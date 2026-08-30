import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// What a single captured thing is.
enum CaptureKind {
  /// The rendered HTML of a page, read out of the webview after it settled.
  /// For a server-rendered site this is the markup a parser will see; for a
  /// Next.js or SvelteKit site it is the hydrated DOM, which is usually easier
  /// to read than the raw payload.
  page,

  /// A URL the page asked for, seen by the webview. No body - the point of
  /// these is to reveal that an API exists at all.
  resource,

  /// A body fetched afterwards through the app's own HTTP stack, using the
  /// cookies the webview earned. This is where an API response ends up.
  fetch,
}

@immutable
class CaptureEntry {
  const CaptureEntry({
    required this.kind,
    required this.url,
    this.status,
    this.contentType,
    this.body,
    this.truncatedFrom,
  });

  final CaptureKind kind;
  final String url;
  final int? status;
  final String? contentType;
  final String? body;

  /// Set when [body] was cut down, to the size it had before.
  final int? truncatedFrom;

  int get size => body?.length ?? 0;
}

/// Collects everything needed to write a booru handler for a site this machine
/// cannot reach on its own.
///
/// The problem this exists for: a site behind a bot filter answers a plain HTTP
/// request with a challenge page, so there is no way to see its real markup
/// from a headless environment - and a handler written without seeing the
/// markup is a guess. The app on a real device already solves that challenge in
/// a webview and keeps the clearance cookie, so it CAN see the site. This
/// records what it sees into one file that can be sent on.
///
/// Nothing here is specific to any one site.
class SourceCaptureHandler {
  SourceCaptureHandler._();

  static final SourceCaptureHandler instance = SourceCaptureHandler._();

  /// Per-body cap. Gallery pages run past 200KB and a hydration payload can be
  /// much larger; past this the tail is rarely the interesting part.
  static const int maxBodyChars = 512 * 1024;

  /// Total cap across the session, so a long browse cannot fill the device.
  static const int maxTotalChars = 8 * 1024 * 1024;

  final List<CaptureEntry> _entries = [];
  final Set<String> _seenResources = {};
  int _totalChars = 0;

  /// Notified whenever the session changes, so the page can repaint without
  /// pulling GetX into a debug tool.
  final ValueNotifier<int> revision = ValueNotifier(0);

  bool _recording = false;
  bool get isRecording => _recording;

  String _target = '';
  String get target => _target;

  List<CaptureEntry> get entries => List.unmodifiable(_entries);

  int get pageCount => _entries.where((e) => e.kind == CaptureKind.page).length;
  int get resourceCount => _entries.where((e) => e.kind == CaptureKind.resource).length;
  int get fetchCount => _entries.where((e) => e.kind == CaptureKind.fetch).length;
  int get totalChars => _totalChars;

  void start(String target) {
    _entries.clear();
    _seenResources.clear();
    _totalChars = 0;
    _target = target;
    _recording = true;
    _bump();
  }

  void stop() {
    _recording = false;
    _bump();
  }

  void clear() {
    _entries.clear();
    _seenResources.clear();
    _totalChars = 0;
    _recording = false;
    _bump();
  }

  void _bump() => revision.value++;

  void _add(CaptureEntry entry) {
    _entries.add(entry);
    _totalChars += entry.size;
    _bump();
  }

  // ── recording ─────────────────────────────────────────────────────────

  /// The rendered HTML of a page. Re-recording the same URL replaces the older
  /// copy: a single-page app fires load-stop repeatedly as it hydrates, and the
  /// last version is the settled one.
  void recordPage(String url, String? html) {
    if (!_recording || html == null || html.trim().isEmpty) return;

    final int existing = _entries.indexWhere(
      (e) => e.kind == CaptureKind.page && e.url == url,
    );
    if (existing != -1) {
      _totalChars -= _entries[existing].size;
      _entries.removeAt(existing);
    }
    if (_totalChars >= maxTotalChars) return;

    final ({String body, int? from}) capped = _cap(redact(html));
    _add(
      CaptureEntry(
        kind: CaptureKind.page,
        url: url,
        contentType: 'text/html (rendered)',
        body: capped.body,
        truncatedFrom: capped.from,
      ),
    );
  }

