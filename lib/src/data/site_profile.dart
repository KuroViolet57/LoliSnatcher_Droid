import 'package:collection/collection.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/site_profiles/bakemono_profile.dart';
import 'package:lolisnatcher/src/data/site_profiles/kemono_profile.dart';

/// Per-SITE deviations from a booru FAMILY's behaviour.
///
/// A handler class describes an API family (Gelbooru 0.2, Danbooru, ...), but
/// "gelbooru-compatible" never means "identical to gelbooru": sites implement
/// a subset, spell endpoints differently, or expose extra capabilities their
/// documented API doesn't mention. Overriding a shared handler for one such
/// site would change behaviour for every site on that handler, and patching
/// call sites scatters the knowledge — so site-specific behaviour lives here,
/// resolved per [Booru] by HOST.
///
/// Every hook defaults to "no opinion" (null / false), meaning the family
/// behaviour applies unchanged. Adding a site means adding one profile class
/// and one registry entry; no shared handler changes.
abstract class SiteProfile {
  const SiteProfile();

  /// Hosts this profile applies to (without `www.`).
  Set<String> get hosts;

  /// Human-readable id, used in logs.
  String get id;

  static final List<SiteProfile> _registry = [
    const BakemonoProfile(),
    const KemonoProfile(),
  ];

  static final Map<String, SiteProfile?> _cache = {};

  /// Profile for [booru], or null when the site needs no deviations.
  static SiteProfile? forBooru(Booru? booru) {
    final String host = Uri.tryParse(booru?.baseURL ?? '')?.host.replaceFirst('www.', '') ?? '';
    if (host.isEmpty) return null;
    return _cache.putIfAbsent(
      host,
      () => _registry.firstWhereOrNull((p) => p.hosts.contains(host)),
    );
  }

  //
  // Tag suggestions
  //

  /// Autocomplete endpoint for this site, or null to use the family's.
  String? tagSuggestionsUrl(Booru booru, String input) => null;

  /// Post count for a suggestion when the site doesn't expose a plain
  /// count field (e.g. it is baked into a display label).
  int? tagSuggestionCount(dynamic responseItem) => null;

  //
  // Meta tags
  //

  /// Replaces the family's meta tag menu. The family list advertises options
  /// that often don't exist on a given site; returning a list here keeps the
  /// menu honest. Null = keep the family's.
  List<MetaTag>? metaTags() => null;

  //
  // "Videos / GIFs only" filter
  //

  /// Tag queries that isolate animated content. An EMPTY list means the site
  /// genuinely has no way to express it, and the control should be hidden
  /// rather than appending tags that match nothing. Null = family default.
  List<String>? animatedFilters() => null;

  //
  // Alternate listing (used when the documented API can't serve a query)
  //

  /// URL of a non-API listing able to serve [tags], or null to use the API.
  /// Implementations decide when the API is insufficient (e.g. the API can't
  /// sort), so the handler needs no per-site knowledge.
  String? listingUrl(Booru booru, String tags, int pageNum, int limit) => null;

  /// Parses a [listingUrl] response body into items.
  ///
  /// Returning null means "couldn't parse" — the caller must fall back to the
  /// API rather than show an empty grid, because this is HTML scraping and
  /// markup shifts without warning.
  List<BooruItem>? parseListing(String body, Booru booru) => null;

  /// A listing page used only to backfill metadata the API omits (file
  /// counts), matched back to API items by id. Null = nothing to backfill.
  String? enrichmentUrl(Booru booru, String tags, int listingPage) => null;

  /// Items a [listingUrl] page can return, when the site caps it and ignores
  /// any limit parameter. 0 = no known cap.
  int get listingPageSize => 0;

  //
  // Multi-file posts
  //

  /// True when one post can hold several media files that the API's single
  /// file/preview pair doesn't expose.
  bool get hasMultipleFilesPerPost => false;

  /// Page that carries the full file list for [item] (fetched lazily, only
  /// when the user opens the post), or null when unsupported.
  String? postFilesUrl(Booru booru, BooruItem item) => null;

  /// Extra headers the [postFilesUrl] request needs on top of the media
  /// headers (kemono's API refuses a browser Accept).
  Map<String, String> postFilesHeaders(Booru booru) => const {};

  /// Parses [postFilesUrl]'s body into the post's files. Null = parse failed.
  List<PostFile>? parsePostFiles(String body, Booru booru) => null;
}

/// One media file belonging to a post, for sites where a post is a gallery.
class PostFile {
  const PostFile({
    required this.url,
    required this.isVideo,
    this.thumbnailUrl,
    this.name,
    this.isDisplayable = true,
  });

  final String url;
  final bool isVideo;

  /// The name the site gives the file, when it has one; downloads keep it.
  final String? name;

  /// False for an archive, a psd, anything the viewer cannot show: listed on
  /// the post page, never put in the carousel.
  final bool isDisplayable;

  /// Null for videos on sites that don't render a poster frame — callers fall
  /// back to the post's own cover.
  final String? thumbnailUrl;
}
