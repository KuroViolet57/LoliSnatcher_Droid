// ignore_for_file: constant_identifier_names

import 'package:lolisnatcher/src/handlers/settings_handler.dart';

enum BooruType {
  Autodetect,
  //
  AGNPH,
  BooruOnRails,
  Civitai,
  Danbooru,
  e621,
  //FurAffinity,
  Gelbooru,
  GelbooruV1,
  Hanime1,
  Hydrus,
  InkBunny,
  Kemono,
  Pawchive,
  Kusowanka,
  Moebooru,
  AsmHentai,
  EaHentai,
  Faccina,
  Hitomi,
  HentaiPaw,
  NHentai,
  NiyaNiya,
  Nozomi,
  NyanPals,
  Philomena,
  Rainbooru,
  Realbooru,
  RedGifs,
  Rule34Dev,
  TikPorn,
  XXXTik,
  XXXFollow,
  R34Hentai,
  R34US,
  Sankaku,
  IdolSankaku,
  Shimmie,
  Szurubooru,
  WebView,
  WildCritters,
  World,

  // [Special types]
  GelbooruAlike,
  Merge,
  Downloads,
  Favourites,
  Collections,
  ForYou,
  History,
  ;

  static List<BooruType> get dropDownValues {
    final settingsHandler = SettingsHandler.instance;
    final isDebug = settingsHandler.isDebug.value;

    return [...values]
      ..remove(BooruType.Downloads)
      ..remove(BooruType.Favourites)
      ..remove(BooruType.Collections)
      ..remove(BooruType.ForYou)
      ..remove(BooruType.History)
      ..remove(BooruType.Merge)
      ..remove(BooruType.GelbooruAlike)
      ..remove(isDebug ? BooruType.NyanPals : null)
      ..remove(isDebug ? BooruType.WildCritters : null);
  }

  bool get isDropDownValue => dropDownValues.contains(this);

  static List<BooruType> get detectable {
    return [...values]
      ..remove(BooruType.Autodetect)
      ..remove(BooruType.Downloads)
      ..remove(BooruType.Favourites)
      ..remove(BooruType.Collections)
      ..remove(BooruType.ForYou)
      ..remove(BooruType.History)
      ..remove(BooruType.Hydrus)
      ..remove(BooruType.Merge)
      // WebView is a "render anything" escape hatch — never autodetect it.
      ..remove(BooruType.WebView)
      // Rule34.dev shares CDNs with rule34.xxx; only pick it deliberately.
      ..remove(BooruType.Rule34Dev)
      // tik.porn, xxxtik and kusowanka all have fixed hosts that ignore
      // the entered URL; only pick them deliberately.
      ..remove(BooruType.TikPorn)
      ..remove(BooruType.Kusowanka)
      ..remove(BooruType.Hanime1)
      // nhentai has a fixed host too; only pick it deliberately.
      ..remove(BooruType.NHentai)
      // niyaniya talks to a fixed API host and ignores the entered URL.
      ..remove(BooruType.NiyaNiya)
      // asmhentai has a fixed host as well.
      ..remove(BooruType.AsmHentai)
      // ...and so does eahentai.
      ..remove(BooruType.EaHentai)
      // faccina is self-hosted: the URL matters, but it is not detectable by
      // probing, so it is only ever picked deliberately.
      ..remove(BooruType.Faccina)
      // hitomi serves everything from its own static hosts and ignores the
      // entered URL, so it would "detect" against any address.
      ..remove(BooruType.Hitomi)
      // hentaipaw has a fixed host; picked deliberately.
      ..remove(BooruType.HentaiPaw)
      // kemono talks to a fixed API host with a non-browser Accept header
      // and answers any address; picked deliberately.
      ..remove(BooruType.Kemono)
      ..remove(BooruType.Pawchive)
      // xxxtik has a fixed API host; only pick it deliberately.
      ..remove(BooruType.XXXTik)
      // xxxfollow has a fixed API host; only pick it deliberately.
      ..remove(BooruType.XXXFollow)
      // civitai has a fixed API host; only pick it deliberately.
      ..remove(BooruType.Civitai)
      // Nozomi and RedGifs hardcode their own hosts and ignore the entered
      // URL entirely, so they "succeed" against ANY address — which made
      // them a silent catch-all: a site that failed every other probe was
      // detected as Nozomi and then quietly served nozomi.la content under
      // the user's site name. Only pick them deliberately.
      ..remove(BooruType.Nozomi)
      ..remove(BooruType.RedGifs);
  }

  bool get isDetectable => detectable.contains(this);

  static List<BooruType> get saveable {
    return [...values]
      ..remove(BooruType.Autodetect)
      ..remove(BooruType.Downloads)
      ..remove(BooruType.Favourites)
      ..remove(BooruType.Collections)
      ..remove(BooruType.ForYou)
      ..remove(BooruType.History)
      ..remove(BooruType.Merge);
  }

