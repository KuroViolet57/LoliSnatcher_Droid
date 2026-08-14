import 'dart:convert';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// Per-booru tag knowledge: a local snapshot of what each site says its tags
/// are, plus your own corrections on top.
///
/// Two tables, deliberately separate:
///
///   * **BooruTag** — the snapshot. One row per (booru, tag): the type the
///     site itself reports, and its post count. Filled in three ways: pulled
///     a page at a time from the site's tag index, recorded opportunistically
///     whenever the app looks a tag up while browsing, or imported from a
///     snapshot file. Disposable — deleting it costs nothing but re-fetching.
///
///   * **BooruTagOverride** — your corrections. One row per (booru, tag) with
///     `source = 'manual'`. This is *also* the permanent exclusion list: a
///     pair that has a manual row is never touched by automatic correction
///     again, no matter what the site later claims. Precious — it is the only
///     data here that cannot be regenerated.
///
/// Both live in `store.db`, so they ride along in the existing database
/// backup and come back with a restore with no extra plumbing; the snapshot
/// can additionally be exported/imported as a portable JSON file, which is
/// what makes hosted snapshots possible.
///
/// The app's *global* [TagHandler] tag map is untouched by all of this. It
/// stores one type per tag string for the whole app, and overloading it with
/// per-site truth is exactly what corrupts colouring everywhere else, so the
/// per-booru answer is resolved on top of it at read time instead.
class BooruTagStore {
  BooruTagStore._();

  /// Manual overrides, in memory: booruKey -> tag -> type.
  ///
  /// Safe to hold: these are hand-entered, so there are tens of them, not
  /// tens of thousands. The snapshot deliberately stays in the database.
  static final Map<String, Map<String, TagType>> _manual = {};
  static bool _loaded = false;

  static SettingsHandler get _settings => SettingsHandler.instance;

  /// Identity of a booru for tag purposes.
  ///
  /// Keyed on HOST, not on the user-visible name: renaming a booru config
  /// must not orphan your corrections, and two configs pointing at the same
  /// site (different credentials, say) genuinely share a tag database.
  static String keyFor(Booru? booru) {
    if (booru == null) return '';
    final String host = Uri.tryParse(booru.baseURL ?? '')?.host.replaceFirst('www.', '') ?? '';
    if (host.isNotEmpty) return host.toLowerCase();
    // No URL at all (virtual feeds); fall back to something stable-ish.
    return '${booru.type?.name ?? '?'}/${booru.name ?? ''}'.toLowerCase();
  }

  static String _clean(String tag) => tag.trim().toLowerCase();

