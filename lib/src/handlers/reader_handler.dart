import 'package:get/get.dart' hide ContextExt, FirstWhereOrNullExt;

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// Saved reading position for one gallery.
class ReaderProgress {
  const ReaderProgress({
    required this.page,
    required this.totalPages,
    required this.updatedAt,
  });

  /// Last page the reader was on, 0-based.
  final int page;
  final int totalPages;
  final int updatedAt;

  bool get isFinished => totalPages > 0 && page >= totalPages - 1;
}

/// Doujin books: per-post ordered page lists + persistent reading progress.
///
/// This is the reader-shaped sibling of PostFilesHandler: that one serves
/// sites where a post happens to hold a few files (carousel), this one serves
/// sites where a post IS a book — ordered pages read front to back, where
/// remembering the position matters. Handlers whose `hasReader` is true push
/// the page list in from their `loadItem`, and the viewer/drawer ask here.
///
/// Progress is keyed on (booru host, gallery id) and stored in the
/// ReaderProgress DB table so "Continue reading" survives restarts; with the
/// DB disabled it degrades to session memory.
class ReaderHandler {
  ReaderHandler._();

  static final ReaderHandler instance = ReaderHandler._();

  /// postURL -> ordered pages. Reactive so the toolbar action can appear the
  /// moment loadItem finishes while the viewer is already open.
  final RxMap<String, List<BooruItem>> books = <String, List<BooruItem>>{}.obs;

  static String _keyOf(BooruItem item) => item.postURL.isNotEmpty ? item.postURL : item.fileURL;

  List<BooruItem>? pagesFor(BooruItem item) => books[_keyOf(item)];

  bool hasBook(BooruItem item) => (pagesFor(item)?.length ?? 0) > 0;

  /// Called by a handler's loadItem once it knows the page list.
  void registerBook(BooruItem item, List<BooruItem> pages) {
    if (pages.isEmpty) return;
    books[_keyOf(item)] = pages;
    item.fileCountHint.value = pages.length;
  }

  // ─────────────────────────── progress ───────────────────────────

  /// Memory cache over the DB, also the sole store when the DB is off.
  final Map<String, ReaderProgress> _progress = {};
  final Set<String> _progressLoaded = {};

  static String progressKey(Booru? booru, String galleryId) {
    final String host = Uri.tryParse(booru?.baseURL ?? '')?.host ?? (booru?.name ?? '');
    return '$host|$galleryId';
  }

  ReaderProgress? cachedProgress(Booru? booru, String galleryId) => _progress[progressKey(booru, galleryId)];

  /// Loads progress for one gallery into the memory cache (DB hit only once
  /// per gallery per session).
  Future<ReaderProgress?> loadProgress(Booru? booru, String galleryId) async {
    final String key = progressKey(booru, galleryId);
    if (_progressLoaded.contains(key)) return _progress[key];
    _progressLoaded.add(key);

    final settingsHandler = SettingsHandler.instance;
    if (!settingsHandler.dbEnabled) return _progress[key];
    try {
      final row = await settingsHandler.dbHandler.getReaderProgress(key);
      if (row != null) {
        _progress[key] = ReaderProgress(
          page: (row['page'] as int?) ?? 0,
          totalPages: (row['totalPages'] as int?) ?? 0,
          updatedAt: (row['updatedAt'] as int?) ?? 0,
        );
      }
    } catch (e, s) {
      Logger.Inst().log('failed to load reader progress: $e', 'ReaderHandler', 'loadProgress', LogTypes.exception, s: s);
    }
    return _progress[key];
  }

  void saveProgress(Booru? booru, String galleryId, int page, int totalPages) {
    final String key = progressKey(booru, galleryId);
    final progress = ReaderProgress(
      page: page,
      totalPages: totalPages,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _progress[key] = progress;
    _progressLoaded.add(key);

    final settingsHandler = SettingsHandler.instance;
    if (!settingsHandler.dbEnabled) return;
    // Fire and forget: a lost write costs one page of position at worst.
    settingsHandler.dbHandler.updateReaderProgress(key, page, totalPages, progress.updatedAt);
  }
}
