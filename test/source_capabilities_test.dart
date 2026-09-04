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
import 'package:lolisnatcher/src/boorus/kemono_handler.dart';
import 'package:lolisnatcher/src/boorus/kusowanka_handler.dart';
import 'package:lolisnatcher/src/boorus/nhentai_handler.dart';
import 'package:lolisnatcher/src/boorus/tikporn_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/kemono_session_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

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
      ];
      for (final h in none) {
        expect(h.usesUserId, isFalse, reason: h.className);
        expect(h.usesApiKey, isFalse, reason: h.className);
      }
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
  });
}
