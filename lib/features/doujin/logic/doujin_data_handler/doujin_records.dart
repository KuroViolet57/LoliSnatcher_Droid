part of '../doujin_data_handler.dart';

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
    this.tags = const [],
    this.pages,
  });

  factory DoujinEntry.fromJson(Map<String, dynamic> json) => DoujinEntry(
    postURL: json['postURL'] as String? ?? '',
    serverId: json['serverId'] as String? ?? '',
    thumbnailURL: json['thumbnailURL'] as String? ?? '',
    title: json['title'] as String? ?? '',
    booruHost: json['booruHost'] as String? ?? '',
    addedAt: json['addedAt'] as int? ?? 0,
    tags: [for (final t in json['tags'] as List? ?? const []) t.toString()],
    pages: json['pages'] as int?,
  );

  /// [tags] are the gallery's namespaced tags (`parody:genshin_impact`);
  /// see [DoujinDataHandler.namespacedTagsOf]. Without them, the item's own
  /// tag list is read through the tag types.
  factory DoujinEntry.fromItem(BooruItem item, Booru? booru, {List<String>? tags}) {
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
      tags: tags ?? DoujinDataHandler.namespacedTagsOf(item),
      pages: item.fileCountHint.value,
    );
  }

  final String postURL;
  final String serverId;
  final String thumbnailURL;
  final String title;
  final String booruHost;
  final int addedAt;

  /// The gallery's tags with their namespace (`artist:x`, `female:y`), bare
  /// when the source filed them under none. Empty for entries saved before
  /// r33. What the doujin For You and the recommender read a history from.
  final List<String> tags;

  /// The gallery's page count, when known.
  final int? pages;

  DoujinEntry withTags(List<String> tags, {int? pages}) => DoujinEntry(
    postURL: postURL,
    serverId: serverId,
    thumbnailURL: thumbnailURL,
    title: title,
    booruHost: booruHost,
    addedAt: addedAt,
    tags: tags,
    pages: pages ?? this.pages,
  );

  Map<String, dynamic> toJson() => {
    'postURL': postURL,
    'serverId': serverId,
    'thumbnailURL': thumbnailURL,
    'title': title,
    'booruHost': booruHost,
    'addedAt': addedAt,
    if (tags.isNotEmpty) 'tags': tags,
    if (pages != null) 'pages': pages,
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
