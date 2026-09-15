import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import 'package:dio/dio.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/boorus/doujin/doujin_filters.dart';
import 'package:lolisnatcher/src/boorus/furaffinity_parser.dart';
import 'package:lolisnatcher/src/boorus/furaffinity_query.dart';
import 'package:lolisnatcher/src/boorus/furaffinity_tag_catalog.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/furaffinity_session_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// FurAffinity (r40), read from its pages — the site has no content API.
///
/// Routes and filters: see [FurAffinityQuery]. A card is built from the
/// listing figure (thumbnail, title, artist, rating, type, the site's
/// category/theme/species and keywords); the full file comes from the
/// submission page when the card is opened ([loadItem]). Logged in
/// ([FurAffinitySessionHandler]), mature and adult submissions come through
/// as far as the account's own content filter allows.
class FurAffinityHandler extends BooruHandler {
  FurAffinityHandler(super.booru, super.limit);

  static const int pageSize = 48;

  FurAffinitySessionHandler get session => FurAffinitySessionHandler.instance;

  /// 1-based: the search handler increments pageNum before the first fetch.
  int get page => pageNum < 0 ? 1 : pageNum + 1;

  /// Favorites page by cursor: query -> page -> the cursor that reaches it.
  final Map<String, Map<int, String>> _favoritesCursors = {};

  TagCatalogSource? _catalog;

  @override
  bool get hasSizeData => false;

  @override
  bool get hasNativeOrSupport => false;

  @override
  bool get hasLoadItemSupport => true;

  @override
  bool get usesUserId => false;

  @override
  bool get usesApiKey => false;

  /// The session is the site's; its images come from other hosts.
  @override
  bool get sendsJarCookiesToMedia => false;

  @override
  String validateTags(String tags) => tags.trim();

  @override
  List<MetaTag> availableMetaTags() => [];

  @override
  TagCatalogSource? get tagCatalog => _catalog ??= FurAffinityTagCatalog(this);

  @override
  Map<String, String> getHeaders() {
    final Map<String, String> headers = {...super.getHeaders(), 'Accept': 'text/html'};
    final String cookie = session.cookieHeader();
    if (cookie.isNotEmpty) headers['Cookie'] = cookie;
    return headers;
  }

  @override
  Map<String, String> getMediaHeaders() => const {'Referer': '${FurAffinityQuery.site}/'};

  @override
  String makePostURL(String id) => '${FurAffinityQuery.site}/view/$id/';

  static const Set<String> _namespaces = {'artist', 'rating', 'type', 'category', 'theme', 'species'};

  @override
  String? tagNamespace(String tag) {
    final int colon = tag.indexOf(':');
    if (colon <= 0) return null;
    final String ns = tag.substring(0, colon);
    return _namespaces.contains(ns) ? ns : null;
  }

  @override
  String makeURL(String tags) {
    final FurAffinityQuery query = FurAffinityQuery.parse(tags);
    String? cursor;
    if (query.kind == FurAffinityRoute.favorites) cursor = _favoritesCursors[tags.trim()]?[page];
    final String url = query.url(page: page, cursor: cursor);
    if (url.isEmpty) locked = true;
    return url;
  }

  @override
  FutureOr<List> parseListFromResponse(dynamic response) {
    final String body = response.data?.toString() ?? '';
    final FurAffinityQuery query = FurAffinityQuery.parse(currentTags);
    if (query.kind == FurAffinityRoute.view) {
      final BooruItem? item = _single(body, query.id);
      if (item == null) errorString = 'This submission could not be read (it may need you to log in, or be removed).';
      locked = true;
      return item == null ? const [] : [item];
    }
    final List<BooruItem> items = FurAffinityParser.listing(body);
    if (items.isEmpty) {
      locked = true;
      if (body.contains('System Message')) {
        errorString = 'FurAffinity answered with a system message: the page needs a login, or the account does not exist.';
      }
      return items;
    }
    switch (query.kind) {
      case FurAffinityRoute.gallery || FurAffinityRoute.scraps:
        if (!FurAffinityParser.galleryHasNext(body)) locked = true;
      case FurAffinityRoute.favorites:
        final String? cursor = FurAffinityParser.favoritesCursor(body);
        if (cursor == null) {
          locked = true;
        } else {
          (_favoritesCursors[currentTags.trim()] ??= {})[page + 1] = cursor;
        }
      default:
        break;
    }
    return items;
  }

