import 'dart:convert';

import 'package:lolisnatcher/src/handlers/database_handler.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// One-time migration of doujin entries OUT of the shared booru stores into
/// the doujin store (doujinData.json). Split into a PURE planner over plain
/// row maps (unit-testable without sqflite) and a thin DB applier.
///
/// What moves (identified by post URL host / booru config name):
/// - DB favourites (BooruItem.isFavourite=1) -> doujin favourites, then the
///   flag is cleared in the DB so booru favourites no longer contain them.
/// - Viewing history (ViewedPost) -> doujin history, rows deleted.
/// - Per-source pinned tags (PinnedTag.booruName = a doujin config) -> doujin
///   pins, rows deleted. GLOBAL pins are left alone: they belong to the booru
///   side and simply stop being shown on doujin surfaces.
/// - Saved searches whose primary booru is a doujin config -> doujin saved
///   searches, rows deleted.
/// - Collection members with a doujin post URL -> a doujin collection of the
///   same name; the member rows are removed from the booru collection (the
///   booru collection itself stays, even if it ends up empty).
///
/// NOT migrated: followed artists. Follows are stored as GLOBAL pins with a
/// follow label and carry no source attribution, so there is no way to tell
/// a doujin follow from a booru follow. They stay booru-side; doujin follows
/// start fresh.
class DoujinMigrationPlan {
  final List<DoujinEntry> favourites = [];
  final List<int> favouriteItemIdsToClear = []; // BooruItem ids -> isFavourite=0

  final List<DoujinEntry> history = []; // newest first
  final List<String> historyKeysToDelete = []; // ViewedPost postKey

  final List<({String tag, String host})> pins = [];
  final List<int> pinIdsToDelete = [];

  final List<({String name, String query, String host})> savedSearches = [];
  final List<int> savedSearchIdsToDelete = [];

  /// collection name -> members (insertion order preserved).
  final Map<String, List<DoujinEntry>> collections = {};
  final List<({int collectionId, int booruItemId})> collectionItemsToDelete = [];

  bool get isEmpty =>
      favourites.isEmpty &&
      history.isEmpty &&
      pins.isEmpty &&
      savedSearches.isEmpty &&
      collections.isEmpty;
}

String? _hostOfUrl(String? url) => Uri.tryParse(url ?? '')?.host;

/// serverId for entries coming from DB rows that never stored one: the last
/// purely numeric path segment (nhentai: /g/177013/).
String _serverIdFromUrl(String url) {
  final segments = Uri.tryParse(url)?.pathSegments ?? const [];
  for (final s in segments.reversed) {
    if (s.isNotEmpty && int.tryParse(s) != null) return s;
  }
  return '';
}

DoujinEntry _entryFromRow({
  required String postURL,
  required String host,
  String thumbnailURL = '',
  String title = '',
  String serverId = '',
  int addedAt = 0,
}) => DoujinEntry(
  postURL: postURL,
  serverId: serverId.isNotEmpty ? serverId : _serverIdFromUrl(postURL),
  thumbnailURL: thumbnailURL,
  title: title,
  booruHost: host,
  addedAt: addedAt == 0 ? DateTime.now().millisecondsSinceEpoch : addedAt,
);