  // ───────────────────────── manual overrides ─────────────────────────

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    await reload();
  }

  static Future<void> reload() async {
    try {
      _manual.clear();
      final rows = await _settings.dbHandler.getBooruTagOverrides();
      for (final row in rows) {
        final String key = row['booruKey']?.toString() ?? '';
        final String name = row['name']?.toString() ?? '';
        if (key.isEmpty || name.isEmpty) continue;
        _manual.putIfAbsent(key, () => {})[name] = TagType.fromString(row['tagType']?.toString() ?? 'none');
      }
    } catch (e, s) {
      Logger.Inst().log('failed to load tag overrides: $e', 'BooruTagStore', 'reload', LogTypes.exception, s: s);
    }
  }

  /// Your correction for this pair, or null when you never made one.
  static TagType? manualType(String tag, Booru? booru) {
    if (booru == null) return null;
    return _manual[keyFor(booru)]?[_clean(tag)];
  }

  static bool isManual(String tag, Booru? booru) => manualType(tag, booru) != null;

  /// All corrections for one booru (or every booru when null).
  static Map<String, TagType> manualFor(Booru? booru) {
    if (booru == null) {
      return {
        for (final entry in _manual.entries)
          for (final tag in entry.value.entries) '${entry.key}/${tag.key}': tag.value,
      };
    }
    return Map.unmodifiable(_manual[keyFor(booru)] ?? const {});
  }

  static int get manualCount => _manual.values.fold(0, (sum, m) => sum + m.length);

  static Future<void> setManualType(Booru booru, String tag, TagType type) async {
    final String key = keyFor(booru);
    final String name = _clean(tag);
    if (key.isEmpty || name.isEmpty) return;
    _manual.putIfAbsent(key, () => {})[name] = type;
    try {
      await _settings.dbHandler.setBooruTagOverride(key, name, type.name, 'manual');
    } catch (e, s) {
      Logger.Inst().log('failed to save override: $e', 'BooruTagStore', 'setManualType', LogTypes.exception, s: s);
    }
  }

  static Future<void> clearManualType(Booru booru, String tag) async {
    final String key = keyFor(booru);
    final String name = _clean(tag);
    _manual[key]?.remove(name);
    try {
      await _settings.dbHandler.deleteBooruTagOverride(key, name);
    } catch (_) {}
  }

  static Future<void> clearAllManual(Booru? booru) async {
    if (booru == null) {
      _manual.clear();
    } else {
      _manual.remove(keyFor(booru));
    }
    try {
      await _settings.dbHandler.deleteBooruTagOverrides(booru == null ? null : keyFor(booru));
    } catch (_) {}
  }

  // ───────────────────────────── snapshot ─────────────────────────────

  /// Writes rows into the snapshot. Pairs you have corrected by hand are
  /// skipped — that is the permanent exclusion the whole design turns on.
  static Future<int> record(Booru booru, Iterable<BooruTagEntry> entries) async {
    final String key = keyFor(booru);
    if (key.isEmpty) return 0;
    final Map<String, TagType> mine = _manual[key] ?? const {};
    final List<BooruTagEntry> writable = [
      for (final e in entries)
        if (e.name.isNotEmpty && !mine.containsKey(e.name)) e,
    ];
    if (writable.isEmpty) return 0;
    try {
      await _settings.dbHandler.upsertBooruTags(key, writable);
    } catch (e, s) {
      Logger.Inst().log('failed to store tags: $e', 'BooruTagStore', 'record', LogTypes.exception, s: s);
      return 0;
    }
    return writable.length;
  }

  /// One page of the local snapshot, most-used first.
  static Future<List<BooruTagEntry>> browse(
    Booru booru, {
    String query = '',
    TagType? type,
    int limit = 60,
    int offset = 0,
  }) async {
    try {
      final rows = await _settings.dbHandler.queryBooruTags(
        booruKey: keyFor(booru),
        nameLike: query.trim().isEmpty ? null : _clean(query).replaceAll(' ', '_'),
        tagType: type?.name,
        limit: limit,
        offset: offset,
      );
      return [
        for (final row in rows)
          BooruTagEntry(
            name: row['name']?.toString() ?? '',
            tagType: TagType.fromString(row['tagType']?.toString() ?? 'none'),
            count: int.tryParse(row['count']?.toString() ?? '') ?? 0,
            origin: row['source']?.toString() == 'import' ? TagTypeOrigin.inferred : TagTypeOrigin.reported,
            updatedAt: int.tryParse(row['updatedAt']?.toString() ?? '') ?? 0,
          ),
      ];
    } catch (e, s) {
      Logger.Inst().log('browse failed: $e', 'BooruTagStore', 'browse', LogTypes.exception, s: s);
      return const [];
    }
  }

  /// Snapshot rows for specific tags — used to avoid re-asking a site about
  /// tags a snapshot pull already answered.
  static Future<Map<String, BooruTagEntry>> lookup(Booru booru, List<String> names) async {
    final List<String> clean = [
      for (final n in names.map(_clean).toSet())
        if (n.isNotEmpty) n,
    ];
    if (clean.isEmpty) return const {};
    try {
      final rows = await _settings.dbHandler.getBooruTagsByNames(keyFor(booru), clean);
      return {
        for (final row in rows)
          row['name'].toString(): BooruTagEntry(
            name: row['name'].toString(),
            tagType: TagType.fromString(row['tagType']?.toString() ?? 'none'),
            count: int.tryParse(row['count']?.toString() ?? '') ?? 0,
            origin: row['source']?.toString() == 'import' ? TagTypeOrigin.inferred : TagTypeOrigin.reported,
            updatedAt: int.tryParse(row['updatedAt']?.toString() ?? '') ?? 0,
          ),
      };
    } catch (_) {
      return const {};
    }
  }

  static Future<int> snapshotSize(Booru booru) async {
    try {
      return await _settings.dbHandler.countBooruTags(keyFor(booru));
    } catch (_) {
      return 0;
    }
  }

  static Future<void> clearSnapshot(Booru booru) async {
    try {
      await _settings.dbHandler.deleteBooruTags(keyFor(booru));
    } catch (_) {}
  }

  // ──────────────────────────── resolution ────────────────────────────

  /// The type to believe for [tag] **on [booru]**, and who says so.
  ///
  /// Order: your correction, then this booru's own snapshot row, then the
  /// app's global store (which is some other site's opinion — hence
  /// `inferred`, and hence the dashed outline in the browser).
  static (TagType, TagTypeOrigin) resolve(String tag, Booru? booru, {BooruTagEntry? snapshotRow}) {
    final String name = _clean(tag);
    final TagType? mine = manualType(name, booru);
    if (mine != null) return (mine, TagTypeOrigin.manual);

    if (snapshotRow != null && snapshotRow.tagType != TagType.none) {
      return (snapshotRow.tagType, snapshotRow.origin);
    }

    final TagType global = TagHandler.instance.getTag(name).tagType;
    if (global != TagType.none) return (global, TagTypeOrigin.inferred);

    if (snapshotRow != null) return (TagType.none, snapshotRow.origin);
    return (TagType.none, TagTypeOrigin.unknown);
  }

  // ────────────────────────── import / export ─────────────────────────

  /// Portable snapshot format. Deliberately boring and self-describing so a
  /// file can be hosted anywhere and read by hand.
  static String exportJson(Booru booru, List<BooruTagEntry> entries) {
    return jsonEncode({
      'format': 'lolisnatcher-tag-snapshot',
      'version': 1,
      'booru': keyFor(booru),
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'tags': [for (final e in entries) e.toJson()],
    });
  }

  /// Reads a snapshot file/response into the snapshot table.
  ///
  /// [booru] is what the rows are filed under. A file carrying a different
  /// `booru` key is still importable (you may have exported it under another
  /// host name) but is reported as `inferred`, never as reported-by-this-site.
  static Future<(int imported, String? warning)> importJson(Booru booru, String body) async {
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return (0, 'That file is not valid JSON.');
    }

    final List raw;
    String? sourceKey;
    if (decoded is List) {
      raw = decoded;
    } else if (decoded is Map) {
      sourceKey = decoded['booru']?.toString();
      raw = (decoded['tags'] as List?) ?? const [];
    } else {
      return (0, 'Unrecognised snapshot format.');
    }
    if (raw.isEmpty) return (0, 'That snapshot has no tags in it.');

    final bool foreign = sourceKey != null && sourceKey.isNotEmpty && sourceKey != keyFor(booru);
    final int now = DateTime.now().millisecondsSinceEpoch;
    final List<BooruTagEntry> entries = [
      for (final e in raw)
        if (e is Map<String, dynamic>)
          BooruTagEntry.fromJson(e).copyWith(
            origin: foreign ? TagTypeOrigin.inferred : TagTypeOrigin.reported,
            updatedAt: now,
          ),
    ];
    final int written = await record(booru, entries);
    return (
      written,
      foreign ? 'Snapshot was made for "$sourceKey" — imported as inferred, not as reported.' : null,
    );
  }

  /// Downloads a hosted snapshot. Any plain HTTP(S) URL serving the format
  /// above works; there is no blessed server.
  static Future<(int imported, String? warning)> importFromUrl(Booru booru, String url) async {
    try {
      final response = await DioNetwork.get(url, headers: {'User-Agent': Tools.appUserAgent});
      final dynamic data = response.data;
      final String body = data is String ? data : jsonEncode(data);
      return importJson(booru, body);
    } catch (e) {
      return (0, 'Download failed: $e');
    }
  }
}