  /// A URL the page asked for. Deduplicated, since a listing pulls the same
  /// thumbnail host dozens of times.
  void recordResource(String url) {
    if (!_recording || url.isEmpty) return;
    if (!_seenResources.add(url)) return;
    _add(CaptureEntry(kind: CaptureKind.resource, url: url));
  }

  /// Pulls a URL through the app's own HTTP stack, which carries the cookies
  /// the webview earned - so this reaches an API that a plain request could
  /// not. Used to turn a bare resource URL into an actual response body.
  Future<CaptureEntry?> fetchBody(String url) async {
    if (url.isEmpty) return null;
    try {
      final response = await DioNetwork.get(
        url,
        headers: {
          'User-Agent': Tools.browserUserAgent,
          'Referer': _target.isEmpty ? url : _target,
          'Accept': '*/*',
        },
      );
      final ({String body, int? from}) capped = _cap(redact(response.data?.toString() ?? ''));
      final entry = CaptureEntry(
        kind: CaptureKind.fetch,
        url: url,
        status: response.statusCode,
        contentType: response.headers.value('content-type'),
        body: capped.body,
        truncatedFrom: capped.from,
      );
      _add(entry);
      return entry;
    } catch (e, s) {
      Logger.Inst().log(
        'capture fetch failed for $url: $e',
        'SourceCaptureHandler',
        'fetchBody',
        LogTypes.exception,
        s: s,
      );
      final entry = CaptureEntry(kind: CaptureKind.fetch, url: url, body: 'FETCH FAILED: $e');
      _add(entry);
      return entry;
    }
  }

  /// Resource URLs worth pulling a body for: the ones that look like data
  /// rather than pictures or styling. This is what turns "the site calls
  /// something" into "here is what it answers".
  List<String> get interestingResources {
    const List<String> mediaExtensions = [
      '.jpg', '.jpeg', '.png', '.webp', '.avif', '.gif', '.svg', '.ico',
      '.css', '.woff', '.woff2', '.ttf', '.otf', '.mp4', '.webm', '.m3u8',
    ];
    return [
      for (final entry in _entries)
        if (entry.kind == CaptureKind.resource)
          if (!mediaExtensions.any((ext) => entry.url.toLowerCase().split('?').first.endsWith(ext)))
            entry.url,
    ];
  }

  ({String body, int? from}) _cap(String body) {
    if (body.length <= maxBodyChars) return (body: body, from: null);
    return (body: body.substring(0, maxBodyChars), from: body.length);
  }

  // ── redaction ─────────────────────────────────────────────────────────

  /// Strips anything that identifies the person who ran the capture, because
  /// the whole point of the bundle is that it gets sent to someone else.
  ///
  /// This is not a guarantee against every possible leak - a page can print a
  /// username anywhere - but it removes the things that are certain to be
  /// there: the clearance and session cookies the site just issued, and every
  /// credential configured in this install.
  @visibleForTesting
  static String redact(String input, {List<String>? extraSecrets}) {
    if (input.isEmpty) return input;
    String out = input;

    // Cookie values, wherever they are spelled out.
    for (final name in const [
      'cf_clearance',
      'cf_bm',
      '__cf_bm',
      'session',
      'sessionid',
      'session_id',
      'PHPSESSID',
      'csrftoken',
      'csrf_token',
      'access_token',
      'refresh_token',
      'remember_web',
      'auth_token',
    ]) {
      // NB: replaceAllMapped, not replaceAll — Dart does not expand `$1` in a
      // replaceAll replacement string, so that form writes a literal `$1` over
      // the very text being kept. The secret still goes, but the surrounding
      // markup is mangled and the capture becomes harder to read.
      out = out.replaceAllMapped(
        RegExp('(${RegExp.escape(name)}\\s*[=:]\\s*"?)[^;,"\\s&]+', caseSensitive: false),
        (match) => '${match.group(1)}<redacted>',
      );
    }

    // Bearer / Key headers echoed into a page or a payload.
    out = out.replaceAllMapped(
      RegExp(r'((?:Bearer|Key|Basic|Token)\s+)[A-Za-z0-9._\-+/=]{8,}', caseSensitive: false),
      (match) => '${match.group(1)}<redacted>',
    );

    // Every credential this install has configured, for any booru - a capture
    // of one site should never carry another site's login.
    final List<String> secrets = [...?extraSecrets];
    try {
      for (final booru in SettingsHandler.instance.booruList) {
        for (final value in [booru.apiKey, booru.userID, booru.defTags]) {
          if (value != null && value.trim().length >= 4) secrets.add(value.trim());
        }
      }
    } catch (_) {
      // Settings not available (tests, early startup) - the cookie rules above
      // still apply.
    }
    for (final secret in secrets.toSet()) {
      if (secret.length < 4) continue;
      out = out.replaceAll(secret, '<redacted>');
    }

    return out;
  }

