import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/doujin_filters.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// The parity sweep's inventory (r70): one row per source with what its
/// handler declares, printed so a gap is a fact on screen, not a guess. Not a
/// gate - the gates live in source_capabilities_test.
///
///   flutter test test/source_matrix_report_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('matrix');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
  });
  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  const Map<BooruType, String> sites = {
    BooruType.AGNPH: 'https://agn.ph',
    BooruType.BooruOnRails: 'https://twibooru.org',
    BooruType.Civitai: 'https://civitai.com',
    BooruType.Danbooru: 'https://danbooru.donmai.us',
    BooruType.e621: 'https://e621.net',
    BooruType.FurAffinity: 'https://www.furaffinity.net',
    BooruType.Gelbooru: 'https://gelbooru.com',
    BooruType.GelbooruV1: 'https://gelbooru-v1.invalid',
    BooruType.GelbooruAlike: 'https://rule34.xxx',
    BooruType.Hanime1: 'https://hanime1.me',
    BooruType.Hydrus: 'http://localhost:45869',
    BooruType.InkBunny: 'https://inkbunny.net',
    BooruType.Kemono: 'https://kemono.cr',
    BooruType.Pawchive: 'https://pawchive.org',
    BooruType.Kusowanka: 'https://kusowanka.com',
    BooruType.Moebooru: 'https://yande.re',
    BooruType.AsmHentai: 'https://asmhentai.com',
    BooruType.EaHentai: 'https://eahentai.com',
    BooruType.EHentai: 'https://e-hentai.org',
    BooruType.Faccina: 'https://hentalk.pw',
    BooruType.Hitomi: 'https://hitomi.la',
    BooruType.HDoujin: 'https://hdoujin.org',
    BooruType.HentaiPaw: 'https://hentaipaw.com',
    BooruType.NHentai: 'https://nhentai.net',
    BooruType.NiyaNiya: 'https://niyaniya.moe',
    BooruType.Nozomi: 'https://nozomi.la',
    BooruType.NyanPals: 'https://nyanpals.com',
    BooruType.Philomena: 'https://derpibooru.org',
    BooruType.Rainbooru: 'https://rainbooru.org',
    BooruType.Realbooru: 'https://realbooru.com',
    BooruType.RedGifs: 'https://redgifs.com',
    BooruType.Rule34Dev: 'https://rule34.dev',
    BooruType.Rule34Video: 'https://rule34video.com',
    BooruType.TikPorn: 'https://tik.porn',
    BooruType.XXXTik: 'https://xxxtik.com',
    BooruType.XXXFollow: 'https://xxxfollow.com',
    BooruType.R34Hentai: 'https://rule34hentai.net',
    BooruType.R34US: 'https://rule34.us',
    BooruType.Sankaku: 'https://chan.sankakucomplex.com',
    BooruType.IdolSankaku: 'https://idol.sankakucomplex.com',
    BooruType.Shimmie: 'https://rule34.paheal.net',
    BooruType.Szurubooru: 'https://szurubooru.invalid',
    BooruType.WildCritters: 'https://wildcritters.ws',
    BooruType.World: 'https://world.xyz',
  };

  test('print the capability matrix', () {
    final StringBuffer out = StringBuffer();
    String yn(bool b) => b ? 'Y' : '.';
    out.writeln('type|doujin|reader|loadItem|catalog|suggest|filters|metatags|comments|notes|siteFav|signIn|acctBlacklist|variants|readerQ|langFilter|titleLang|contentTypes|userId|apiKey');
    for (final MapEntry<BooruType, String> e in sites.entries) {
      final Booru booru = Booru(e.key.name, e.key, '', e.value, '');
      BooruHandler h;
      try {
        h = BooruHandlerFactory().getBooruHandler([booru], 20).booruHandler;
      } catch (err) {
        out.writeln('${e.key.name}|ERROR $err');
        continue;
      }
      final DoujinFilterSpec? f = h.siteFilters;
      int metas = 0;
      try {
        metas = h.availableMetaTags().length;
      } catch (_) {}
      out.writeln(
        [
          e.key.name,
          yn(DoujinDataHandler.isDoujinBooru(booru)),
          yn(h.hasReader),
          yn(h.hasLoadItemSupport),
          yn(h.tagCatalog != null),
          yn(h.hasTagSuggestions),
          f == null ? '.' : f.groups.map((g) => g.key).join('+'),
          '$metas',
          yn(h.hasCommentsSupport),
          yn(h.hasNotesSupport),
          yn(h.hasSiteFavourites),
          yn(h.hasSignInSupport),
          yn(h.hasAccountBlacklist),
          '${h.siteVariants.length}',
          '${h.readerImageQualities.length}',
          yn(h.supportsLanguageFilter),
          yn(h.supportsTitleLanguage),
          '${h.contentTypeOptions.length}',
          yn(h.usesUserId),
          yn(h.usesApiKey),
        ].join('|'),
      );
    }
    debugPrint(out.toString());
    File('${tempDir.path}${Platform.pathSeparator}matrix.txt').writeAsStringSync(out.toString());
    expect(sites, isNotEmpty);
  });
}