/// Pure planner. Inputs mirror the DB row shapes exactly:
/// - [doujinHosts]: post URL hosts that count as doujin (e.g. {nhentai.net}).
/// - [doujinBooruNames]: doujin booru CONFIG name -> host, for rows that
///   reference boorus by name (pins, saved searches).
/// - [favouriteRows]: SELECT id, postURL, thumbnailURL FROM BooruItem WHERE isFavourite=1
/// - [viewedRows]: SELECT postKey, itemJson, viewedAt FROM ViewedPost (newest first)
/// - [pinRows]: SELECT id, tagName, booruType, booruName, label FROM PinnedTag
/// - [savedSearchRows]: SELECT id, name, payload, createdAt FROM SavedSearch
/// - [collectionRows]: SELECT id, name FROM Collection
/// - [collectionItemRows]: SELECT collectionId, booruItemID, addedAt FROM CollectionItem
/// - [booruItemsById]: BooruItem id -> {postURL, thumbnailURL} for collection members.
DoujinMigrationPlan planDoujinMigration({
  required Set<String> doujinHosts,
  required Map<String, String> doujinBooruNames,
  required List<Map<String, Object?>> favouriteRows,
  required List<Map<String, Object?>> viewedRows,
  required List<Map<String, Object?>> pinRows,
  required List<Map<String, Object?>> savedSearchRows,
  required List<Map<String, Object?>> collectionRows,
  required List<Map<String, Object?>> collectionItemRows,
  required Map<int, Map<String, Object?>> booruItemsById,
}) {
  final plan = DoujinMigrationPlan();

  bool isDoujinUrl(String? url) {
    final host = _hostOfUrl(url);
    return host != null && doujinHosts.contains(host);
  }

  // ── favourites ──
  for (final row in favouriteRows) {
    final String postURL = row['postURL']?.toString() ?? '';
    if (!isDoujinUrl(postURL)) continue;
    plan.favourites.add(
      _entryFromRow(
        postURL: postURL,
        host: _hostOfUrl(postURL)!,
        thumbnailURL: row['thumbnailURL']?.toString() ?? '',
      ),
    );
    final int? id = row['id'] as int?;
    if (id != null) plan.favouriteItemIdsToClear.add(id);
  }

  // ── history ──
  for (final row in viewedRows) {
    final String postKey = row['postKey']?.toString() ?? '';
    String postURL = postKey;
    String thumbnailURL = '';
    String serverId = '';
    try {
      final Map<String, dynamic> j = jsonDecode(row['itemJson']?.toString() ?? '') as Map<String, dynamic>;
      postURL = j['postURL']?.toString() ?? postKey;
      thumbnailURL = j['thumbnailURL']?.toString() ?? '';
      serverId = j['serverId']?.toString() ?? '';
    } catch (_) {}
    if (!isDoujinUrl(postURL)) continue;
    plan.history.add(
      _entryFromRow(
        postURL: postURL,
        host: _hostOfUrl(postURL)!,
        thumbnailURL: thumbnailURL,
        serverId: serverId,
        addedAt: row['viewedAt'] as int? ?? 0,
      ),
    );
    plan.historyKeysToDelete.add(postKey);
  }

  // ── per-source pins ──
  for (final row in pinRows) {
    final String? booruName = row['booruName']?.toString();
    if (booruName == null || booruName.isEmpty) continue; // global pin: stays booru-side
    final String? host = doujinBooruNames[booruName];
    if (host == null) continue;
    final String tag = row['tagName']?.toString() ?? '';
    if (tag.isEmpty) continue;
    plan.pins.add((tag: tag, host: host));
    final int? id = row['id'] as int?;
    if (id != null) plan.pinIdsToDelete.add(id);
  }

  // ── saved searches ──
  for (final row in savedSearchRows) {
    String booru = '';
    String tags = '';
    try {
      final Map<String, dynamic> j = jsonDecode(row['payload']?.toString() ?? '') as Map<String, dynamic>;
      booru = j['booru']?.toString() ?? '';
      tags = j['tags']?.toString() ?? '';
    } catch (_) {}
    final String? host = doujinBooruNames[booru];
    if (host == null) continue;
    plan.savedSearches.add((
      name: row['name']?.toString() ?? '',
      query: tags,
      host: host,
    ));
    final int? id = row['id'] as int?;
    if (id != null) plan.savedSearchIdsToDelete.add(id);
  }

  // ── collections ──
  final Map<int, String> collectionNames = {
    for (final row in collectionRows)
      if (row['id'] is int) row['id']! as int: row['name']?.toString() ?? '',
  };
  for (final row in collectionItemRows) {
    final int? collectionId = row['collectionId'] as int?;
    final int? itemId = row['booruItemID'] as int?;
    if (collectionId == null || itemId == null) continue;
    final item = booruItemsById[itemId];
    final String postURL = item?['postURL']?.toString() ?? '';
    if (!isDoujinUrl(postURL)) continue;
    final String name = collectionNames[collectionId] ?? 'Collection $collectionId';
    (plan.collections[name] ??= []).add(
      _entryFromRow(
        postURL: postURL,
        host: _hostOfUrl(postURL)!,
        thumbnailURL: item?['thumbnailURL']?.toString() ?? '',
        addedAt: row['addedAt'] as int? ?? 0,
      ),
    );
    plan.collectionItemsToDelete.add((collectionId: collectionId, booruItemId: itemId));
  }

  return plan;
}

