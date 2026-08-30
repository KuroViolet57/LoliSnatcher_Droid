import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/history_item.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

/// Domain router for SEARCH history.
///
/// Booru search history lives in store.db (`SearchHistory`); doujin search
/// history lives in the doujin store. They are never mixed: a doujin query
/// must not appear in a booru's "Recent searches" (or its typed suggestions)
/// and vice versa. Every history surface goes through here instead of
/// touching `dbHandler` directly, so the routing exists in exactly one place.
///
/// Legacy rows recorded before the split are filtered out of the booru reads
/// by booru name, so an existing install stops showing them immediately.
class SearchHistoryStore {
  const SearchHistoryStore._();

  static SettingsHandler get _settings => SettingsHandler.instance;

  /// Names of the configured doujin sources — used to drop legacy doujin rows
  /// out of the booru history reads.
  static Set<String> get _doujinBooruNames => {
    for (final b in _settings.booruList)
      if (DoujinDataHandler.isDoujinBooru(b) && (b.name?.isNotEmpty ?? false)) b.name!,
  };

  /// The domain of the tab the user is looking at.
  static bool get currentIsDoujin {
    final searchHandler = SearchHandler.instance;
    if (searchHandler.tabs.isEmpty) return false;
    return DoujinDataHandler.isDoujinBooru(searchHandler.currentBooru);
  }

  /// SQLite writes CURRENT_TIMESTAMP as UTC digits with no zone marker, and
  /// the UI parses that then adds the local offset. Doujin entries render
  /// through the same path, so they use the same shape.
  static String _timestampOf(int millis) {
    final DateTime utc = DateTime.fromMillisecondsSinceEpoch(millis).toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${utc.year}-${two(utc.month)}-${two(utc.day)} ${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}';
  }

  static HistoryItem _toHistoryItem(DoujinSearchHistoryEntry e) {
    final Booru booru = _settings.booruList.firstWhere(
      (b) => DoujinDataHandler.isDoujinBooru(b) && DoujinDataHandler.hostOf(b) == e.booruHost,
      orElse: Booru.unknown,
    );
    return HistoryItem(
      e.id,
      e.query,
      booru.type,
      booru.name ?? e.booruHost,
      e.isFavourite,
      _timestampOf(e.at),
    );
  }

  static List<HistoryItem> _doujinItems() =>
      [for (final e in DoujinDataHandler.instance.searchHistory) _toHistoryItem(e)];

  static List<HistoryItem> _withoutDoujinRows(List<HistoryItem> items) {
    final names = _doujinBooruNames;
    if (names.isEmpty) return items;
    return [
      for (final i in items)
        if (!names.contains(i.booruName)) i,
    ];
  }

  /// Records a search on [booru]. Doujin sources never touch store.db.
  static Future<void> record(String searchText, Booru? booru) async {
    // One user preference governs both domains — it's about recording
    // searches at all, not about which store they land in.
    if (!_settings.searchHistoryEnabled) return;
    if (DoujinDataHandler.isDoujinBooru(booru)) {
      DoujinDataHandler.instance.addSearchHistory(searchText, booru);
      return;
    }
    await _settings.dbHandler.updateSearchHistory(searchText, booru?.type?.name, booru?.name);
  }

  /// The 20 most recent entries of the CURRENT domain.
  static Future<List<HistoryItem>> latest() async {
    if (currentIsDoujin) {
      DoujinDataHandler.instance.ensureLoaded();
      return _doujinItems().take(20).toList();
    }
    return _withoutDoujinRows(await _settings.dbHandler.getLatestSearchHistory());
  }

  /// Every entry of the current domain (the full history page).
  static Future<List<HistoryItem>> all() async {
    if (currentIsDoujin) {
      DoujinDataHandler.instance.ensureLoaded();
      return _doujinItems();
    }
    return _withoutDoujinRows(await _settings.dbHandler.getSearchHistory());
  }

  /// Prefix matches for the typed-suggestion blend, current domain only.
  static Future<List<String>> byInput(String query, int limit) async {
    if (currentIsDoujin) {
      return DoujinDataHandler.instance.searchHistoryByInput(query, limit);
    }
    final List<String> out = await _settings.dbHandler.getSearchHistoryByInput(query, limit);
    return out;
  }

  /// [id] null = clear the whole current-domain history.
  static Future<void> delete(int? id) async {
    if (currentIsDoujin) {
      DoujinDataHandler.instance.deleteSearchHistory(id);
      return;
    }
    await _settings.dbHandler.deleteFromSearchHistory(id);
  }

  static Future<void> setFavourite(int id, bool isFavourite) async {
    if (currentIsDoujin) {
      DoujinDataHandler.instance.setSearchHistoryFavourite(id, isFavourite);
      return;
    }
    await _settings.dbHandler.setFavouriteSearchHistory(id, isFavourite);
  }
}