  @override
  FutureOr<BooruItem?> parseItemFromResponse(dynamic responseItem, int index) => responseItem is BooruItem ? responseItem : null;

  BooruItem? _single(String body, String id) {
    final FurAffinitySubmission? s = FurAffinityParser.submission(body);
    if (s == null) return null;
    final BooruItem item = BooruItem(
      fileURL: s.fileUrl,
      sampleURL: s.previewUrl.isNotEmpty ? s.previewUrl : s.fileUrl,
      thumbnailURL: s.previewUrl.isNotEmpty ? s.previewUrl : s.fileUrl,
      tagsList: [if (s.artist.isNotEmpty) Tag('artist:${s.artist}', tagType: TagType.artist)],
      postURL: makePostURL(id),
      serverId: id,
    );
    applySubmission(item, s);
    return item;
  }

  @override
  Future<({BooruItem? item, bool failed, String? error})> loadItem({
    required BooruItem item,
    CancelToken? cancelToken,
    bool withCapcthaCheck = false,
  }) async {
    try {
      final response = await DioNetwork.get(item.postURL, headers: getHeaders(), cancelToken: cancelToken);
      final FurAffinitySubmission? s = FurAffinityParser.submission(response.data?.toString() ?? '');
      if (s == null) {
        return (
          item: null,
          failed: true,
          error: session.isLoggedIn
              ? 'The file is not on the submission page.'
              : 'The file is not on the submission page: music, stories and mature submissions need you to log in.',
        );
      }
      applySubmission(item, s);
      return (item: item, failed: false, error: null);
    } catch (e, s) {
      Logger.Inst().log('loading ${item.postURL} failed: $e', className, 'loadItem', LogTypes.exception, s: s);
      return (item: null, failed: true, error: e.toString());
    }
  }

  static const Set<String> _audio = {'mp3', 'wav', 'ogg', 'm4a', 'flac', 'aac', 'mid', 'midi'};
  static const Set<String> _images = {'png', 'jpg', 'jpeg', 'webp', 'bmp'};

  /// Fills [item] from its submission page: the file and what kind it is,
  /// the title, the keywords, the stats.
  @visibleForTesting
  void applySubmission(BooruItem item, FurAffinitySubmission s) {
    final String path = Uri.tryParse(s.fileUrl)?.path ?? s.fileUrl;
    final int dot = path.lastIndexOf('.');
    final String ext = dot >= 0 ? path.substring(dot + 1).toLowerCase() : '';
    item
      ..fileURL = s.fileUrl
      ..fileExt = ext.isEmpty ? null : ext
      ..description = s.title.isNotEmpty ? s.title : item.description
      ..uploaderName = s.artistName.isNotEmpty ? s.artistName : item.uploaderName
      ..score = '${s.favorites}'
      ..postDate = s.postedAt?.toString()
      ..postDateFormat = s.postedAt == null ? item.postDateFormat : 'unix'
      ..isUpdated = true;
    if (s.previewUrl.isNotEmpty && (ext == 'gif' || _images.contains(ext))) item.sampleURL = s.previewUrl;
    final Set<String> names = item.tagsList.map((t) => t.fullString).toSet();
    void add(String name, TagType type) {
      if (name.isNotEmpty && names.add(name)) item.tagsList.add(Tag(name, tagType: type));
    }

    if (s.rating.isNotEmpty) add('rating:${s.rating}', TagType.meta);
    for (final String k in s.keywords) {
      add(k.toLowerCase().replaceAll(' ', '_'), TagType.none);
    }
    item.possibleMediaType.value = null;
    item.mediaType.value = switch (ext) {
      'gif' => MediaType.animation,
      _ when _images.contains(ext) => MediaType.image,
      // Music plays through the video player, which plays audio files.
      _ when _audio.contains(ext) => MediaType.video,
      _ => MediaType.unknown,
    };
  }

