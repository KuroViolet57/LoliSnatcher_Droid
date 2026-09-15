import 'dart:async';

import 'package:flutter/cupertino.dart';

import 'package:dio/dio.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/boorus/linked_media.dart';
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
///
/// r42: the account's blocklist leaves blocked submissions out (the site only
/// blurs them); the submissions inbox pages by its cursor; favourites sync
/// with the site; artists can be watched; folders and watch lists are read.
class FurAffinityHandler extends BooruHandler {
  FurAffinityHandler(super.booru, super.limit);

  static const int pageSize = 48;

  FurAffinitySessionHandler get session => FurAffinitySessionHandler.instance;

  /// 1-based: the search handler increments pageNum before the first fetch.
  int get page => pageNum < 0 ? 1 : pageNum + 1;

  /// Pages reached by a cursor (favorites, the inbox): query -> page -> cursor.
  final Map<String, Map<int, String>> _cursors = {};

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

  static const Set<String> _namespaces = {'artist', 'rating', 'type', 'category', 'theme', 'species', 'folder'};

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
    if (query.kind == FurAffinityRoute.favorites || query.kind == FurAffinityRoute.inbox) {
      cursor = _cursors[tags.trim()]?[page];
    }
    final String url = query.url(page: page, cursor: cursor);
    if (url.isEmpty) locked = true;
    return url;
  }

  /// What a logged-in page says about the account: its name and blocklist.
  void _noteAccount(String body) {
    if (!session.isLoggedIn) return;
    final String? me = FurAffinityParser.loggedInUser(body);
    if (me != null) session.noteUsername(me);
    if (body.contains('data-user-logged-in="1"')) session.noteBlocklist(FurAffinityParser.blocklist(body));
  }

  @override
  FutureOr<List> parseListFromResponse(dynamic response) {
    final String body = response.data?.toString() ?? '';
    final FurAffinityQuery query = FurAffinityQuery.parse(currentTags);
    _noteAccount(body);
    if (query.kind == FurAffinityRoute.view) {
      final BooruItem? item = _single(body, query.id);
      if (item == null) errorString = 'This submission could not be read (it may need you to log in, or be removed).';
      locked = true;
      return item == null ? const [] : [item];
    }
    final List<BooruItem> items = FurAffinityParser.listing(body);
    // A page whose every submission the blocklist took is not the last page.
    final bool hadFigures = body.contains('id="sid-');
    if (items.isEmpty && !hadFigures) {
      locked = true;
      if (query.kind == FurAffinityRoute.inbox && !session.isLoggedIn) {
        errorString = 'The submissions inbox needs you to log in to FurAffinity.';
      } else if (body.contains('System Message')) {
        errorString = 'FurAffinity answered with a system message: the page needs a login, or the account does not exist.';
      }
      return items;
    }
    switch (query.kind) {
      case FurAffinityRoute.gallery || FurAffinityRoute.scraps || FurAffinityRoute.folder:
        if (!FurAffinityParser.galleryHasNext(body)) locked = true;
      case FurAffinityRoute.favorites || FurAffinityRoute.inbox:
        final String? cursor = query.kind == FurAffinityRoute.favorites ? FurAffinityParser.favoritesCursor(body) : FurAffinityParser.inboxCursor(body);
        if (cursor == null) {
          locked = true;
        } else {
          (_cursors[currentTags.trim()] ??= {})[page + 1] = cursor;
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

  /// One of the site's pages, with the account's session.
  Future<String> fetchPage(String url, {CancelToken? cancelToken}) async {
    final response = await DioNetwork.get(url, headers: getHeaders(), cancelToken: cancelToken);
    final String body = response.data?.toString() ?? '';
    _noteAccount(body);
    return body;
  }

  @override
  Future<({BooruItem? item, bool failed, String? error})> loadItem({
    required BooruItem item,
    CancelToken? cancelToken,
    bool withCapcthaCheck = false,
  }) async {
    try {
      final FurAffinitySubmission? s = FurAffinityParser.submission(await fetchPage(item.postURL, cancelToken: cancelToken));
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
    // r52: the description's media links, for the viewer's link button.
    LinkedMediaStore.remember(
      item.postURL,
      LinkedMediaResolver.mediaLinksIn(
        s.descriptionHtml,
        SettingsHandler.instance.booruList,
        base: FurAffinityQuery.site,
        self: item.postURL,
      ),
    );
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

  // ---- the account (r42) ----

  /// Favourites go to the site too while logged in.
  @override
  bool get hasSiteFavourites => session.isLoggedIn;

  @override
  Future<(bool, String)> setSiteFavourite(BooruItem item, bool value) async {
    if (!session.isLoggedIn) return (false, 'Local only: log in to FurAffinity to favourite on the site');
    try {
      final ({String path, bool faved})? link = FurAffinityParser.favLink(await fetchPage(item.postURL));
      if (link == null) return (false, 'FurAffinity offered no favourite button (log in again?)');
      if (link.faved == value) return (true, value ? 'Already in your FurAffinity favorites' : 'Not in your FurAffinity favorites');
      await fetchPage('${FurAffinityQuery.site}${link.path}');
      return (true, value ? 'Added to your FurAffinity favorites' : 'Removed from your FurAffinity favorites');
    } catch (e) {
      return (false, 'FurAffinity favourite failed: $e');
    }
  }

  /// The watch button of an artist's profile, when logged in.
  Future<({String path, bool watching})?> fetchWatchLink(String username) async {
    if (!session.isLoggedIn) return null;
    try {
      return FurAffinityParser.watchLink(await fetchPage('${FurAffinityQuery.site}/user/${username.toLowerCase()}/'));
    } catch (_) {
      return null;
    }
  }

  /// Watches or unwatches an artist; the state after it, and what to say.
  Future<({bool ok, bool watching, String message})> toggleWatch(String username) async {
    final ({String path, bool watching})? link = await fetchWatchLink(username);
    if (link == null) return (ok: false, watching: false, message: 'FurAffinity offered no watch button (log in again?)');
    try {
      await fetchPage('${FurAffinityQuery.site}${link.path}');
      final bool now = !link.watching;
      return (ok: true, watching: now, message: now ? 'Watching $username' : 'No longer watching $username');
    } catch (e) {
      return (ok: false, watching: link.watching, message: 'Watch failed: $e');
    }
  }

  static final Map<String, List<FurAffinityFolder>> _folders = {};

  /// An artist's gallery folders, read once per session.
  Future<List<FurAffinityFolder>> fetchFolders(String username) async {
    final String name = username.toLowerCase();
    final List<FurAffinityFolder>? known = _folders[name];
    if (known != null) return known;
    try {
      return _folders[name] = FurAffinityParser.userFolders(await fetchPage('${FurAffinityQuery.site}/gallery/$name/'));
    } catch (e) {
      Logger.Inst().log('reading the folders of $name failed: $e', className, 'fetchFolders', LogTypes.booruHandlerInfo);
      return const [];
    }
  }

  /// A page of the artists [username] watches.
  Future<({List<FurAffinityWatchEntry> users, bool hasNext})> fetchWatchlist(String username, int page) async {
    final String html = await fetchPage('${FurAffinityQuery.site}/watchlist/by/${username.toLowerCase()}/?page=$page');
    return FurAffinityParser.watchlist(html);
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
    // r42: many "animation" submissions are a still with the animation linked
    // in the description; a GIF file is the only real animation on the site.
    DoujinFilterGroup(
      key: 'animated',
      label: 'Animated',
      defaultValue: 'all',
      options: [DoujinFilterOption('all', 'Everything'), DoujinFilterOption('gif', 'Real animations (GIF files)')],
    ),
    DoujinFilterGroup(
      key: 'rating',
      label: 'Rating',
      multi: true,
      defaultValues: FurAffinityQuery.defaultRatings,
      options: [DoujinFilterOption('general', 'General'), DoujinFilterOption('mature', 'Mature'), DoujinFilterOption('adult', 'Adult')],
    ),
    DoujinFilterGroup(
      key: 'gender',
      label: 'Gender',
      multi: true,
      options: [
        DoujinFilterOption('male', 'Male'),
        DoujinFilterOption('female', 'Female'),
        DoujinFilterOption('trans_male', 'Trans (male)'),
        DoujinFilterOption('trans_female', 'Trans (female)'),
        DoujinFilterOption('intersex', 'Intersex'),
        DoujinFilterOption('non_binary', 'Non-binary'),
      ],
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
    DoujinFilterGroup(
      key: 'mode',
      label: 'Match',
      defaultValue: 'extended',
      options: [DoujinFilterOption('extended', 'Extended'), DoujinFilterOption('all', 'All words'), DoujinFilterOption('any', 'Any word')],
    ),
    DoujinFilterGroup(
      key: 'perpage',
      label: 'Results per page',
      defaultValue: '48',
      options: [DoujinFilterOption('24', '24'), DoujinFilterOption('48', '48'), DoujinFilterOption('72', '72')],
    ),
  ]);

  /// An artist's profile, read once per session.
  static final Map<String, FurAffinityUser?> _users = {};

  Future<FurAffinityUser?> fetchUser(String username) async {
    final String name = username.toLowerCase();
    if (_users.containsKey(name)) return _users[name];
    try {
      return _users[name] = FurAffinityParser.user(await fetchPage('${FurAffinityQuery.site}/user/$name/'));
    } catch (e) {
      // The site answers some profiles with an error page (400) every time: not asked again this session.
      if (e is DioException && (e.response?.statusCode ?? 0) >= 400 && (e.response?.statusCode ?? 0) < 500) _users[name] = null;
      Logger.Inst().log('reading the profile of $name failed: $e', className, 'fetchUser', LogTypes.booruHandlerInfo);
      return null;
    }
  }
}
