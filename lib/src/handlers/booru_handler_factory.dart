import 'package:flutter/foundation.dart';

import 'package:lolisnatcher/src/boorus/agnph_handler.dart';
import 'package:lolisnatcher/src/boorus/booru_on_rails_handler.dart';
import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/collections_handler.dart';
import 'package:lolisnatcher/src/boorus/danbooru_handler.dart';
import 'package:lolisnatcher/src/boorus/downloads_handler.dart';
import 'package:lolisnatcher/src/boorus/e621_handler.dart';
import 'package:lolisnatcher/src/boorus/empty_handler.dart';
import 'package:lolisnatcher/src/boorus/favourites_handler.dart';
import 'package:lolisnatcher/src/boorus/foryou_handler.dart';
import 'package:lolisnatcher/src/boorus/history_handler.dart';
import 'package:lolisnatcher/src/boorus/gelbooru_alikes_handler.dart';
import 'package:lolisnatcher/src/boorus/gelbooru_handler.dart';
import 'package:lolisnatcher/src/boorus/gelbooruv1_handler.dart';
import 'package:lolisnatcher/src/boorus/hydrus_handler.dart';
import 'package:lolisnatcher/src/boorus/idol_sankaku_handler.dart';
import 'package:lolisnatcher/src/boorus/ink_bunny_handler.dart';
import 'package:lolisnatcher/src/boorus/mergebooru_handler.dart';
import 'package:lolisnatcher/src/boorus/moebooru_handler.dart';
import 'package:lolisnatcher/src/boorus/nozomi_handler.dart';
import 'package:lolisnatcher/src/boorus/nyanpals_handler.dart';
import 'package:lolisnatcher/src/boorus/philomena_handler.dart';
import 'package:lolisnatcher/src/boorus/r34hentai_handler.dart';
import 'package:lolisnatcher/src/boorus/r34us_handler.dart';
import 'package:lolisnatcher/src/boorus/rainbooru_handler.dart';
import 'package:lolisnatcher/src/boorus/realbooru_handler.dart';
import 'package:lolisnatcher/src/boorus/redgifs_handler.dart';
import 'package:lolisnatcher/src/boorus/rule34dev_handler.dart';
import 'package:lolisnatcher/src/boorus/sankaku_handler.dart';
import 'package:lolisnatcher/src/boorus/shimmie_handler.dart';
import 'package:lolisnatcher/src/boorus/szurubooru_handler.dart';
import 'package:lolisnatcher/src/boorus/webview_browser_handler.dart';
import 'package:lolisnatcher/src/boorus/wildcritters_handler.dart';
import 'package:lolisnatcher/src/boorus/worldxyz_handler.dart';
import 'package:lolisnatcher/src/boorus/civitai_handler.dart';
import 'package:lolisnatcher/src/boorus/xxxfollow_handler.dart';
import 'package:lolisnatcher/src/boorus/hanime1_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/asmhentai_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/hentaipaw_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/eahentai_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/faccina_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/hitomi_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/schale_handler.dart';
import 'package:lolisnatcher/src/boorus/nhentai_handler.dart';
import 'package:lolisnatcher/src/boorus/kemono_handler.dart';
import 'package:lolisnatcher/src/boorus/kusowanka_handler.dart';
import 'package:lolisnatcher/src/boorus/tikporn_handler.dart';
import 'package:lolisnatcher/src/boorus/xxxtik_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

class BooruHandlerFactory {
  late BooruHandler booruHandler;
  int pageNum = -1;

  /// Media headers per booru, so the image loader can ask a source what its CDN
  /// needs instead of a shared list of hosts having to know about every source.
  static final Map<String, Map<String, String>> _mediaHeaderCache = {};

  /// The headers this booru's own handler says its media host requires.
  ///
  /// Cached because it is consulted once per thumbnail and a grid asks for
  /// dozens at a time; the answer only depends on which source this is.
  static Map<String, String> mediaHeadersFor(Booru booru) {
    final String key = '${booru.type?.name ?? '?'}|${booru.baseURL ?? ''}';
    final Map<String, String>? cached = _mediaHeaderCache[key];
    if (cached != null) return cached;

    Map<String, String> resolved = const {};
    try {
      resolved = BooruHandlerFactory().getBooruHandler([booru], 1).booruHandler.getMediaHeaders();
    } catch (_) {
      // A source that cannot even be constructed here is not one whose images
      // are about to load anyway; an empty map keeps the old behaviour.
    }
    _mediaHeaderCache[key] = resolved;
    return resolved;
  }

  static final Map<String, BooruHandler?> _mediaHandlerCache = {};

