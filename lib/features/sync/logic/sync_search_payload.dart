import 'package:lolisnatcher/core/storage/database_handler.dart';
import 'package:lolisnatcher/models/history_item.dart';
import 'package:lolisnatcher/models/saved_search.dart';

/// One search-history row on the wire. The session code is not in here.
class SyncHistoryRow {
  const SyncHistoryRow({
    required this.searchText,
    required this.booruType,
    required this.booruName,
    required this.favourite,
    required this.timestamp,
  });

  final String searchText;
  final String booruType;
  final String booruName;
  final bool favourite;
  final String timestamp;

  Map<String, Object?> toJson() => {
    'searchText': searchText,
    'booruType': booruType,
    'booruName': booruName,
    'favourite': favourite,
    'timestamp': timestamp,
  };

  /// A row with no booru name cannot be opened again, so it is not sent.
  /// The search text is trimmed, the same way a local search is stored.
  static SyncHistoryRow? fromHistoryItem(HistoryItem item) {
    final String booruName = item.booruName.trim();
    if (booruName.isEmpty) return null;
    return SyncHistoryRow(
      searchText: item.searchText.trim(),
      booruType: item.booruType?.name ?? '',
      booruName: booruName,
      favourite: item.isFavourite,
      timestamp: _cleanTimestamp(item.timestamp),
    );
  }

  static SyncHistoryRow? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final String booruName = (raw['booruName']?.toString() ?? '').trim();
    if (booruName.isEmpty) return null;
    final String type = raw['booruType']?.toString() ?? '';
    return SyncHistoryRow(
      searchText: (raw['searchText']?.toString() ?? '').trim(),
      booruType: type == 'null' ? '' : type,
      booruName: booruName,
      favourite: raw['favourite'] == true || raw['favourite'] == 1 || raw['favourite'] == '1',
      timestamp: _cleanTimestamp(raw['timestamp']?.toString() ?? ''),
    );
  }
}

String _cleanTimestamp(String raw) {
  final String trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed == 'null') return '';
  return trimmed;
}

/// What to do with one incoming history row.
enum HistoryMergeAction { insert, upgradeFavourite, skip }

/// A search this phone already has is left as it is. A favourite on the
/// other phone marks that same search here, and never clears one.
HistoryMergeAction decideHistoryMerge({
  required bool booruNamed,
  required bool alreadyThere,
  required bool alreadyFavourite,
  required bool incomingFavourite,
}) {
  if (!booruNamed) return HistoryMergeAction.skip;
  if (!alreadyThere) return HistoryMergeAction.insert;
  if (incomingFavourite && !alreadyFavourite) return HistoryMergeAction.upgradeFavourite;
  return HistoryMergeAction.skip;
}

String historyIdentity(String searchText, String booruType, String booruName) =>
    '${searchText.trim()}\u0002$booruType\u0002${booruName.trim()}';

class HistoryMergeCounts {
  const HistoryMergeCounts({required this.inserted, required this.upgraded, required this.skipped});

  final int inserted;
  final int upgraded;
  final int skipped;
}

/// Writes [rows] into [db]. A repeated row in the same list is stored once.
/// This does not trim the history table: the next search the user types
/// still applies the existing cap, and favourites stay outside that cap.
Future<HistoryMergeCounts> applySyncedSearchHistory(DBHandler db, List<SyncHistoryRow> rows) async {
  final stored = await db.listSearchHistoryKeys();
  final Map<String, bool> favouriteByIdentity = {};
  for (final row in stored) {
    final String id = historyIdentity(row.searchText, row.booruType, row.booruName);
    favouriteByIdentity[id] = (favouriteByIdentity[id] ?? false) || row.favourite;
  }
  var inserted = 0;
  var upgraded = 0;
  var skipped = 0;
  for (final SyncHistoryRow row in rows) {
    final String id = historyIdentity(row.searchText, row.booruType, row.booruName);
    final bool alreadyThere = favouriteByIdentity.containsKey(id);
    final HistoryMergeAction action = decideHistoryMerge(
      booruNamed: row.booruName.trim().isNotEmpty,
      alreadyThere: alreadyThere,
      alreadyFavourite: favouriteByIdentity[id] ?? false,
      incomingFavourite: row.favourite,
    );
    switch (action) {
      case HistoryMergeAction.insert:
        await db.insertSyncedSearchHistory(
          searchText: row.searchText.trim(),
          booruType: row.booruType,
          booruName: row.booruName.trim(),
          favourite: row.favourite,
          timestamp: row.timestamp,
        );
        favouriteByIdentity[id] = row.favourite;
        inserted++;
      case HistoryMergeAction.upgradeFavourite:
        await db.markSearchHistoryFavourite(
          searchText: row.searchText.trim(),
          booruType: row.booruType,
          booruName: row.booruName.trim(),
        );
        favouriteByIdentity[id] = true;
        upgraded++;
      case HistoryMergeAction.skip:
        skipped++;
    }
  }
  return HistoryMergeCounts(inserted: inserted, upgraded: upgraded, skipped: skipped);
}

