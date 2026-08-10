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
  bool hasMultiple(BooruItem item) => (cached(item)?.length ?? 0) > 1;

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
        final headers = await Tools.getFileCustomHeaders(booru, item: item, checkForReferer: true);
        final response = await DioNetwork.get(url, headers: headers).timeout(const Duration(seconds: 20));
        final List<PostFile>? files = profile.parsePostFiles(response.data?.toString() ?? '', booru);
        if (files == null || files.isEmpty) {
          _failed.add(key);
          return const <PostFile>[];
        }
        // The grid badge reads this on the way back out of the viewer.
        item.fileCountHint = files.length;
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

  /// Builds viewer-ready items for a post's files.
  ///
  /// Each file becomes a BooruItem so it can go through the SAME viewer
  /// widgets as any other post — no second player or image pipeline. Videos on
  /// some sites have no poster frame, so they fall back to the post's cover.
  List<BooruItem> itemsFor(BooruItem post, List<PostFile> files) {
    return [
      for (final file in files)
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
        ),
    ];
  }
}
