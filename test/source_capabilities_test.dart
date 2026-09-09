import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/agnph_handler.dart';
import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/asmhentai_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/eahentai_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/faccina_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/hitomi_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/schale_handler.dart';
import 'package:lolisnatcher/src/boorus/gelbooru_handler.dart';
import 'package:lolisnatcher/src/boorus/hydrus_handler.dart';
import 'package:lolisnatcher/src/boorus/idol_sankaku_handler.dart';
import 'package:lolisnatcher/src/boorus/kemono_handler.dart';
import 'package:lolisnatcher/src/boorus/kusowanka_handler.dart';
import 'package:lolisnatcher/src/boorus/nhentai_handler.dart';
import 'package:lolisnatcher/src/boorus/rule34video_handler.dart';
import 'package:lolisnatcher/src/boorus/tikporn_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/kemono_session_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/ehentai_handler.dart';

/// Settings are offered by CAPABILITY. Each fact below was read off the
/// handler: which credential it sends, whether it has several page sizes,
/// whether its search honours the language filter.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('caps');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Booru b(String name, BooruType type, String url) => Booru(name, type, '', url, '');

  group('doujin sources', () {
    test('niyaniya: no account, no key, five page sizes', () {
      final h = SchaleHandler(b('niyaniya', BooruType.NiyaNiya, 'https://niyaniya.moe'), 20);
      expect(h.usesUserId, isFalse);
      expect(h.usesApiKey, isFalse);
      expect(h.readerImageQualities.map((q) => q.$1), ['780', '980', '1280', '1600', '0']);
      expect(h.supportsLanguageFilter, isFalse);
      // And the API is never sent an Authorization header, key or not.
      final Booru withKey = b('niyaniya', BooruType.NiyaNiya, 'https://niyaniya.moe')..apiKey = 'abc';
      expect(SchaleHandler(withKey, 20).getHeaders().keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
    });

    test('hitomi: nothing to configure', () {
      final h = HitomiHandler(b('hitomi', BooruType.Hitomi, 'https://hitomi.la'), 20);
      expect(h.usesUserId, isFalse);
      expect(h.usesApiKey, isFalse);
      expect(h.readerImageQualities, isEmpty);
    });

    test('nhentai: optional API key only; honours language and title language', () {
      final h = NHentaiHandler(b('nhentai', BooruType.NHentai, 'https://nhentai.net'), 20);
      expect(h.usesUserId, isFalse);
      expect(h.usesApiKey, isTrue);
      expect(h.apiKeyLabel, contains('optional'));
      expect(h.supportsLanguageFilter, isTrue);
      expect(h.supportsTitleLanguage, isTrue);
      expect(h.readerImageQualities, isEmpty);
    });

    test('e-hentai: a WebView session instead of credential fields; two hosts; My Tags as a blacklist', () {
      final h = EHentaiHandler(b('eh', BooruType.EHentai, 'https://e-hentai.org'), 25);
      expect(h.usesUserId, isFalse);
      expect(h.usesApiKey, isFalse);
      expect(h.hasSignInSupport, isFalse);
      expect(h.siteVariants.map((v) => v.$1), ['e-hentai', 'exhentai']);
      expect(h.hasAccountBlacklist, isTrue);
      expect(h.readerImageQualities, isEmpty);
      expect(h.supportsLanguageFilter, isFalse);
      expect(h.getHeaders()['Cookie'], 'nw=1; sl=dm_2', reason: 'anonymous: no session, only the content-warning skip and the display mode');
      expect(h.getMediaHeaders().containsKey('Cookie'), isFalse);
    });

    test("hdoujin: niyaniya's surface on its own network", () {
      final h = SchaleHandler(b('hdoujin', BooruType.HDoujin, 'https://hdoujin.org'), 20);
      expect(h.usesUserId, isFalse);
      expect(h.usesApiKey, isFalse);
      expect(h.readerImageQualities.map((q) => q.$1), ['780', '980', '1280', '1600', '0']);
      expect(h.apiBase, 'https://api.hdoujin.org');
      expect(h.siteVariants, isEmpty);
      expect(h.hasAccountBlacklist, isFalse);
    });

    test('the account-blacklist import is a capability: nhentai and e-hentai only', () {
      expect(NHentaiHandler(b('nhentai', BooruType.NHentai, 'https://nhentai.net'), 20).hasAccountBlacklist, isTrue);
      expect(HitomiHandler(b('hitomi', BooruType.Hitomi, 'https://hitomi.la'), 20).hasAccountBlacklist, isFalse);
    });

    test('asmhentai, eahentai, faccina: username + password logins, one page size', () {
      final List<BooruHandler> logins = [
        AsmHentaiHandler(b('asmhentai', BooruType.AsmHentai, 'https://asmhentai.com'), 20),
        EaHentaiHandler(b('eahentai', BooruType.EaHentai, 'https://eahentai.com'), 20),
        FaccinaHandler(b('faccina', BooruType.Faccina, 'https://hentalk.pw'), 20),
      ];
      for (final h in logins) {
        expect(h.usesUserId, isTrue, reason: h.className);
        expect(h.usesApiKey, isTrue, reason: h.className);
        expect(h.apiKeyLabel, contains('Password'), reason: h.className);
        expect(h.readerImageQualities, isEmpty, reason: h.className);
        expect(h.supportsLanguageFilter, isFalse, reason: h.className);
      }
    });
  });

  group('booru engines', () {
    test('an engine that sends credentials keeps both fields', () {
      final h = GelbooruHandler(b('gelbooru', BooruType.Gelbooru, 'https://gelbooru.com'), 20);
      expect(h.usesUserId, isTrue);
      expect(h.usesApiKey, isTrue);
    });

    test('engines that never read a credential hide both fields', () {
      final List<BooruHandler> none = [
        KusowankaHandler(b('kusowanka', BooruType.Kusowanka, 'https://kusowanka.com'), 20),
        TikPornHandler(b('tikporn', BooruType.TikPorn, 'https://tik.porn'), 20),
        AGNPHHandler(b('agnph', BooruType.AGNPH, 'https://agn.ph'), 20),
        Rule34VideoHandler(b('rule34video', BooruType.Rule34Video, 'https://rule34video.com'), 24),
      ];
      for (final h in none) {
        expect(h.usesUserId, isFalse, reason: h.className);
        expect(h.usesApiKey, isFalse, reason: h.className);
      }
    });

    test('a site-wide content filter is a capability only rule34video declares', () {
      expect(KusowankaHandler(b('kusowanka', BooruType.Kusowanka, 'https://kusowanka.com'), 20).contentTypeOptions, isEmpty);
      expect(GelbooruHandler(b('gelbooru', BooruType.Gelbooru, 'https://gelbooru.com'), 20).contentTypeOptions, isEmpty);
      final r34v = Rule34VideoHandler(b('rule34video', BooruType.Rule34Video, 'https://rule34video.com'), 24);
      expect(r34v.contentTypeOptions.map((v) => v.value), ['straight', 'gay', 'futa', 'music', 'iwara']);
      expect(BooruType.Rule34Video.isDetectable, isFalse, reason: 'one fixed host; would match any URL');
    });

    test('the tag builder lists categories on the booru families, not on idol sankaku or bakemono', () {
      expect(GelbooruHandler(b('gelbooru', BooruType.Gelbooru, 'https://gelbooru.com'), 20).tagCatalog, isNotNull);
      expect(GelbooruHandler(b('bakemono', BooruType.Gelbooru, 'https://bakemono.app'), 20).tagCatalog, isNull);
      expect(IdolSankakuHandler(b('idol', BooruType.IdolSankaku, 'https://idol.sankakucomplex.com'), 20).tagCatalog, isNull);
    });

    test('hydrus is an access key alone', () {
      final h = HydrusHandler(b('hydrus', BooruType.Hydrus, 'http://localhost:45869'), 20);
      expect(h.usesUserId, isFalse);
      expect(h.usesApiKey, isTrue);
      expect(h.apiKeyLabel, 'Access key');
    });

    test('kemono: username + password, no size data, comments, favourites only with a session', () {
      KemonoSessionHandler.instance.resetForTests();
      final h = KemonoHandler(b('kemono', BooruType.Kemono, 'https://kemono.cr'), 50);
      expect(h.usesUserId, isTrue);
      expect(h.usesApiKey, isTrue);
      expect(h.userIdLabel, contains('Username'));
      expect(h.apiKeyLabel, contains('Password'));
      expect(h.hasSizeData, isFalse);
      expect(h.hasCommentsSupport, isTrue);
      expect(h.hasSignInSupport, isTrue);
      expect(h.hasSiteFavourites, isFalse, reason: 'no session yet');
      expect(h.getHeaders()['Accept'], 'text/css');
      expect(h.getHeaders().keys.map((k) => k.toLowerCase()), isNot(contains('cookie')));
      expect(h.tagCatalog.namespaces.map((n) => n.key), containsAll(['tag', 'creator']));
      expect(DoujinDataHandler.isDoujinBooru(b('kemono', BooruType.Kemono, 'https://kemono.cr')), isFalse);
      expect(BooruType.Kemono.isDetectable, isFalse);
      expect(BooruType.Kemono.isSaveable, isTrue);
    });

    test('pawchive: the same handler on the archive; plain JSON, no file referer, no popular', () {
      KemonoSessionHandler.instance.resetForTests();
      final h = KemonoHandler(b('pawchive', BooruType.Pawchive, 'https://pawchive.pw'), 50);
      expect(h.usesUserId, isTrue);
      expect(h.usesApiKey, isTrue);
      expect(h.hasCommentsSupport, isTrue);
      expect(h.hasSignInSupport, isTrue);
      expect(h.getHeaders()['Accept'], 'application/json');
      expect(h.getMediaHeaders(), isEmpty);
      expect(h.availableMetaTags().map((m) => m.name), isNot(contains('Popular')));
      expect(DoujinDataHandler.isDoujinBooru(b('pawchive', BooruType.Pawchive, 'https://pawchive.pw')), isFalse);
      expect(BooruType.Pawchive.isDetectable, isFalse);
      expect(BooruType.Pawchive.isKemono, isTrue);
    });
  });
}
