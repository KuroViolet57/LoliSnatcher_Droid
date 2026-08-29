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

  factory DoujinEntry.fromItem(BooruItem item, Booru? booru) => DoujinEntry(
    postURL: item.postURL,
    serverId: item.serverId ?? '',
    thumbnailURL: item.thumbnailURL,
    title: (item.description ?? '').split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => ''),
    booruHost: Uri.tryParse(booru?.baseURL ?? '')?.host ?? '',
    addedAt: DateTime.now().millisecondsSinceEpoch,
  );

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

  // ── state ──
  final RxMap<String, DoujinEntry> favourites = <String, DoujinEntry>{}.obs; // by postURL
  final RxList<DoujinCollection> collections = <DoujinCollection>[].obs;
  final RxList<DoujinFollow> followed = <DoujinFollow>[].obs;
  final RxList<DoujinEntry> history = <DoujinEntry>[].obs; // newest first
  final RxList<DoujinSavedSearch> savedSearches = <DoujinSavedSearch>[].obs;
  final RxList<DoujinPin> pins = <DoujinPin>[].obs;
  int? lastBookmarkCollectionId;
  bool migrationDone = false;

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
    'lastBookmarkCollectionId': lastBookmarkCollectionId,
    'favourites': [for (final e in favourites.values) e.toJson()],
    'collections': [for (final c in collections) c.toJson()],
    'followed': [for (final f in followed) f.toJson()],
    'history': [for (final e in history) e.toJson()],
    'savedSearches': [for (final s in savedSearches) s.toJson()],
    'pins': [for (final p in pins) p.toJson()],
  };

  void importJson(Map<String, dynamic> data) {
    migrationDone = data['migrationDone'] as bool? ?? false;
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
    lastBookmarkCollectionId = null;
    migrationDone = false;
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
    lastBookmarkCollectionId = null;
    migrationDone = false;
    _loaded = false;
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

  void removeFromCollection(DoujinCollection collection, BooruItem item) {
    ensureLoaded();
    collection.items.removeWhere((e) => e.postURL == item.postURL);
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
