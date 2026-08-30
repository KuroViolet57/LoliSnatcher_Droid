import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:get/get.dart' hide ContextExt, FirstWhereOrNullExt;

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// One doujin gallery reference — the shared record for favourites,
/// collections, history: enough to render a list row and reopen the gallery
/// (`id:<serverId>` query) without refetching.
class DoujinEntry {
  const DoujinEntry({
    required this.postURL,
    required this.serverId,
    required this.thumbnailURL,
    required this.title,
    required this.booruHost,
    required this.addedAt,
  });

  factory DoujinEntry.fromJson(Map<String, dynamic> json) => DoujinEntry(
    postURL: json['postURL'] as String? ?? '',
    serverId: json['serverId'] as String? ?? '',
    thumbnailURL: json['thumbnailURL'] as String? ?? '',
    title: json['title'] as String? ?? '',
    booruHost: json['booruHost'] as String? ?? '',
    addedAt: json['addedAt'] as int? ?? 0,
  );

  factory DoujinEntry.fromItem(BooruItem item, Booru? booru) {
    // Host from the booru config when it has one; otherwise from the item's
    // own post URL (merge tabs pass the Merge placeholder, which has none).
    String host = Uri.tryParse(booru?.baseURL ?? '')?.host ?? '';
    if (host.isEmpty) host = Uri.tryParse(item.postURL)?.host ?? '';
    return DoujinEntry(
      postURL: item.postURL,
      serverId: item.serverId ?? '',
      thumbnailURL: item.thumbnailURL,
      title: (item.description ?? '').split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => ''),
      booruHost: host,
      addedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  final String postURL;
  final String serverId;
  final String thumbnailURL;
  final String title;
  final String booruHost;
  final int addedAt;

  Map<String, dynamic> toJson() => {
    'postURL': postURL,
    'serverId': serverId,
    'thumbnailURL': thumbnailURL,
    'title': title,
    'booruHost': booruHost,
    'addedAt': addedAt,
  };
}

class DoujinCollection {
  DoujinCollection({
    required this.id,
    required this.name,
    required this.createdAt,
    List<DoujinEntry>? items,
  }) : items = items ?? [];

  factory DoujinCollection.fromJson(Map<String, dynamic> json) => DoujinCollection(
    id: json['id'] as int? ?? 0,
    name: json['name'] as String? ?? '',
    createdAt: json['createdAt'] as int? ?? 0,
    items: [
      for (final entry in json['items'] as List? ?? []) DoujinEntry.fromJson(entry as Map<String, dynamic>),
    ],
  );

  final int id;
  String name;
  final int createdAt;
  final List<DoujinEntry> items;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt,
    'items': [for (final e in items) e.toJson()],
  };
}

class DoujinPin {
  const DoujinPin({required this.tag, required this.booruHost, required this.addedAt});

  factory DoujinPin.fromJson(Map<String, dynamic> json) => DoujinPin(
    tag: json['tag'] as String? ?? '',
    booruHost: json['booruHost'] as String?,
    addedAt: json['addedAt'] as int? ?? 0,
  );

  final String tag;

  /// null = pinned for ALL doujin sources; otherwise one source's host.
  final String? booruHost;
  final int addedAt;

  Map<String, dynamic> toJson() => {
    'tag': tag,
    if (booruHost != null) 'booruHost': booruHost,
    'addedAt': addedAt,
  };
}

/// One remembered doujin search query. The doujin counterpart of the booru
/// `SearchHistory` table — the two never mix, in either direction.
class DoujinSearchHistoryEntry {
  const DoujinSearchHistoryEntry({
    required this.id,
    required this.query,
    required this.booruHost,
    required this.at,
    this.isFavourite = false,
  });

  factory DoujinSearchHistoryEntry.fromJson(Map<String, dynamic> json) => DoujinSearchHistoryEntry(
    id: json['id'] as int? ?? 0,
    query: json['query'] as String? ?? '',
    booruHost: json['booruHost'] as String? ?? '',
    at: json['at'] as int? ?? 0,
    isFavourite: json['isFavourite'] as bool? ?? false,
  );

  final int id;
  final String query;
  final String booruHost;
  final int at;
  final bool isFavourite;

