import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/foundation.dart';

import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/log_redaction.dart';
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

  /// A request the page made ITSELF, caught as it happened, with the response
  /// body. This is the richest kind: a single-page app talks to its API through
  /// fetch/XHR, and those calls carry the exact headers and query shape the
  /// site uses. onLoadResource only ever reported the URL, and for a Next.js
  /// app it does not report client-side calls at all.
  xhr,
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
    _resetJournal();
    _bump();
  }

  void stop() {
    _recording = false;
    _bump();
  }

  void clear() {
    _entries.clear();
    _seenResources.clear();
    _fetchedUrls.clear();
    _seenXhr.clear();
    _totalChars = 0;
    _recording = false;
    _deleteJournal();
    _bump();
  }

  void _bump() => revision.value++;

  void _add(CaptureEntry entry) {
    _entries.add(entry);
    _totalChars += entry.size;
    _appendToJournal(entry);
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

  /// The live recording webview, while one is open.
  ///
  /// Bodies are fetched THROUGH it rather than beside it. The previous version
  /// pulled them with Dio after the webview had closed, which on a
  /// Cloudflare-protected site failed every time: Dio has none of the
  /// clearance the webview earned, so every request came back as an opaque
  /// `DioException [unknown]: null`. That is what happened on hentaipaw.com -
  /// the capture recorded the URLs and not one body.
  InAppWebViewController? _liveController;

  void attachController(InAppWebViewController controller) => _liveController = controller;

  void detachController() => _liveController = null;

  bool get hasLiveController => _liveController != null;

  /// The script run inside the page to read a URL.
  ///
  /// `credentials: 'include'` is the whole point: the request goes out from the
  /// page's own origin with the page's own cookies, so a site that only answers
  /// cleared clients answers this too.
  @visibleForTesting
  static String fetchScript(String url) {
    final String encoded = jsonEncode(url);
    return '''
(async () => {
  try {
    const r = await fetch($encoded, { credentials: 'include' });
    const t = await r.text();
    return JSON.stringify({
      ok: true,
      status: r.status,
      contentType: r.headers.get('content-type'),
      body: t,
    });
  } catch (e) {
    return JSON.stringify({ ok: false, error: String(e) });
  }
})()
''';
  }

  /// Reads what the page's own fetch returned. Separated so the shapes the
  /// bridge hands back - a JSON string on one platform, a decoded Map on
  /// another, null when the script threw - can be tested directly.
  @visibleForTesting
  static ({int? status, String? contentType, String? body, String? error})? parseFetchResult(
    dynamic raw,
  ) {
    if (raw == null) return null;
    dynamic decoded = raw;
    if (raw is String) {
      if (raw.trim().isEmpty) return null;
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        return null;
      }
    }
    if (decoded is! Map) return null;
    if (decoded['ok'] != true) {
      return (status: null, contentType: null, body: null, error: decoded['error']?.toString());
    }
    return (
      status: (decoded['status'] as num?)?.toInt(),
      contentType: decoded['contentType']?.toString(),
      body: decoded['body']?.toString() ?? '',
      error: null,
    );
  }

  /// Fetches a URL from inside the live page. Returns null when there is no
  /// webview to run it in, or the page refused.
  Future<CaptureEntry?> fetchBodyInPage(String url) async {
    final InAppWebViewController? controller = _liveController;
    if (controller == null || url.isEmpty) return null;
    try {
      final raw = await controller.evaluateJavascript(source: fetchScript(url));
      final result = parseFetchResult(raw);
      if (result == null || result.error != null) return null;
      final ({String body, int? from}) capped = _cap(redact(result.body ?? ''));
      final entry = CaptureEntry(
        kind: CaptureKind.fetch,
        url: url,
        status: result.status,
        contentType: result.contentType,
        body: capped.body,
        truncatedFrom: capped.from,
      );
      _add(entry);
      return entry;
    } catch (e, s) {
      Logger.Inst().log(
        'in-page capture fetch failed for $url: $e',
        'SourceCaptureHandler',
        'fetchBodyInPage',
        LogTypes.exception,
        s: s,
      );
      return null;
    }
  }

  /// The name the page posts intercepted traffic back through.
  static const String bridgeName = 'lsCapture';

  /// Wraps fetch and XMLHttpRequest so every call the page makes is reported
  /// with its response body.
  ///
  /// Injected at document start, before the app's own bundle runs, or the very
  /// first API call - usually the one that fetches the listing - is missed.
  /// Media and static assets are skipped: they are large, uninteresting, and
  /// would blow the capture size limit.
  static const String networkHookScript = r'''
(() => {
  if (window.__lsCaptureInstalled) return;
  window.__lsCaptureInstalled = true;
  const SKIP = /\.(jpe?g|png|webp|avif|gif|svg|ico|css|woff2?|ttf|otf|mp4|webm|m3u8|ts)(\?|$)/i;
  const report = (method, url, status, contentType, body) => {
    try {
      if (!url || SKIP.test(url)) return;
      window.flutter_inappwebview.callHandler(
        'lsCapture',
        { method, url, status, contentType, body: (body || '').slice(0, 200000) },
      );
    } catch (e) {}
  };

  const origFetch = window.fetch;
  window.fetch = async function (...args) {
    const res = await origFetch.apply(this, args);
    try {
      const req = args[0];
      const url = typeof req === 'string' ? req : (req && req.url) || '';
      const method = (args[1] && args[1].method) || (req && req.method) || 'GET';
      const clone = res.clone();
      clone.text().then((t) =>
        report(method, url, res.status, res.headers.get('content-type'), t)
      ).catch(() => {});
    } catch (e) {}
    return res;
  };

  const origOpen = XMLHttpRequest.prototype.open;
  const origSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function (method, url) {
    this.__lsMethod = method;
    this.__lsUrl = url;
    return origOpen.apply(this, arguments);
  };
  XMLHttpRequest.prototype.send = function () {
    this.addEventListener('load', () => {
      try {
        report(
          this.__lsMethod || 'GET',
          this.__lsUrl || this.responseURL,
          this.status,
          this.getResponseHeader('content-type'),
          typeof this.responseText === 'string' ? this.responseText : '',
        );
      } catch (e) {}
    });
    return origSend.apply(this, arguments);
  };
})();
''';

  /// Records one call the page made. Deduplicated by method+url, since a feed
  /// refetches the same endpoint as it pages.
  void recordXhr({
    required String method,
    required String url,
    int? status,
    String? contentType,
    String? body,
  }) {
    if (!_recording || url.isEmpty) return;
    if (!_seenXhr.add('$method $url')) return;
    final ({String body, int? from}) capped = _cap(redact(body ?? ''));
    _add(
      CaptureEntry(
        kind: CaptureKind.xhr,
        url: '$method $url',
        status: status,
        contentType: contentType,
        body: capped.body,
        truncatedFrom: capped.from,
      ),
    );
  }

  final Set<String> _seenXhr = {};

  /// Resource URLs whose bodies have not been read yet.
  final Set<String> _fetchedUrls = {};

  List<String> get pendingResources =>
      [for (final url in interestingResources) if (!_fetchedUrls.contains(url)) url];

  /// Reads every not-yet-read interesting resource from inside the live page.
  ///
  /// Called on each load stop, so a body is taken while its page still holds
  /// the clearance that made it reachable.
  Future<int> fetchPendingBodies({int limit = 40}) async {
    if (!hasLiveController) return 0;
    int done = 0;
    for (final url in pendingResources.take(limit)) {
      _fetchedUrls.add(url);
      if (await fetchBodyInPage(url) != null) done++;
    }
    return done;
  }

  /// Pulls a URL through the app's own HTTP stack. Only reached when there is
  /// no live webview to fetch from; on a protected site it will usually fail,
  /// which is why the in-page path is tried first.
  Future<CaptureEntry?> fetchBody(String url) async {
    if (url.isEmpty) return null;
    final CaptureEntry? inPage = await fetchBodyInPage(url);
    if (inPage != null) return inPage;
    try {
      final response = await DioNetwork.get(
        url,
        headers: {
          'User-Agent': Tools.browserUserAgent,
          'Referer': _target.isEmpty ? url : _target,
          'Accept': '*/*',
        },
        options: Options(
          // The default response type is json, which would put an HTML page
          // through the json transformer on its way in. Plain keeps whatever
          // the server actually sent.
          responseType: ResponseType.plain,
          // A 403 or a 404 is itself worth recording — it says the endpoint
          // exists but wants something we are not sending.
          validateStatus: (_) => true,
        ),
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

  /// The most that can be put on the clipboard.
  ///
  /// Android moves clipboard data across a Binder transaction, which caps out
  /// around 1MB for the whole parcel. A 5.7MB capture threw
  /// TransactionTooLargeException and the Copy button did nothing at all — no
  /// error, no clipboard, just silence. Anything larger has to go out as a file.
  static const int maxClipboardChars = 256 * 1024;

  /// A copyable form of the capture: the whole thing when it fits, otherwise
  /// the parts that identify the site's API, which is what a handler is written
  /// from. Never silently truncated — the result says what was left out.
  String buildClipboardBundle() {
    final String full = buildBundle();
    if (full.length <= maxClipboardChars) return full;

    final StringBuffer out = StringBuffer()
      ..writeln('LoliSnatcher source capture (SHORTENED FOR THE CLIPBOARD)')
      ..writeln('full capture: ${full.length} chars — too large for the clipboard,')
      ..writeln('use Share to send the complete file instead.')
      ..writeln();

    // The API calls first: they are the capture's whole point, and they are
    // small next to the page markup and script bodies.
    for (final entry in _entries) {
      if (entry.kind != CaptureKind.xhr) continue;
      out
        ..writeln('===== ${entry.kind.name.toUpperCase()} ${entry.status ?? ''} '
            '${entry.contentType ?? ''}')
        ..writeln('===== ${entry.url}')
        ..writeln(entry.body ?? '')
        ..writeln();
      if (out.length > maxClipboardChars) break;
    }

    final String head = out.toString();
    if (head.length <= maxClipboardChars) return head;
    return '${head.substring(0, maxClipboardChars - 80)}\n\n===== CUT HERE — use Share for the rest';
  }

  ({String body, int? from}) _cap(String body) {
    if (body.length <= maxBodyChars) return (body: body, from: null);
    return (body: body.substring(0, maxBodyChars), from: body.length);
  }

  // ── the journal ───────────────────────────────────────────────────────
  //
  // A capture is gathered by browsing a heavy site inside a webview, which is
  // exactly the situation Android reaps an app in. Held only in memory, a
  // session that took ten minutes to collect would vanish with no indication
  // why - and the developer-mode flag that reveals this tool is not persisted
  // either, so the app would come back with neither the capture nor an obvious
  // way back to it.
  //
  // So every entry is appended to a journal as it arrives. Append-only, one
  // JSON object per line: rewriting a whole 8MB bundle on every page load
  // would be far too much writing, and a half-written journal costs at most
  // its last line rather than the whole session.

  static const String journalName = 'source-capture-session.jsonl';

  /// Writes are chained rather than fired off in parallel, so two entries
  /// arriving together cannot interleave halfway through a line.
  Future<void> _journalQueue = Future.value();

  /// Completes once every journal write queued so far has landed.
  ///
  /// Recording is deliberately fire-and-forget so the UI never waits on disk,
  /// which leaves no moment a caller can observe. Tests await this instead of
  /// sleeping — a fixed delay passes alone and fails the moment the machine is
  /// busy, which is exactly the kind of flake that gets a real failure ignored.
  Future<void> get journalFlushed => _journalQueue;

  File? get _journalFile {
    try {
      return File('${SettingsHandler.instance.path}$journalName');
    } catch (_) {
      return null;
    }
  }

  void _resetJournal() {
    final File? file = _journalFile;
    if (file == null) return;
    _journalQueue = _journalQueue.then((_) async {
      try {
        await file.writeAsString(
          '${jsonEncode({'target': _target, 'started': DateTime.now().toIso8601String()})}\n',
          flush: true,
        );
      } catch (_) {}
    });
  }

  void _appendToJournal(CaptureEntry entry) {
    final File? file = _journalFile;
    if (file == null) return;
    _journalQueue = _journalQueue.then((_) async {
      try {
        await file.writeAsString(
          '${jsonEncode(_entryToJson(entry))}\n',
          mode: FileMode.append,
          flush: true,
        );
      } catch (_) {}
    });
  }

  void _deleteJournal() {
    final File? file = _journalFile;
    if (file == null) return;
    _journalQueue = _journalQueue.then((_) async {
      try {
        if (file.existsSync()) await file.delete();
      } catch (_) {}
    });
  }

  /// Drops what is in memory while leaving the journal alone — how the world
  /// looks after the process is killed. Tests use this to prove a session
  /// really does come back from disk rather than from a leftover field.
  @visibleForTesting
  void clearMemoryOnlyForTests() {
    _entries.clear();
    _seenResources.clear();
    _totalChars = 0;
    _target = '';
    _recording = false;
    _bump();
  }

  /// True when a previous session is sitting on disk waiting to be picked up.
  bool get hasRecoverableSession {
    final File? file = _journalFile;
    return file != null && file.existsSync() && file.lengthSync() > 0;
  }

  /// Reads an interrupted session back in. A trailing half-written line is
  /// dropped rather than failing the whole restore - losing the last page is
  /// recoverable by revisiting it, losing all of them is not.
  Future<int> restoreSession() async {
    final File? file = _journalFile;
    if (file == null || !file.existsSync()) return 0;

    _entries.clear();
    _seenResources.clear();
    _totalChars = 0;

    int skipped = 0;
    final List<String> lines = await file.readAsLines();
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map) continue;
        if (decoded.containsKey('started')) {
          _target = decoded['target']?.toString() ?? '';
          continue;
        }
        final CaptureEntry? entry = _entryFromJson(decoded);
        if (entry == null) continue;
        if (entry.kind == CaptureKind.resource && !_seenResources.add(entry.url)) continue;
        // A page recorded more than once replaces its earlier copy, matching
        // what happened in memory as the page hydrated.
        if (entry.kind == CaptureKind.page) {
          final int existing = _entries.indexWhere(
            (e) => e.kind == CaptureKind.page && e.url == entry.url,
          );
          if (existing != -1) {
            _totalChars -= _entries[existing].size;
            _entries.removeAt(existing);
          }
        }
        _entries.add(entry);
        _totalChars += entry.size;
      } catch (_) {
        skipped++;
      }
    }

    _recording = false;
    _bump();
    return skipped;
  }

  static Map<String, dynamic> _entryToJson(CaptureEntry entry) => {
    'kind': entry.kind.name,
    'url': entry.url,
    'status': ?entry.status,
    'contentType': ?entry.contentType,
    'truncatedFrom': ?entry.truncatedFrom,
    'body': ?entry.body,
  };

  static CaptureEntry? _entryFromJson(Map json) {
    final String url = json['url']?.toString() ?? '';
    if (url.isEmpty) return null;
    final CaptureKind kind = CaptureKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => CaptureKind.resource,
    );
    return CaptureEntry(
      kind: kind,
      url: url,
      status: (json['status'] as num?)?.toInt(),
      contentType: json['contentType']?.toString(),
      body: json['body']?.toString(),
      truncatedFrom: (json['truncatedFrom'] as num?)?.toInt(),
    );
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
  /// Delegates to the shared redactor so a capture and a log strip exactly the
  /// same things.
  static String redact(String input, {List<String>? extraSecrets}) =>
      redactSecrets(input, extraSecrets: extraSecrets);

  // ── the bundle ────────────────────────────────────────────────────────

  /// One plain-text file: readable as-is, pasteable, and unambiguous about
  /// where each captured thing starts and ends.
  String buildBundle({DateTime? now}) {
    final StringBuffer out = StringBuffer();
    final DateTime stamp = now ?? DateTime.now();

    out.writeln('LoliSnatcher source capture');
    out.writeln('target: ${_target.isEmpty ? '(none)' : _target}');
    out.writeln('captured: ${stamp.toUtc().toIso8601String()}');
    final int xhrCount = _entries.where((e) => e.kind == CaptureKind.xhr).length;
    out.writeln(
      'pages: $pageCount  api calls: $xhrCount  fetched bodies: $fetchCount  '
      'resource urls: $resourceCount',
    );
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

    // The page's own API calls, listed together. On a single-page app this is
    // the handler's entire contract in one block.
    final List<CaptureEntry> calls = [
      for (final entry in _entries)
        if (entry.kind == CaptureKind.xhr) entry,
    ];
    if (calls.isNotEmpty) {
      out.writeln('--- api calls the page made itself ---');
      for (final call in calls) {
        out.writeln('  ${call.status ?? '???'}  ${call.url}');
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
