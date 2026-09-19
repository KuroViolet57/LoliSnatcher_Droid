import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart' hide ContextExt, FirstWhereOrNullExt;

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// One bookmarked doujin: enough of a snapshot to render a list entry and
/// reopen the gallery without refetching.
class DoujinBookmark {
  const DoujinBookmark({
    required this.postURL,
    required this.serverId,
    required this.thumbnailURL,
    required this.title,
    required this.booruHost,
    required this.addedAt,
  });

  factory DoujinBookmark.fromJson(Map<String, dynamic> json) => DoujinBookmark(
    postURL: json['postURL'] as String? ?? '',
    serverId: json['serverId'] as String? ?? '',
    thumbnailURL: json['thumbnailURL'] as String? ?? '',
    title: json['title'] as String? ?? '',
    booruHost: json['booruHost'] as String? ?? '',
    addedAt: json['addedAt'] as int? ?? 0,
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

/// Purely LOCAL bookmarks for doujins — never talks to any site, unlike the
/// detail page's favourite (which can sync to an account). Persisted as
/// bookmarks.json next to settings.json.
class BookmarkHandler {
  BookmarkHandler._();

  static final BookmarkHandler instance = BookmarkHandler._();

  /// postURL -> bookmark. Reactive so buttons/lists update immediately.
  final RxMap<String, DoujinBookmark> bookmarks = <String, DoujinBookmark>{}.obs;
  bool _loaded = false;

  File get _file => File('${SettingsHandler.instance.path}bookmarks.json');

  void ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = _file;
      if (!file.existsSync()) return;
      final List<dynamic> data = jsonDecode(file.readAsStringSync());
      for (final entry in data) {
        final bookmark = DoujinBookmark.fromJson(entry as Map<String, dynamic>);
        if (bookmark.postURL.isNotEmpty) bookmarks[bookmark.postURL] = bookmark;
      }
    } catch (e, s) {
      Logger.Inst().log('failed to load bookmarks: $e', 'BookmarkHandler', 'ensureLoaded', LogTypes.exception, s: s);
    }
  }

  void _save() {
    try {
      _file.writeAsStringSync(jsonEncode([for (final b in bookmarks.values) b.toJson()]));
    } catch (e, s) {
      Logger.Inst().log('failed to save bookmarks: $e', 'BookmarkHandler', '_save', LogTypes.exception, s: s);
    }
  }

  /// Forgets the in-memory state and reloads from the file — used after a
  /// backup restore replaces bookmarks.json on disk.
  void reloadFromDisk() {
    bookmarks.clear();
    _loaded = false;
    ensureLoaded();
  }

  bool isBookmarked(BooruItem item) {
    ensureLoaded();
    return bookmarks.containsKey(item.postURL);
  }

  /// Returns the new state.
  bool toggle(BooruItem item, Booru? booru) {
    ensureLoaded();
    if (bookmarks.containsKey(item.postURL)) {
      bookmarks.remove(item.postURL);
      _save();
      return false;
    }
    bookmarks[item.postURL] = DoujinBookmark(
      postURL: item.postURL,
      serverId: item.serverId ?? '',
      thumbnailURL: item.thumbnailURL,
      title: (item.description ?? '').split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => ''),
      booruHost: Uri.tryParse(booru?.baseURL ?? '')?.host ?? '',
      addedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _save();
    return true;
  }

  void remove(String postURL) {
    ensureLoaded();
    if (bookmarks.remove(postURL) != null) _save();
  }

  List<DoujinBookmark> all() {
    ensureLoaded();
    final List<DoujinBookmark> list = bookmarks.values.toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return list;
  }
}