  DoujinSearchHistoryEntry copyWith({bool? isFavourite, int? at}) => DoujinSearchHistoryEntry(
    id: id,
    query: query,
    booruHost: booruHost,
    at: at ?? this.at,
    isFavourite: isFavourite ?? this.isFavourite,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'query': query,
    'booruHost': booruHost,
    'at': at,
    'isFavourite': isFavourite,
  };
}

class DoujinSavedSearch {
  const DoujinSavedSearch({
    required this.id,
    required this.name,
    required this.query,
    required this.booruHost,
    required this.createdAt,
  });

  factory DoujinSavedSearch.fromJson(Map<String, dynamic> json) => DoujinSavedSearch(
    id: json['id'] as int? ?? 0,
    name: json['name'] as String? ?? '',
    query: json['query'] as String? ?? '',
    booruHost: json['booruHost'] as String? ?? '',
    createdAt: json['createdAt'] as int? ?? 0,
  );

  final int id;
  final String name;
  final String query;
  final String booruHost;
  final int createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'query': query,
    'booruHost': booruHost,
    'createdAt': createdAt,
  };
}

class DoujinFollow {
  const DoujinFollow({required this.tag, required this.booruHost, required this.addedAt});

  factory DoujinFollow.fromJson(Map<String, dynamic> json) => DoujinFollow(
    tag: json['tag'] as String? ?? '',
    booruHost: json['booruHost'] as String? ?? '',
    addedAt: json['addedAt'] as int? ?? 0,
  );

  final String tag;
  final String booruHost;
  final int addedAt;

  Map<String, dynamic> toJson() => {'tag': tag, 'booruHost': booruHost, 'addedAt': addedAt};
}

/// THE doujin data store — favourites, collections, followed artists,
/// history, saved searches and pinned tags for doujin sources, all in their
/// own file (doujinData.json), fully parallel to and SEPARATE from every
/// booru store. A booru entry can never appear here and nothing here is ever
/// read by a booru surface: the only shared thing is the file system.
///
/// The doujin blacklist lives in SourceSettingsHandler (sourceSettings.json)
/// which is equally doujin-only.
class DoujinDataHandler {
  DoujinDataHandler._();

  static final DoujinDataHandler instance = DoujinDataHandler._();

  static const int historyCap = 1000;

  /// The doujin source types. Extend when new doujin engines land.
  static bool isDoujinBooru(Booru? booru) => booru?.type == BooruType.NHentai;

  static String hostOf(Booru? booru) => Uri.tryParse(booru?.baseURL ?? '')?.host ?? (booru?.name ?? '');

  /// Hosts that are always doujin, even without a matching config — keeps
  /// item-level attribution working after a source is renamed/removed.
  static const Set<String> knownDoujinHosts = {'nhentai.net'};

  /// ITEM-level doujin check, for mixed feeds (merge tabs, floating
  /// previews): a doujin item is recognized by its post URL host no matter
  /// which handler fetched it.
  static bool isDoujinItem(BooruItem item) {
    final String? host = Uri.tryParse(item.postURL)?.host;
    if (host == null || host.isEmpty) return false;
    if (knownDoujinHosts.contains(host)) return true;
    for (final b in SettingsHandler.instance.booruList) {
      if (isDoujinBooru(b) && hostOf(b) == host) return true;
    }
    return false;
  }

  /// The configured doujin booru an item belongs to (by post URL host), or
  /// null when none matches.
  static Booru? doujinBooruForItem(BooruItem item) {
    final String? host = Uri.tryParse(item.postURL)?.host;
    if (host == null || host.isEmpty) return null;
    for (final b in SettingsHandler.instance.booruList) {
      if (isDoujinBooru(b) && hostOf(b) == host) return b;
    }
    return null;
  }

  // ── state ──
  final RxMap<String, DoujinEntry> favourites = <String, DoujinEntry>{}.obs; // by postURL
  final RxList<DoujinCollection> collections = <DoujinCollection>[].obs;
  final RxList<DoujinFollow> followed = <DoujinFollow>[].obs;
  final RxList<DoujinEntry> history = <DoujinEntry>[].obs; // newest first
  final RxList<DoujinSavedSearch> savedSearches = <DoujinSavedSearch>[].obs;
  final RxList<DoujinPin> pins = <DoujinPin>[].obs;