  bool get isSaveable => saveable.contains(this);

  String get alias {
    switch (this) {
      case World:
        return 'World/XYZ/Vault';
      case IdolSankaku:
        return 'Sankaku Idol';
      case WebView:
        return 'WebView (browser)';
      case Rule34Dev:
        return 'Rule34.dev (aggregator)';
      case Hanime1:
        return 'Hanime1';
      case Kusowanka:
        return 'Kusowanka';
      case NHentai:
        return 'nhentai';
      case NiyaNiya:
        return 'niyaniya (Schale)';
      case AsmHentai:
        return 'ASMHentai';
      case EaHentai:
        return 'EAHentai';
      case Faccina:
        return 'Faccina (hentalk.pw)';
      case Hitomi:
        return 'hitomi.la';
      case HentaiPaw:
        return 'HentaiPaw';
      case Kemono:
        return 'Kemono';
      case Pawchive:
        return 'Pawchive';
      case TikPorn:
        return 'Tik.Porn';
      case XXXTik:
        return 'xxxtik';
      case XXXFollow:
        return 'xxxfollow';
      case Civitai:
        return 'Civitai';
      default:
        return name;
    }
  }

  bool get isAutodetect => this == BooruType.Autodetect;
  bool get isAGNPH => this == BooruType.AGNPH;
  bool get isBooruOnRails => this == BooruType.BooruOnRails;
  bool get isDanbooru => this == BooruType.Danbooru;
  bool get isE621 => this == BooruType.e621;
  //bool get isFurAffinity => this == BooruType.FurAffinity;
  bool get isGelbooru => this == BooruType.Gelbooru;
  bool get isGelbooruV1 => this == BooruType.GelbooruV1;
  bool get isHydrus => this == BooruType.Hydrus;
  bool get isInkBunny => this == BooruType.InkBunny;
  bool get isMoebooru => this == BooruType.Moebooru;
  bool get isNozomi => this == BooruType.Nozomi;
  bool get isNyanPals => this == BooruType.NyanPals;
  bool get isPhilomena => this == BooruType.Philomena;
  bool get isRainbooru => this == BooruType.Rainbooru;
  bool get isRealbooru => this == BooruType.Realbooru;
  bool get isRedGifs => this == BooruType.RedGifs;
  bool get isRule34Dev => this == BooruType.Rule34Dev;
  bool get isHanime1 => this == BooruType.Hanime1;
  bool get isKusowanka => this == BooruType.Kusowanka;
  bool get isNHentai => this == BooruType.NHentai;
  bool get isNiyaNiya => this == BooruType.NiyaNiya;
  bool get isAsmHentai => this == BooruType.AsmHentai;
  bool get isEaHentai => this == BooruType.EaHentai;
  bool get isFaccina => this == BooruType.Faccina;
  bool get isHitomi => this == BooruType.Hitomi;
  bool get isHentaiPaw => this == BooruType.HentaiPaw;
  /// kemono-style: kemono.cr and its archive pawchive.pw share one handler,
  /// one sidebar and one set of pages.
  bool get isKemono => this == BooruType.Kemono || this == BooruType.Pawchive;

  bool get isPawchive => this == BooruType.Pawchive;
  bool get isTikPorn => this == BooruType.TikPorn;
  bool get isXXXTik => this == BooruType.XXXTik;
  bool get isXXXFollow => this == BooruType.XXXFollow;
  bool get isCivitai => this == BooruType.Civitai;
  bool get isWebView => this == BooruType.WebView;
  bool get isR34Hentai => this == BooruType.R34Hentai;
  bool get isR34US => this == BooruType.R34US;
  bool get isSankaku => this == BooruType.Sankaku;
  bool get isIdolSankaku => this == BooruType.IdolSankaku;
  bool get isShimmie => this == BooruType.Shimmie;
  bool get isSzurubooru => this == BooruType.Szurubooru;
  bool get isWildCritters => this == BooruType.WildCritters;
  bool get isWorld => this == BooruType.World;

  bool get isGelbooruAlike => this == BooruType.GelbooruAlike;
  bool get isMerge => this == BooruType.Merge;
  bool get isDownloads => this == BooruType.Downloads;
  bool get isFavourites => this == BooruType.Favourites;
  bool get isCollections => this == BooruType.Collections;
  bool get isForYou => this == BooruType.ForYou;
  bool get isHistory => this == BooruType.History;
  bool get isFavouritesOrDownloads => isFavourites || isDownloads;

  /// Local, DB-backed virtual boorus (Favourites / Downloads / Collections /
  /// History). These aggregate posts from many sources, so the grid/viewer
  /// must resolve each item's real source booru from its URL rather than the
  /// tab's booru.
  bool get isLocalDb => isFavourites || isDownloads || isCollections || isHistory;
}
