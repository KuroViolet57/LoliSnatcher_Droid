import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/boorus/kemono_api.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// One file host's last probe.
class KemonoHostStatus {
  const KemonoHostStatus({
    required this.host,
    required this.ok,
    required this.checkedAt,
    this.error,
  });

  /// `n3.kemono.cr`
  final String host;
  final bool ok;
  final String? error;
  final DateTime checkedAt;

  String get shortName => host.split('.').first;
}

/// Reachability of kemono's file hosts (`n1..n4.kemono.cr`) from THIS network.
///
/// kemono's API and thumbnails sit behind DDoS-Guard and answer everywhere;
/// the files live on plain hosts that some networks cannot reach at all (the
/// connection just hangs — the site's own post pages break the same way
/// there). Without this the viewer spun until its timeout on every file. One
/// HEAD per host, in parallel, with a short timeout; the result feeds the
/// viewer's error screen and the sidebar's footer.
class KemonoFileHosts {
  KemonoFileHosts._();

  static final KemonoFileHosts instance = KemonoFileHosts._();

  /// A result older than this says nothing about the network any more.
  static const Duration freshFor = Duration(minutes: 10);
  static const Duration probeTimeout = Duration(seconds: 8);

  final ValueNotifier<Map<String, KemonoHostStatus>> state = ValueNotifier(const {});
  final ValueNotifier<bool> running = ValueNotifier(false);
  Future<void>? _inFlight;

  /// Tests swap the network probe out.
  @visibleForTesting
  Future<KemonoHostStatus> Function(String host)? probeOverride;

  static List<String> get hosts => [for (final s in KemonoApi.fileServers) Uri.parse(s.host).host];

  static bool isFileHost(String host) => hosts.contains(host.toLowerCase());

  bool get checked => state.value.isNotEmpty;

  DateTime? get checkedAt {
    DateTime? newest;
    for (final s in state.value.values) {
      if (newest == null || s.checkedAt.isAfter(newest)) newest = s.checkedAt;
    }
    return newest;
  }

  bool get isFresh {
    final DateTime? at = checkedAt;
    return at != null && DateTime.now().difference(at) < freshFor;
  }

  /// Probes every host once; a fresh result is reused unless [force].
  Future<void> check({bool force = false}) {
    if (!force && isFresh) return Future.value();
    return _inFlight ??= _run().whenComplete(() => _inFlight = null);
  }

  Future<void> _run() async {
    running.value = true;
    try {
      final List<KemonoHostStatus> results = await Future.wait(hosts.map(probeOverride ?? _probe));
      state.value = {for (final r in results) r.host: r};
      final bool anyDown = results.any((r) => !r.ok);
      Logger.Inst().log(
        'file hosts: ${results.map((r) => '${r.shortName} ${r.ok ? 'ok' : r.error}').join(', ')}',
        'KemonoFileHosts',
        'check',
        anyDown ? LogTypes.networkError : LogTypes.booruHandlerInfo,
      );
    } finally {
      running.value = false;
    }
  }

  Future<KemonoHostStatus> _probe(String host) async {
    final Dio dio = Dio(
      BaseOptions(
        connectTimeout: probeTimeout,
        receiveTimeout: probeTimeout,
        sendTimeout: probeTimeout,
        validateStatus: (_) => true,
        headers: {'User-Agent': Tools.browserUserAgent, 'Referer': '${KemonoApi.site}/'},
      ),
    );
    try {
      // Any HTTP answer at all means the host is reachable; only the
      // transport failing counts as "down".
      await dio.head('https://$host/');
      return KemonoHostStatus(host: host, ok: true, checkedAt: DateTime.now());
    } on DioException catch (e) {
      final String why = switch (e.type) {
        DioExceptionType.connectionTimeout => 'connection timed out',
        DioExceptionType.connectionError => 'connection failed',
        DioExceptionType.receiveTimeout => 'no answer',
        DioExceptionType.sendTimeout => 'no answer',
        _ => e.type.name,
      };
      return KemonoHostStatus(host: host, ok: false, error: why, checkedAt: DateTime.now());
    } catch (e) {
      return KemonoHostStatus(host: host, ok: false, error: e.toString(), checkedAt: DateTime.now());
    } finally {
      dio.close();
    }
  }

  static String ago(DateTime at) {
    final Duration d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    return '${d.inHours} h ago';
  }

  /// The text the viewer shows instead of loading, when [url]'s host failed a
  /// fresh probe. Null = nothing known against it.
  String? noticeFor(String url) {
    final String host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    final KemonoHostStatus? s = state.value[host];
    if (s == null || s.ok) return null;
    if (DateTime.now().difference(s.checkedAt) > freshFor) return null;
    return "kemono's file host $host is not reachable from this network (${s.error}, ${ago(s.checkedAt)}). "
        "The site's own images fail here too. Try Private DNS (dns.google) or another network, then restart.";
  }

  /// One line for the sidebar.
  String summary() {
    if (state.value.isEmpty) return running.value ? 'Checking the file hosts…' : 'File hosts: not checked';
    final List<KemonoHostStatus> rows = state.value.values.toList()..sort((a, b) => a.host.compareTo(b.host));
    final String parts = rows.map((r) => '${r.shortName} ${r.ok ? '✓' : '✗'}').join('  ');
    final List<String> errors = rows.where((r) => !r.ok).map((r) => r.error ?? '?').toSet().toList();
    final String tail = errors.isEmpty ? 'all reachable' : errors.join(', ');
    return '$parts · $tail · ${ago(checkedAt!)}';
  }

  @visibleForTesting
  void resetForTests() {
    state.value = const {};
    running.value = false;
    _inFlight = null;
    probeOverride = null;
  }
}