  /// Favourite ("starred") tags on doujin sources — the doujin counterpart
  /// of the booru markedTags list, stored normalized (lowercase_underscores,
  /// namespace stripped). A star here has zero effect on booru surfaces and
  /// booru stars have zero effect here.
  final RxSet<String> starredTags = <String>{}.obs;

  /// Remembered doujin search queries (newest first).
  final RxList<DoujinSearchHistoryEntry> searchHistory = <DoujinSearchHistoryEntry>[].obs;
  int _searchHistoryNextId = 1;
  static const int searchHistoryCap = 200;
  int? lastBookmarkCollectionId;
  bool migrationDone = false;
  bool legacyBookmarksMerged = false;

  bool _loaded = false;

  File get _file => File('${SettingsHandler.instance.path}doujinData.json');

  void ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = _file;
      if (!file.existsSync()) return;
      importJson(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
    } catch (e, s) {
      Logger.Inst().log('failed to load doujin data: $e', 'DoujinDataHandler', 'ensureLoaded', LogTypes.exception, s: s);
    }
  }

  Map<String, dynamic> exportJson() => {
    'version': 1,
    'migrationDone': migrationDone,
    'legacyBookmarksMerged': legacyBookmarksMerged,
    'lastBookmarkCollectionId': lastBookmarkCollectionId,
    'favourites': [for (final e in favourites.values) e.toJson()],
    'collections': [for (final c in collections) c.toJson()],
    'followed': [for (final f in followed) f.toJson()],
    'history': [for (final e in history) e.toJson()],
    'savedSearches': [for (final s in savedSearches) s.toJson()],
    'pins': [for (final p in pins) p.toJson()],
    'starredTags': starredTags.toList(),
    'searchHistory': [for (final e in searchHistory) e.toJson()],
  };

  void importJson(Map<String, dynamic> data) {
    migrationDone = data['migrationDone'] as bool? ?? false;
    legacyBookmarksMerged = data['legacyBookmarksMerged'] as bool? ?? false;
    lastBookmarkCollectionId = data['lastBookmarkCollectionId'] as int?;
    favourites.clear();
    for (final entry in data['favourites'] as List? ?? []) {
      final e = DoujinEntry.fromJson(entry as Map<String, dynamic>);
      if (e.postURL.isNotEmpty) favourites[e.postURL] = e;
    }
    collections.assignAll([
      for (final c in data['collections'] as List? ?? []) DoujinCollection.fromJson(c as Map<String, dynamic>),
    ]);
    followed.assignAll([
      for (final f in data['followed'] as List? ?? []) DoujinFollow.fromJson(f as Map<String, dynamic>),
    ]);
    history.assignAll([
      for (final e in data['history'] as List? ?? []) DoujinEntry.fromJson(e as Map<String, dynamic>),
    ]);
    savedSearches.assignAll([
      for (final s in data['savedSearches'] as List? ?? []) DoujinSavedSearch.fromJson(s as Map<String, dynamic>),
    ]);
    pins.assignAll([
      for (final p in data['pins'] as List? ?? []) DoujinPin.fromJson(p as Map<String, dynamic>),
    ]);
    starredTags.assignAll({
      for (final t in data['starredTags'] as List? ?? []) t.toString(),
    });
    searchHistory.assignAll([
      for (final e in data['searchHistory'] as List? ?? [])
        DoujinSearchHistoryEntry.fromJson(e as Map<String, dynamic>),
    ]);
    _searchHistoryNextId = searchHistory.isEmpty
        ? 1
        : (searchHistory.map((e) => e.id).reduce((a, b) => a > b ? a : b) + 1);
  }

  void save() {
    try {
      _file.writeAsStringSync(jsonEncode(exportJson()));
    } catch (e, s) {
      Logger.Inst().log('failed to save doujin data: $e', 'DoujinDataHandler', 'save', LogTypes.exception, s: s);
    }
  }

  /// Forgets the in-memory state and reloads from the file on next access —
  /// used after a backup restore replaces doujinData.json on disk.
  void reloadFromDisk() {
    favourites.clear();
    collections.clear();
    followed.clear();
    history.clear();
    savedSearches.clear();
    pins.clear();
    starredTags.clear();
    searchHistory.clear();
    _searchHistoryNextId = 1;
    lastBookmarkCollectionId = null;
    migrationDone = false;
    legacyBookmarksMerged = false;
    _loaded = false;
    ensureLoaded();
  }

  /// Tests only.
  @visibleForTesting
  void resetForTests() {
    favourites.clear();
    collections.clear();
    followed.clear();
    history.clear();
    savedSearches.clear();
    pins.clear();
    starredTags.clear();
    searchHistory.clear();
    _searchHistoryNextId = 1;
    lastBookmarkCollectionId = null;
    migrationDone = false;
    legacyBookmarksMerged = false;
    _loaded = false;
  }

  /// Display title of a doujin item — the first non-empty line of its
  /// description (the convention every doujin surface uses).
  static String titleOf(BooruItem item) =>
      (item.description ?? '').split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '').trim();

  // ── search history ──

  /// Records a doujin search query. Newest first, deduped per (query, host),
  /// favourited entries survive the cap.
  void addSearchHistory(String query, Booru? booru) {
    ensureLoaded();
    final String text = query.trim();
    if (text.isEmpty) return;
    final String host = hostOf(booru);

    final int existing = searchHistory.indexWhere((e) => e.query == text && e.booruHost == host);
    final bool wasFavourite = existing != -1 && searchHistory[existing].isFavourite;
    final int id = existing != -1 ? searchHistory[existing].id : _searchHistoryNextId++;
    if (existing != -1) searchHistory.removeAt(existing);

    searchHistory.insert(
      0,
      DoujinSearchHistoryEntry(
        id: id,
        query: text,
        booruHost: host,
        at: DateTime.now().millisecondsSinceEpoch,
        isFavourite: wasFavourite,
      ),
    );

    if (searchHistory.length > searchHistoryCap) {
      final kept = <DoujinSearchHistoryEntry>[];
      for (final e in searchHistory) {
        if (e.isFavourite || kept.length < searchHistoryCap) kept.add(e);
      }
      searchHistory.assignAll(kept);
    }
    save();
  }

  /// [id] null clears everything except favourited entries' explicit removal
  /// (matching the booru history's "clear all" semantics, which deletes all).
  void deleteSearchHistory(int? id) {
    ensureLoaded();
    if (id == null) {
      searchHistory.clear();
    } else {
      searchHistory.removeWhere((e) => e.id == id);
    }
    save();
  }

  void setSearchHistoryFavourite(int id, bool isFavourite) {
    ensureLoaded();
    final int i = searchHistory.indexWhere((e) => e.id == id);
    if (i == -1) return;
    final updated = searchHistory.toList();
    updated[i] = updated[i].copyWith(isFavourite: isFavourite);
    searchHistory.assignAll(updated);
    save();
  }

  /// Queries matching [input] (prefix match), newest first.
  List<String> searchHistoryByInput(String input, int limit) {
    ensureLoaded();
    final String q = input.trim().toLowerCase();
    final List<String> out = [];
    for (final e in searchHistory) {
      if (out.length >= limit) break;
      if (q.isEmpty || e.query.toLowerCase().startsWith(q)) {
        if (!out.contains(e.query)) out.add(e.query);
      }
    }
    return out;
  }

  // ── starred (favourite) tags ──

  /// Normalizes to the store's token form: namespace stripped, lowercased,
  /// spaces to underscores — same as the doujin blacklist.
  static String normalizeTag(String raw) {
    String name = raw.trim().toLowerCase().replaceAll(' ', '_');
    final int colon = name.indexOf(':');
    if (colon != -1) name = name.substring(colon + 1);
    return name;
  }

  bool isTagStarred(String raw) {
    ensureLoaded();
    return starredTags.contains(normalizeTag(raw));
  }

  void starTag(String raw) {
    ensureLoaded();
    final String tag = normalizeTag(raw);
    if (tag.isEmpty || starredTags.contains(tag)) return;
    starredTags.add(tag);
    save();
  }

  void unstarTag(String raw) {
    ensureLoaded();
    if (starredTags.remove(normalizeTag(raw))) save();
  }

  /// Which of [itemTags] are starred, in item order (raw tag strings back).
  List<String> starredIn(List<String> itemTags) {
    ensureLoaded();
    if (starredTags.isEmpty) return const [];
    return [
      for (final t in itemTags)
        if (starredTags.contains(normalizeTag(t))) t,
    ];
  }

  // ── favourites ──

  bool isFavourite(BooruItem item) {
    ensureLoaded();
    return favourites.containsKey(item.postURL);
  }

  /// Returns the new state.
  bool toggleFavourite(BooruItem item, Booru? booru) {
    ensureLoaded();
    final bool nowFavourite;
    if (favourites.containsKey(item.postURL)) {
      favourites.remove(item.postURL);
      nowFavourite = false;
    } else {
      favourites[item.postURL] = DoujinEntry.fromItem(item, booru);
      nowFavourite = true;
    }
    item.isFavourite.value = nowFavourite;
    save();
    return nowFavourite;
  }

  List<DoujinEntry> favouritesList() {
    ensureLoaded();
    return favourites.values.toList()..sort((a, b) => b.addedAt.compareTo(a.addedAt));
  }

  /// THE favourite entry point for doujin items: toggles the doujin store and
  /// pushes the change to the site account when the source supports it. Every
  /// UI path (detail page button, card menu, double-tap) must go through this
  /// so account sync can never be skipped.
  Future<({bool nowFavourite, bool syncAttempted, bool syncOk, String? message})> toggleFavouriteSynced(
    BooruItem item,
    BooruHandler handler,
  ) async {
    final bool now = toggleFavourite(item, handler.booru);
    if (!handler.hasSiteFavourites) {
      return (nowFavourite: now, syncAttempted: false, syncOk: false, message: null);
    }
    final (bool ok, String message) = await handler.setSiteFavourite(item, now);
    return (nowFavourite: now, syncAttempted: true, syncOk: ok, message: message);
  }

  // ── collections ──

  DoujinCollection createCollection(String name) {
    ensureLoaded();
    final int id = (collections.isEmpty ? 0 : collections.map((c) => c.id).reduce((a, b) => a > b ? a : b)) + 1;
    final collection = DoujinCollection(id: id, name: name, createdAt: DateTime.now().millisecondsSinceEpoch);
    collections.add(collection);
    save();
    return collection;
  }

  void deleteCollection(int id) {
    ensureLoaded();
    collections.removeWhere((c) => c.id == id);
    if (lastBookmarkCollectionId == id) lastBookmarkCollectionId = null;
    save();
  }

  DoujinCollection? collectionById(int? id) {
    ensureLoaded();
    if (id == null) return null;
    for (final c in collections) {
      if (c.id == id) return c;
    }
    return null;
  }

  bool collectionContains(DoujinCollection collection, BooruItem item) =>
      collection.items.any((e) => e.postURL == item.postURL);

  void addToCollection(DoujinCollection collection, BooruItem item, Booru? booru) {
    ensureLoaded();
    if (!collectionContains(collection, item)) {
      collection.items.add(DoujinEntry.fromItem(item, booru));
    }
    lastBookmarkCollectionId = collection.id;
    // Nested mutation (collection.items) doesn't notify the RxList; reassign so
    // Obx watchers rebuild.
    collections.assignAll(collections.toList());
    save();
  }

  void removeFromCollection(DoujinCollection collection, BooruItem item) =>
      removeEntryFromCollection(collection, item.postURL);

  void removeEntryFromCollection(DoujinCollection collection, String postURL) {
    ensureLoaded();
    collection.items.removeWhere((e) => e.postURL == postURL);
    collections.assignAll(collections.toList());
    save();
  }

  void removeFromCollections(BooruItem item) {
    ensureLoaded();
    for (final c in collections) {
      c.items.removeWhere((e) => e.postURL == item.postURL);
    }
    collections.assignAll(collections.toList());
    save();
  }

  bool isInAnyCollection(BooruItem item) {
    ensureLoaded();
    return collections.any((c) => collectionContains(c, item));
  }

  /// Which collection a NEW bookmark goes into: the last one used for
  /// bookmarking, else the first existing one, else a fresh "Default".
  DoujinCollection bookmarkCollection() {
    ensureLoaded();
    final DoujinCollection? last = collectionById(lastBookmarkCollectionId);
    if (last != null) return last;
    if (collections.isNotEmpty) return collections.first;
    return createCollection('Default');
  }

  /// The bookmark action: files the doujin into [bookmarkCollection] (or
  /// pulls it out of every collection when it's already in one). Returns the
  /// new bookmarked state and the collection involved.
  (bool, DoujinCollection?) toggleBookmark(BooruItem item, Booru? booru) {
    ensureLoaded();
    if (isInAnyCollection(item)) {
      removeFromCollections(item);
      return (false, null);
    }
    final DoujinCollection target = bookmarkCollection();
    addToCollection(target, item, booru);
    return (true, target);
  }

  /// One-time merge of the old flat bookmarks.json list into the bookmark
  /// collection — bookmarks ARE collection entries now.
  void mergeLegacyBookmarks(Iterable<DoujinEntry> legacy) {
    ensureLoaded();
    if (legacyBookmarksMerged) return;
    final List<DoujinEntry> entries = legacy.toList();
    if (entries.isNotEmpty) {
      final DoujinCollection target = bookmarkCollection();
      for (final e in entries) {
        if (!target.items.any((x) => x.postURL == e.postURL)) target.items.add(e);
      }
      collections.assignAll(collections.toList());
    }
    legacyBookmarksMerged = true;
    save();
  }

  // ── followed artists ──

  bool isFollowed(String tag, Booru? booru) {
    ensureLoaded();
    final String host = hostOf(booru);
    return followed.any((f) => f.tag == tag && f.booruHost == host);
  }

  bool toggleFollow(String tag, Booru? booru) {
    ensureLoaded();
    final String host = hostOf(booru);
    final int before = followed.length;
    followed.removeWhere((f) => f.tag == tag && f.booruHost == host);
    final bool nowFollowed = followed.length == before;
    if (nowFollowed) {
      followed.add(DoujinFollow(tag: tag, booruHost: host, addedAt: DateTime.now().millisecondsSinceEpoch));
    }
    save();
    return nowFollowed;
  }

  // ── history ──

  void addHistory(BooruItem item, Booru? booru) {
    ensureLoaded();
    if (item.postURL.isEmpty) return;
    history.removeWhere((e) => e.postURL == item.postURL);
    history.insert(0, DoujinEntry.fromItem(item, booru));
    if (history.length > historyCap) history.removeRange(historyCap, history.length);
    save();
  }

  void clearHistory() {
    ensureLoaded();
    history.clear();
    save();
  }

  // ── saved searches ──

  DoujinSavedSearch addSavedSearch({required String name, required String query, required Booru? booru}) {
    ensureLoaded();
    final int id = (savedSearches.isEmpty ? 0 : savedSearches.map((s) => s.id).reduce((a, b) => a > b ? a : b)) + 1;
    final entry = DoujinSavedSearch(
      id: id,
      name: name,
      query: query,
      booruHost: hostOf(booru),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    savedSearches.insert(0, entry);
    save();
    return entry;
  }

  void deleteSavedSearch(int id) {
    ensureLoaded();
    savedSearches.removeWhere((s) => s.id == id);
    save();
  }

  /// null host = all doujin saved searches ("Global" view).
  List<DoujinSavedSearch> savedSearchesFor(String? host) {
    ensureLoaded();
    return [
      for (final s in savedSearches)
        if (host == null || s.booruHost == host) s,
    ];
  }

  // ── pinned tags ──

  /// Pins shown on [booru]'s surfaces: its own + the doujin-global ones.
  /// NEVER includes booru pins — different store entirely.
  List<DoujinPin> pinsFor(Booru? booru) {
    ensureLoaded();
    final String host = hostOf(booru);
    return [
      for (final p in pins)
        if (p.booruHost == null || p.booruHost == host) p,
    ];
  }

  bool isPinned(String tag, Booru? booru) => pinsFor(booru).any((p) => p.tag == tag);

  void addPin(String tag, Booru? booru, {bool global = false}) {
    ensureLoaded();
    if (isPinned(tag, booru)) return;
    pins.add(
      DoujinPin(
        tag: tag,
        booruHost: global ? null : hostOf(booru),
        addedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    save();
  }

  void removePin(String tag, Booru? booru) {
    ensureLoaded();
    final String host = hostOf(booru);
    pins.removeWhere((p) => p.tag == tag && (p.booruHost == null || p.booruHost == host));
    save();
  }
}