  // ── the bundle ────────────────────────────────────────────────────────

  /// One plain-text file: readable as-is, pasteable, and unambiguous about
  /// where each captured thing starts and ends.
  String buildBundle({DateTime? now}) {
    final StringBuffer out = StringBuffer();
    final DateTime stamp = now ?? DateTime.now();

    out.writeln('LoliSnatcher source capture');
    out.writeln('target: ${_target.isEmpty ? '(none)' : _target}');
    out.writeln('captured: ${stamp.toUtc().toIso8601String()}');
    out.writeln('pages: $pageCount  fetched bodies: $fetchCount  resource urls: $resourceCount');
    out.writeln('credentials and session cookies are redacted');
    out.writeln();

    // Hosts first: the fastest way to see where a site keeps its images and
    // whether it talks to an API on another domain.
    final Map<String, int> hosts = {};
    for (final entry in _entries) {
      if (entry.kind != CaptureKind.resource) continue;
      final String host = Uri.tryParse(entry.url)?.host ?? '';
      if (host.isEmpty) continue;
      hosts[host] = (hosts[host] ?? 0) + 1;
    }
    if (hosts.isNotEmpty) {
      out.writeln('--- hosts the site talked to ---');
      final sorted = hosts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      for (final host in sorted) {
        out.writeln('  ${host.value.toString().padLeft(4)}  ${host.key}');
      }
      out.writeln();
    }

    final List<String> interesting = interestingResources;
    if (interesting.isNotEmpty) {
      out.writeln('--- non-media urls the site requested ---');
      for (final url in interesting) {
        out.writeln('  $url');
      }
      out.writeln();
    }

    for (int i = 0; i < _entries.length; i++) {
      final CaptureEntry entry = _entries[i];
      if (entry.body == null) continue;
      out.writeln('===== [$i] ${entry.kind.name.toUpperCase()} '
          '${entry.status ?? ''} ${entry.contentType ?? ''}');
      out.writeln('===== ${entry.url}');
      if (entry.truncatedFrom != null) {
        out.writeln('===== TRUNCATED to $maxBodyChars of ${entry.truncatedFrom} chars');
      }
      out.writeln(entry.body);
      out.writeln('===== end [$i]');
      out.writeln();
    }

    return out.toString();
  }

  /// Writes the bundle beside the app's other config files and hands back the
  /// path, so it can be shared out.
  Future<String?> writeBundle() async {
    try {
      final String dir = SettingsHandler.instance.path;
      final String host = (Uri.tryParse(_target)?.host ?? 'capture').replaceAll('.', '-');
      final String name =
          'source-capture-$host-${DateTime.now().millisecondsSinceEpoch}.txt';
      final File file = File('$dir$name');
      await file.writeAsString(buildBundle(), flush: true);
      return file.path;
    } catch (e, s) {
      Logger.Inst().log(
        'failed to write capture bundle: $e',
        'SourceCaptureHandler',
        'writeBundle',
        LogTypes.exception,
        s: s,
      );
      return null;
    }
  }

  /// A compact JSON form, for when the text bundle is awkward to move around.
  @visibleForTesting
  String buildJson() => jsonEncode({
    'target': _target,
    'entries': [
      for (final entry in _entries)
        {
          'kind': entry.kind.name,
          'url': entry.url,
          'status': ?entry.status,
          'contentType': ?entry.contentType,
          'truncatedFrom': ?entry.truncatedFrom,
          'body': ?entry.body,
        },
    ],
  });
}
