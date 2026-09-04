import 'package:get/get.dart' hide ContextExt, FirstWhereOrNullExt;

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/site_profile.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// Lazy per-post file lists for sites where one post is a gallery.
///
/// Most booru APIs describe a post with a single file/preview pair, so a
/// multi-file post silently collapses to its cover. Sites that keep the real
/// list somewhere else expose it through [SiteProfile.postFilesUrl] /
/// [SiteProfile.parsePostFiles].
///
/// Fetching costs one page request per post, so it happens ONLY when a post is
/// opened — never during grid loading — and results are cached for the session.
class PostFilesHandler {
  PostFilesHandler._();

  static final PostFilesHandler instance = PostFilesHandler._();

  /// postURL -> files. Reactive so the viewer's toolbar can reveal its action
  /// the moment a list arrives.
  final RxMap<String, List<PostFile>> loaded = <String, List<PostFile>>{}.obs;

  final Map<String, Future<List<PostFile>>> _inFlight = {};
  final Set<String> _failed = {};

  static String _keyOf(BooruItem item) => item.postURL.isNotEmpty ? item.postURL : item.fileURL;

  /// Files already known for [item], or null when not fetched (yet).
  List<PostFile>? cached(BooruItem item) => loaded[_keyOf(item)];

  /// True when this post is known to hold more than one file.
  /// Only what the viewer can show counts: an archive beside one picture is
  /// not a gallery.
  static List<PostFile> displayable(List<PostFile> files) => files.where((f) => f.isDisplayable).toList();

  bool hasMultiple(BooruItem item) => displayable(cached(item) ?? const []).length > 1;

  bool supports(Booru? booru) => SiteProfile.forBooru(booru)?.hasMultipleFilesPerPost ?? false;

  /// Fetches the file list for [item] once, caching the result.
  ///
  /// Safe to call repeatedly (deduped, and failures aren't retried in a loop).
  Future<List<PostFile>> ensureLoaded(BooruItem item, Booru? booru) async {
    final String key = _keyOf(item);
    final List<PostFile>? already = loaded[key];
    if (already != null) return already;
    if (_failed.contains(key)) return const [];

    final SiteProfile? profile = SiteProfile.forBooru(booru);
    if (profile == null || !profile.hasMultipleFilesPerPost || booru == null) return const [];

    final String? url = profile.postFilesUrl(booru, item);
    if (url == null) {
      _failed.add(key);
      return const [];
    }

    return _inFlight[key] ??= () async {
      try {
        final headers = {
          ...await Tools.getFileCustomHeaders(booru, item: item, checkForReferer: true),
          ...profile.postFilesHeaders(booru),
        };
        final response = await DioNetwork.get(url, headers: headers).timeout(const Duration(seconds: 20));
        final List<PostFile>? files = profile.parsePostFiles(response.data?.toString() ?? '', booru);
        if (files == null || files.isEmpty) {
          _failed.add(key);
          return const <PostFile>[];
        }
        // The grid badge reads this on the way back out of the viewer.
        item.fileCountHint.value = displayable(files).length;
        loaded[key] = files;
        return files;
      } catch (e) {
        Logger.Inst().log(
          'failed to load post files from $url: $e',
          'PostFilesHandler',
          'ensureLoaded',
          LogTypes.booruItemLoad,
        );
        _failed.add(key);
        return const <PostFile>[];
      } finally {
        _inFlight.remove(key);
      }
    }();
  }

  // Backfill bookkeeping: which (booru, query, page) sweeps already ran.
  final Set<String> _enriched = {};

  /// Fills in file counts for items whose API gave none, so gallery posts are
  /// recognisable in the GRID without opening them.
  ///
  /// The API here exposes no multi-file signal whatsoever, and probing each
  /// post would cost one request per grid cell. The site's own listing prints
  /// the count, so a handful of listing pages are fetched once per API page
  /// and matched back BY POST ID — order-independent, and items the sweep
  /// doesn't cover simply stay unbadged until opened.
  Future<void> enrichCounts(List<BooruItem> items, Booru? booru, String tags) async {
    final SiteProfile? profile = SiteProfile.forBooru(booru);
    if (profile == null || booru == null || items.isEmpty) return;

    final List<BooruItem> missing = items.where((i) => i.fileCountHint.value == null).toList();
    if (missing.isEmpty) return;

    const int maxPages = 4;
    final Map<String, BooruItem> byId = {
      for (final item in missing)
        if (item.serverId?.isNotEmpty ?? false) item.serverId!: item,
    };
    if (byId.isEmpty) return;

    for (int page = 0; page < maxPages && byId.isNotEmpty; page++) {
      final String? url = profile.enrichmentUrl(booru, tags, page);
      if (url == null) return;
      final String sweepKey = '${booru.name}|$url';
      if (!_enriched.add(sweepKey)) continue;

      try {
        final response = await DioNetwork.get(url).timeout(const Duration(seconds: 15));
        final List<BooruItem>? listing = profile.parseListing(response.data?.toString() ?? '', booru);
        if (listing == null || listing.isEmpty) return;

        for (final scraped in listing) {
          final String? id = scraped.serverId;
          final int? count = scraped.fileCountHint.value;
          if (id == null || count == null) continue;
          final BooruItem? target = byId.remove(id);
          // Reactive: the grid cell may already be on screen.
          target?.fileCountHint.value = count;
        }
      } catch (e) {
        Logger.Inst().log(
          'file-count backfill failed for $url: $e',
          'PostFilesHandler',
          'enrichCounts',
          LogTypes.booruHandlerInfo,
        );
        return;
      }
    }
  }

  /// Builds viewer-ready items for a post's files.
  ///
  /// Each file becomes a BooruItem so it can go through the SAME viewer
  /// widgets as any other post — no second player or image pipeline. Videos on
  /// some sites have no poster frame, so they fall back to the post's cover.
  List<BooruItem> itemsFor(BooruItem post, List<PostFile> files) {
    return [
      for (final file in displayable(files))
        BooruItem(
          fileURL: file.url,
          sampleURL: file.url,
          thumbnailURL: file.thumbnailUrl ?? post.thumbnailURL,
          tagsList: post.tagsList,
          postURL: post.postURL,
          serverId: post.serverId,
          rating: post.rating,
          sources: post.sources,
          // kind comes from the site, so don't let extension guessing override
          // it — a video served from a query-string URL would guess wrong.
          fileExt: file.isVideo ? Tools.getFileExt(file.url) : null,
          downloadFileName: file.name,
        ),
    ];
  }
}