  /// FurAffinity's thumbnails say what a submission is (r40): image, GIF,
  /// music, story, Flash.
  @override
  IconData? mediaIconFor(BooruItem item) {
    String type = '';
    for (final Tag t in item.tagsList) {
      if (t.fullString.startsWith('type:')) {
        type = t.fullString.substring(5);
        break;
      }
    }
    switch (type) {
      case 'music':
        return Symbols.music_note_rounded;
      case 'text':
        return Symbols.article_rounded;
      case 'flash':
        return Symbols.extension_rounded;
    }
    if (item.fileExt == 'gif' || item.mediaType.value == MediaType.animation) return CupertinoIcons.play_fill;
    return Symbols.image_rounded;
  }

  @override
  DoujinFilterSpec get doujinFilters => const DoujinFilterSpec([
    DoujinFilterGroup(
      key: 'sort',
      label: 'Sort',
      defaultValue: 'relevancy',
      options: [DoujinFilterOption('relevancy', 'Relevancy'), DoujinFilterOption('date', 'Date'), DoujinFilterOption('popularity', 'Popularity')],
    ),
    DoujinFilterGroup(
      key: 'order',
      label: 'Order',
      defaultValue: 'desc',
      options: [DoujinFilterOption('desc', 'Descending'), DoujinFilterOption('asc', 'Ascending')],
    ),
    DoujinFilterGroup(
      key: 'type',
      label: 'Type',
      multi: true,
      defaultValues: FurAffinityQuery.defaultTypes,
      options: [
        DoujinFilterOption('art', 'Art'),
        DoujinFilterOption('photo', 'Photo'),
        DoujinFilterOption('music', 'Music'),
        DoujinFilterOption('story', 'Story'),
        DoujinFilterOption('poetry', 'Poetry'),
        DoujinFilterOption('flash', 'Flash'),
      ],
    ),
    DoujinFilterGroup(
      key: 'rating',
      label: 'Rating',
      multi: true,
      defaultValues: FurAffinityQuery.defaultRatings,
      options: [DoujinFilterOption('general', 'General'), DoujinFilterOption('mature', 'Mature'), DoujinFilterOption('adult', 'Adult')],
    ),
    DoujinFilterGroup(
      key: 'range',
      label: 'Posted within',
      defaultValue: 'all',
      options: [
        DoujinFilterOption('1day', '24 hours'),
        DoujinFilterOption('3days', '3 days'),
        DoujinFilterOption('7days', '7 days'),
        DoujinFilterOption('30days', '30 days'),
        DoujinFilterOption('90days', '90 days'),
        DoujinFilterOption('1year', '1 year'),
        DoujinFilterOption('3years', '3 years'),
        DoujinFilterOption('5years', '5 years'),
        DoujinFilterOption('all', 'All time'),
      ],
    ),
  ]);

  /// An artist's profile, read once per session.
  static final Map<String, FurAffinityUser?> _users = {};

  Future<FurAffinityUser?> fetchUser(String username) async {
    final String name = username.toLowerCase();
    if (_users.containsKey(name)) return _users[name];
    try {
      final response = await DioNetwork.get('${FurAffinityQuery.site}/user/$name/', headers: getHeaders());
      return _users[name] = FurAffinityParser.user(response.data?.toString() ?? '');
    } catch (e) {
      Logger.Inst().log('reading the profile of $name failed: $e', className, 'fetchUser', LogTypes.booruHandlerInfo);
      return null;
    }
  }
}