/// Merges a plan into the doujin store. Pure w.r.t. the DB; the store itself
/// persists via its normal save(). Skips entries that already exist so the
/// migration is idempotent even if interrupted halfway.
void applyPlanToStore(DoujinMigrationPlan plan, DoujinDataHandler store) {
  store.ensureLoaded();
  for (final e in plan.favourites) {
    store.favourites.putIfAbsent(e.postURL, () => e);
  }
  // History arrives newest first; store is newest first too, so append in
  // order (fresh store) or skip what's already there.
  for (final e in plan.history) {
    if (store.history.any((h) => h.postURL == e.postURL)) continue;
    store.history.add(e);
  }
  store.history.sort((a, b) => b.addedAt.compareTo(a.addedAt));
  if (store.history.length > DoujinDataHandler.historyCap) {
    store.history.removeRange(DoujinDataHandler.historyCap, store.history.length);
  }
  for (final p in plan.pins) {
    if (store.pins.any((x) => x.tag == p.tag && x.booruHost == p.host)) continue;
    store.pins.add(DoujinPin(tag: p.tag, booruHost: p.host, addedAt: DateTime.now().millisecondsSinceEpoch));
  }
  for (final s in plan.savedSearches) {
    if (store.savedSearches.any((x) => x.query == s.query && x.booruHost == s.host)) continue;
    final int id = (store.savedSearches.isEmpty ? 0 : store.savedSearches.map((x) => x.id).reduce((a, b) => a > b ? a : b)) + 1;
    store.savedSearches.add(
      DoujinSavedSearch(
        id: id,
        name: s.name,
        query: s.query,
        booruHost: s.host,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
  plan.collections.forEach((name, entries) {
    final existing = store.collections.where((c) => c.name == name).toList();
    final collection = existing.isNotEmpty ? existing.first : store.createCollection(name);
    for (final e in entries) {
      if (collection.items.any((x) => x.postURL == e.postURL)) continue;
      collection.items.add(e);
    }
  });
  store.save();
}

/// Runs the whole migration once per install: gathers rows from the DB,
/// plans, applies to the store, then removes the migrated rows from the
/// booru stores. Safe to call on every startup — no-ops after the first
/// successful run (or when the DB is off).
Future<void> runDoujinMigrationIfNeeded() async {
  final store = DoujinDataHandler.instance..ensureLoaded();
  if (store.migrationDone) return;

  final settings = SettingsHandler.instance;
  // Only ever mark the migration done after actually inspecting an OPEN
  // database. DB disabled or failed-to-open → retry next startup (cheap
  // no-op), so old doujin rows can't get stranded in the booru stores if the
  // DB comes back later.
  if (!settings.dbEnabled || settings.dbHandler.db == null) {
    return;
  }

  try {
    final DBHandler db = settings.dbHandler;

    // Hard-code known doujin hosts too, so favourites/history saved before a
    // config was (re)named still migrate.
    final Set<String> doujinHosts = {'nhentai.net'};
    final Map<String, String> doujinBooruNames = {};
    for (final booru in settings.booruList) {
      if (!DoujinDataHandler.isDoujinBooru(booru)) continue;
      final String host = DoujinDataHandler.hostOf(booru);
      if (host.isNotEmpty) doujinHosts.add(host);
      if (booru.name?.isNotEmpty ?? false) doujinBooruNames[booru.name!] = host;
    }

    final plan = planDoujinMigration(
      doujinHosts: doujinHosts,
      doujinBooruNames: doujinBooruNames,
      favouriteRows: await db.rawRows('SELECT id, postURL, thumbnailURL FROM BooruItem WHERE isFavourite = 1'),
      viewedRows: await db.rawRows('SELECT postKey, itemJson, viewedAt FROM ViewedPost ORDER BY viewedAt DESC'),
      pinRows: await db.rawRows('SELECT id, tagName, booruType, booruName, label FROM PinnedTag'),
      savedSearchRows: await db.rawRows('SELECT id, name, payload, createdAt FROM SavedSearch'),
      collectionRows: await db.rawRows('SELECT id, name FROM Collection'),
      collectionItemRows: await db.rawRows('SELECT collectionId, booruItemID, addedAt FROM CollectionItem'),
      booruItemsById: {
        for (final row in await db.rawRows(
          'SELECT BooruItem.id, postURL, thumbnailURL FROM BooruItem '
          'INNER JOIN CollectionItem ON CollectionItem.booruItemID = BooruItem.id',
        ))
          if (row['id'] is int) row['id']! as int: row,
      },
    );

    // Store first (additive, idempotent), deletions second — a crash in
    // between re-runs cleanly next start.
    applyPlanToStore(plan, store);

    if (plan.favouriteItemIdsToClear.isNotEmpty) {
      await db.clearFavouriteFlag(plan.favouriteItemIdsToClear);
    }
    for (final key in plan.historyKeysToDelete) {
      await db.deleteViewedPost(key);
    }
    for (final id in plan.pinIdsToDelete) {
      await db.removePinnedTag(id);
    }
    for (final id in plan.savedSearchIdsToDelete) {
      await db.deleteSavedSearch(id);
    }
    for (final pair in plan.collectionItemsToDelete) {
      await db.removeCollectionItem(pair.collectionId, pair.booruItemId);
    }

    store.migrationDone = true;
    store.save();
    Logger.Inst().log(
      'doujin migration done: ${plan.favourites.length} favs, ${plan.history.length} history, '
      '${plan.pins.length} pins, ${plan.savedSearches.length} saved searches, '
      '${plan.collections.length} collections',
      'DoujinMigration',
      'runDoujinMigrationIfNeeded',
      LogTypes.settingsLoad,
    );
  } catch (e, s) {
    // Leave migrationDone false so it retries next startup.
    Logger.Inst().log('doujin migration failed: $e', 'DoujinMigration', 'runDoujinMigrationIfNeeded', LogTypes.exception, s: s);
  }
}
