import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/boorus/kemono_api.dart';
import 'package:lolisnatcher/src/data/kemono_creator.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// Progress of an index refresh.
class KemonoIndexState {
  const KemonoIndexState({
    this.running = false,
    this.inserted = 0,
    this.total = 0,
    this.error,
    this.refreshedAt = 0,
    this.count = 0,
  });

  final bool running;
  final int inserted;
  final int total;
  final String? error;

  /// When the last full refresh finished (ms), 0 when never.
  final int refreshedAt;

  /// Rows in the table.
  final int count;

  double? get progress => total == 0 ? null : (inserted / total).clamp(0, 1);

  KemonoIndexState copyWith({bool? running, int? inserted, int? total, String? error, int? refreshedAt, int? count}) =>
      KemonoIndexState(
        running: running ?? this.running,
        inserted: inserted ?? this.inserted,
        total: total ?? this.total,
        error: error,
        refreshedAt: refreshedAt ?? this.refreshedAt,
        count: count ?? this.count,
      );
}

/// kemono's creator index, kept in the app's database so the Artists page,
/// tag suggestions and the creator name on every card come from the phone
/// rather than from a 3.4 MB download per look-up.
///
/// `/api/v1/creators` is one request for every creator the site knows
/// (108,063 rows on 2026-09-04). It is decoded in an isolate, written in
/// batches, and rows the new download no longer lists are pruned afterwards;
/// the table stays usable while a refresh runs. Refreshed on demand and when
/// older than [staleAfter].
class KemonoCreatorStore {
  KemonoCreatorStore._();

  static final KemonoCreatorStore instance = KemonoCreatorStore._();

  static const String metaFile = 'kemono_creators.json';
  static const Duration staleAfter = Duration(hours: 24);
  static const int batch = 2000;
  static const int nameCacheSize = 5000;

  final ValueNotifier<KemonoIndexState> state = ValueNotifier(const KemonoIndexState());
  final Map<String, String> _names = {};
  Future<void>? _running;
  bool _metaLoaded = false;