  /// One handler per source for the media hooks the viewer consults
  /// (outage notice, error, retry); null when the source cannot be built.
  static BooruHandler? mediaHandlerFor(Booru booru) {
    final String key = '${booru.type?.name ?? '?'}|${booru.baseURL ?? ''}';
    if (_mediaHandlerCache.containsKey(key)) return _mediaHandlerCache[key];
    BooruHandler? handler;
    try {
      handler = BooruHandlerFactory().getBooruHandler([booru], 1).booruHandler;
    } catch (_) {
      handler = null;
    }
    _mediaHandlerCache[key] = handler;
    return handler;
  }

  static String? mediaOutageNoticeFor(Booru booru, String url) => mediaHandlerFor(booru)?.mediaOutageNotice(url);

  static void onMediaErrorFor(Booru booru, String url, Object error) => mediaHandlerFor(booru)?.onMediaError(url, error);

  static Future<void> beforeMediaRetryFor(Booru booru, String url) async => mediaHandlerFor(booru)?.beforeMediaRetry(url);

  @visibleForTesting
  static void clearMediaHeaderCache() {
    _mediaHeaderCache.clear();
    _mediaHandlerCache.clear();
  }

  ({BooruHandler booruHandler, int startingPage}) getBooruHandler(
    List<Booru> boorus,
    int? customLimit,
  ) {
    final int limit = customLimit ?? SettingsHandler.instance.itemLimit;

    if (boorus.length == 1) {
      final Booru booru = boorus.first;

      switch (booru.type) {
        case BooruType.Moebooru:
          pageNum = 0;
          booruHandler = MoebooruHandler(booru, limit);
          break;
        case BooruType.Nozomi:
          pageNum = 0;
          booruHandler = NozomiHandler(booru, limit);
          break;
        case BooruType.Gelbooru:
          // current gelbooru is v.0.2.5, while safe and others are 0.2.0, but since we had them under the same type from the start
          // we should keep them like that, but change sub-handler depending on the link
          // TODO only these sites or there are more?
          const List<String> gelbooruAlikes = ['rule34.xxx', 'safebooru.org', 'furry.booru.org'];

          if (booru.baseURL!.contains('gelbooru.com')) {
            booruHandler = GelbooruHandler(booru, limit);
          } else if (booru.baseURL!.contains('realbooru.com')) {
            // workaround to keep realbooru working with old configs
            booruHandler = RealbooruHandler(booru, limit);
          } else if (gelbooruAlikes.any((element) => booru.baseURL!.contains(element))) {
            booruHandler = GelbooruAlikesHandler(booru, limit);
          } else {
            // fallback to alikes handler since probably no one else has latest version of gelbooru
            booruHandler = GelbooruAlikesHandler(booru, limit);
          }
          break;
        case BooruType.GelbooruAlike:
          // this type is not available in type selector
          booruHandler = GelbooruAlikesHandler(booru, limit);
          break;
        case BooruType.Danbooru:
          pageNum = 0;
          booruHandler = DanbooruHandler(booru, limit);
          break;
        case BooruType.e621:
          pageNum = 0;
          booruHandler = e621Handler(booru, limit);
          break;
        case BooruType.Shimmie:
          pageNum = 0;
          if (booru.baseURL?.contains('paheal.net') ?? false) {
            booruHandler = ShimmieHtmlHandler(booru, limit);
          } else {
            booruHandler = ShimmieHandler(booru, limit);
          }
          break;
        case BooruType.Philomena:
          pageNum = 0;
          booruHandler = PhilomenaHandler(booru, limit);
          break;
        case BooruType.Szurubooru:
          booruHandler = SzurubooruHandler(booru, limit);
          break;
        case BooruType.R34US:
          booruHandler = R34USHandler(booru, limit);
          break;
        case BooruType.Sankaku:
          pageNum = 0;
          booruHandler = SankakuHandler(booru, limit);
          break;
        case BooruType.Hydrus:
          booruHandler = HydrusHandler(booru, limit);
          break;
        case BooruType.GelbooruV1:
          booruHandler = GelbooruV1Handler(booru, limit);
          break;
        case BooruType.BooruOnRails:
          pageNum = 0;
          booruHandler = BooruOnRailsHandler(booru, limit);
          break;
        case BooruType.Downloads:
          booruHandler = DownloadsHandler(booru, limit);
          break;
        case BooruType.Favourites:
          booruHandler = FavouritesHandler(booru, limit);
          break;
        case BooruType.Collections:
          booruHandler = CollectionsHandler(booru, limit);
          break;
        case BooruType.ForYou:
          booruHandler = ForYouHandler(booru, limit);
          break;
        case BooruType.History:
          booruHandler = HistoryHandler(booru, limit);
          break;
        case BooruType.Rainbooru:
          pageNum = 0;
          booruHandler = RainbooruHandler(booru, limit);
          break;
        case BooruType.Realbooru:
          booruHandler = RealbooruHandler(booru, limit);
          break;
        case BooruType.R34Hentai:
          pageNum = 0;
          booruHandler = R34HentaiHandler(booru, limit);
          break;
        case BooruType.World:
          booruHandler = WorldXyzHandler(booru, limit);
          break;
        case BooruType.IdolSankaku:
          pageNum = 0;
          booruHandler = IdolSankakuHandler(booru, limit);
          break;
        case BooruType.InkBunny:
          pageNum = 0;
          booruHandler = InkBunnyHandler(booru, limit);
          break;
        case BooruType.AGNPH:
          pageNum = 0;
          booruHandler = AGNPHHandler(booru, limit);
          break;
        case BooruType.NyanPals:
          pageNum = 0;
          booruHandler = NyanPalsHandler(booru, limit);
          break;
        case BooruType.RedGifs:
          // redgifs pages start at 1
          pageNum = 0;
          booruHandler = RedGifsHandler(booru, limit);
          break;
        case BooruType.Rule34Dev:
          // rule34.dev data route is 0-based; leave pageNum at -1 so the
          // first search increments it to page 0.
          booruHandler = Rule34DevHandler(booru, limit);
          break;
        case BooruType.Hanime1:
          // 1-based ?page=N; default pageNum of -1 makes the first fetch
          // page 1.
          booruHandler = Hanime1Handler(booru, limit);
          break;
        case BooruType.NHentai:
          // 1-based &page=N; default pageNum of -1 makes the first fetch
          // page 1.
          booruHandler = NHentaiHandler(booru, limit);
          break;
        case BooruType.NiyaNiya:
          // 1-based ?page=N, same as the other doujin sources.
          booruHandler = SchaleHandler(booru, limit);
          break;
        case BooruType.AsmHentai:
          // 1-based ?page=N.
          booruHandler = AsmHentaiHandler(booru, limit);
          break;
        case BooruType.EaHentai:
          // 1-based ?page=N.
          booruHandler = EaHentaiHandler(booru, limit);
          break;
        case BooruType.Faccina:
          // 1-based ?page=N on the faccina REST API.
          booruHandler = FaccinaHandler(booru, limit);
          break;
        case BooruType.Hitomi:
          // 1-based pages, resolved against hitomi's packed id indexes.
          booruHandler = HitomiHandler(booru, limit);
          break;
        case BooruType.HentaiPaw:
          // 1-based ?page=N on server-rendered pages.
          booruHandler = HentaiPawHandler(booru, limit);
          break;
        case BooruType.Kemono:
          // Offset paging in steps of 50 (o = page*50): pageNum 0 is the
          // first fetch, so o starts at 0. The API ignores any limit.
          pageNum = 0;
          booruHandler = KemonoHandler(booru, KemonoHandler.pageSize);
          break;
        case BooruType.Kusowanka:
          // 1-based ?page=N; the default pageNum of -1 makes the first
          // fetch page 1.
          booruHandler = KusowankaHandler(booru, limit);
          break;
        case BooruType.TikPorn:
          // limit/offset paging; the default pageNum of -1 makes the first
          // fetch page 0 -> offset 0.
          booruHandler = TikPornHandler(booru, limit);
          break;
        case BooruType.XXXTik:
          // keyset cursor pagination handled inside the handler.
          pageNum = 0;
          booruHandler = XXXTikHandler(booru, limit);
          break;
        case BooruType.XXXFollow:
          // xxxfollow's API is 1-indexed; pre-increment makes the first fetch
          // page 1.
          pageNum = 0;
          booruHandler = XXXFollowHandler(booru, limit);
          break;
        case BooruType.Civitai:
          // cursor pagination handled inside the handler; pageNum only marks
          // first-page resets.
          pageNum = -1;
          booruHandler = CivitaiHandler(booru, limit);
          break;
        case BooruType.WebView:
          booruHandler = WebViewBrowserHandler(booru, limit);
          break;
        case BooruType.WildCritters:
          pageNum = 0;
          booruHandler = WildCrittersHandler(booru, limit);
          break;
        /*   case (BooruType.FurAffinity):
          pageNum = 0;
          booruHandler = FurAffinityHandler(booru, limit);
          break;*/
        default:
          booruHandler = EmptyHandler(Booru.unknown(), limit);
          break;
      }
    } else {
      booruHandler = MergebooruHandler(Booru('Merge', BooruType.Merge, '', '', ''), limit);
      (booruHandler as MergebooruHandler).setupMerge(boorus);
    }

    return (
      booruHandler: booruHandler,
      startingPage: pageNum,
    );
  }
}