/// One booru saved search on the wire. Doujin bookmarks are not this table.
class SyncSavedSearchRow {
  const SyncSavedSearchRow({required this.name, required this.payload, required this.createdAtMs});

  final String name;
  final String payload;
  final int createdAtMs;

  Map<String, Object?> toJson() => {
    'name': name,
    'payload': payload,
    'createdAt': createdAtMs,
  };

  static SyncSavedSearchRow? fromSavedSearch(SavedSearch entry) {
    if (entry.booru.trim().isEmpty) return null;
    return SyncSavedSearchRow(
      name: entry.name,
      payload: entry.payloadJson(),
      createdAtMs: entry.createdAt.millisecondsSinceEpoch,
    );
  }

  static SyncSavedSearchRow? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final String payload = raw['payload']?.toString() ?? '';
    if (payload.isEmpty) return null;
    final Object? created = raw['createdAt'];
    final int ms = created is int ? created : int.tryParse(created?.toString() ?? '') ?? 0;
    return SyncSavedSearchRow(name: raw['name']?.toString() ?? '', payload: payload, createdAtMs: ms);
  }

  SavedSearch? toSavedSearch() {
    return SavedSearch.fromRow({
      'id': null,
      'name': name,
      'payload': payload,
      'createdAt': createdAtMs > 0 ? createdAtMs : DateTime.now().millisecondsSinceEpoch,
    });
  }
}

enum SavedSearchMergeAction { insert, skip }

/// The same search is the same bookmark even when the label differs.
/// A label this phone already wrote is left as it is.
SavedSearchMergeAction decideSavedSearchMerge({
  required bool payloadOk,
  required bool booruNamed,
  required bool alreadyThere,
}) {
  if (!payloadOk || !booruNamed || alreadyThere) return SavedSearchMergeAction.skip;
  return SavedSearchMergeAction.insert;
}

/// Tags, booru, secondaries, overrides, and inherit flags. The label is not
/// part of it, and the order of the lists is not either.
String savedSearchIdentity(SavedSearch entry) {
  final List<String> secondaries = [...entry.secondaryBoorus]..sort();
  final List<String> overrideKeys = entry.tagOverrides.keys.toList()..sort();
  final List<String> inheritOff = entry.inheritMainTags.keys.where((String k) => entry.inheritMainTags[k] == false).toList()
    ..sort();
  return [
    entry.tags,
    entry.booru.trim(),
    secondaries.join('\u0001'),
    overrideKeys.map((String k) => '$k=${entry.tagOverrides[k]}').join('\u0001'),
    inheritOff.join('\u0001'),
  ].join('\u0002');
}

class SavedSearchMergeCounts {
  const SavedSearchMergeCounts({required this.inserted, required this.skipped});

  final int inserted;
  final int skipped;
}

Future<SavedSearchMergeCounts> applySyncedSavedSearches(DBHandler db, List<SyncSavedSearchRow> rows) async {
  final List<SavedSearch> stored = await db.getSavedSearches();
  final Set<String> identities = {for (final SavedSearch entry in stored) savedSearchIdentity(entry)};
  var inserted = 0;
  var skipped = 0;
  for (final SyncSavedSearchRow row in rows) {
    final SavedSearch? parsed = row.toSavedSearch();
    final bool payloadOk = parsed != null;
    final bool booruNamed = parsed != null && parsed.booru.trim().isNotEmpty;
    final String id = parsed == null ? '' : savedSearchIdentity(parsed);
    final SavedSearchMergeAction action = decideSavedSearchMerge(
      payloadOk: payloadOk,
      booruNamed: booruNamed,
      alreadyThere: id.isNotEmpty && identities.contains(id),
    );
    if (action == SavedSearchMergeAction.insert && parsed != null) {
      await db.addSavedSearch(parsed);
      identities.add(id);
      inserted++;
    } else {
      skipped++;
    }
  }
  return SavedSearchMergeCounts(inserted: inserted, skipped: skipped);
}