  File? get _meta {
    try {
      return File('${SettingsHandler.instance.path}$metaFile');
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadMeta() async {
    if (_metaLoaded) return;
    _metaLoaded = true;
    int refreshedAt = 0;
    try {
      final File? file = _meta;
      if (file != null && file.existsSync()) {
        final decoded = jsonDecode(file.readAsStringSync());
        if (decoded is Map) refreshedAt = int.tryParse(decoded['refreshedAt']?.toString() ?? '') ?? 0;
      }
    } catch (_) {}
    state.value = state.value.copyWith(refreshedAt: refreshedAt, count: await count());
  }

  void _saveMeta(int refreshedAt, int count) {
    try {
      _meta?.writeAsStringSync(jsonEncode({'refreshedAt': refreshedAt, 'count': count}));
    } catch (_) {}
  }

  bool get isStale =>
      state.value.count == 0 ||
      DateTime.now().millisecondsSinceEpoch - state.value.refreshedAt > staleAfter.inMilliseconds;

  /// Refreshes when the table is empty or old. Never more than one job.
  Future<void> ensureFresh({bool force = false}) async {
    await _loadMeta();
    if (!force && !isStale) return;
    return refresh();
  }

  Future<void> refresh() {
    return _running ??= _refresh().whenComplete(() => _running = null);
  }

  /// The compute entry point: the index body → compact rows
  /// `[service, id, name, indexed, updated, favorited]`.
  @visibleForTesting
  static List<List<Object?>> parseRows(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List) return const [];
    final List<List<Object?>> out = [];
    for (final row in decoded) {
      if (row is! Map) continue;
      final String service = row['service']?.toString() ?? '';
      final String id = row['id']?.toString() ?? '';
      if (service.isEmpty || id.isEmpty) continue;
      out.add([
        service,
        id,
        row['name']?.toString() ?? '',
        KemonoCreator.epochOf(row['indexed']),
        KemonoCreator.epochOf(row['updated']),
        int.tryParse(row['favorited']?.toString() ?? '') ?? 0,
      ]);
    }
    return out;
  }

  Future<void> _refresh() async {
    await _loadMeta();
    state.value = state.value.copyWith(running: true, inserted: 0, total: 0);
    final int startedAt = DateTime.now().millisecondsSinceEpoch;
    _log('index refresh started');
    try {
      final Response response = await DioNetwork.get(
        '${KemonoApi.api}/creators',
        headers: KemonoApi.headers(null),
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 180),
          validateStatus: (_) => true,
        ),
      );
      if (response.statusCode != 200) {
        throw KemonoApiException(response.statusCode ?? -1, KemonoApi.describeStatus(response.statusCode ?? -1, ''));
      }
      final String body = response.data?.toString() ?? '';
      final List<List<Object?>> rows = await compute(parseRows, body);
      state.value = state.value.copyWith(total: rows.length);
      _log('index: ${rows.length} creators decoded (${(body.length / 1048576).toStringAsFixed(1)} MB)');
      final db = SettingsHandler.instance.dbHandler;
      int inserted = 0;
      for (int i = 0; i < rows.length; i += batch) {
        final List<List<Object?>> slice = rows.sublist(i, (i + batch).clamp(0, rows.length));
        await db.upsertKemonoCreators(slice, startedAt);
        inserted += slice.length;
        state.value = state.value.copyWith(inserted: inserted);
        // Let the UI breathe between batches.
        await Future.delayed(Duration.zero);
      }
      final int pruned = await db.pruneKemonoCreators(seenBefore: startedAt);
      final int total = await count();
      final int finishedAt = DateTime.now().millisecondsSinceEpoch;
      _saveMeta(finishedAt, total);
      _names.clear();
      state.value = state.value.copyWith(running: false, refreshedAt: finishedAt, count: total, inserted: inserted);
      _log('index refresh done: $total creators, $pruned pruned, ${(finishedAt - startedAt) ~/ 1000}s');
    } catch (e, s) {
      Logger.Inst().log('index refresh failed: $e', 'KemonoCreatorStore', 'refresh', LogTypes.exception, s: s);
      state.value = state.value.copyWith(running: false, error: e.toString(), count: await count());
    }
  }

  Future<int> count() async {
    try {
      return await SettingsHandler.instance.dbHandler.countKemonoCreators();
    } catch (_) {
      return 0;
    }
  }

  /// Loads the names of [pairs] into the cache so [nameOf] can answer.
  Future<void> warmNames(Iterable<({String service, String id})> pairs) async {
    final List<({String service, String id})> missing = [
      for (final p in pairs.toSet())
        if (!_names.containsKey('${p.service}:${p.id}')) p,
    ];
    if (missing.isEmpty) return;
    try {
      final rows = await SettingsHandler.instance.dbHandler.getKemonoCreatorsByKeys(missing);
      for (final row in rows) {
        final c = KemonoCreator.fromRow(row);
        _remember(c.key, c.name);
      }
    } catch (_) {}
  }

  void _remember(String key, String name) {
    if (_names.length >= nameCacheSize) _names.remove(_names.keys.first);
    _names[key] = name;
  }

  /// The creator's name when the cache holds it; null otherwise.
  String? nameOf(String service, String id) {
    final String? name = _names['$service:$id'];
    return (name == null || name.isEmpty) ? null : name;
  }

  Future<KemonoCreator?> get(String service, String id) async {
    try {
      final rows = await SettingsHandler.instance.dbHandler.getKemonoCreatorsByKeys([(service: service, id: id)]);
      if (rows.isEmpty) return null;
      final c = KemonoCreator.fromRow(rows.first);
      _remember(c.key, c.name);
      return c;
    } catch (_) {
      return null;
    }
  }

  /// The most-favourited creator called exactly [name] (case-insensitive).
  Future<KemonoCreator?> findByName(String name) async {
    try {
      final rows = await SettingsHandler.instance.dbHandler.findKemonoCreatorsByName(name.trim(), limit: 1);
      if (rows.isEmpty) return null;
      return KemonoCreator.fromRow(rows.first);
    } catch (_) {
      return null;
    }
  }

  Future<List<KemonoCreator>> search(
    String text, {
    Set<String>? services,
    String sort = 'favorited',
    int limit = 60,
    int offset = 0,
    Set<String>? onlyKeys,
  }) async {
    try {
      final rows = await SettingsHandler.instance.dbHandler.queryKemonoCreators(
        nameLike: text.trim().isEmpty ? null : text.trim(),
        services: (services == null || services.isEmpty) ? null : services,
        orderBy: sort,
        keys: onlyKeys,
        limit: limit,
        offset: offset,
      );
      final List<KemonoCreator> out = [for (final row in rows) KemonoCreator.fromRow(row)];
      for (final c in out) {
        _remember(c.key, c.name);
      }
      return out;
    } catch (e, s) {
      Logger.Inst().log('creator search failed: $e', 'KemonoCreatorStore', 'search', LogTypes.exception, s: s);
      return const [];
    }
  }

  void resetForTests() {
    _names.clear();
    _metaLoaded = true;
    state.value = const KemonoIndexState();
  }

  static void _log(String message) =>
      Logger.Inst().log('kemono creators: $message', 'KemonoCreatorStore', 'index', LogTypes.booruHandlerInfo);
}
