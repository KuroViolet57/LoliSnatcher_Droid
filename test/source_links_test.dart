import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/site_profiles/bakemono_profile.dart';
import 'package:lolisnatcher/src/data/site_profiles/kemono_profile.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/pages/settings/links_page.dart';
import 'package:lolisnatcher/src/services/source_links.dart';

/// r85: Android cannot add link hosts to an app while it runs, so the sites
/// the app opens are a list built in: the manifest's `.SourceLinks` entry,
/// off until Settings → Links turns it on. Link Sheet offers an app for a
/// link only when its filter names the link's host (PackageIntentHandler,
/// `hasNonWildcardDataAuthority`), so every site is named, with its
/// subdomains.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final String manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  String sourceLinksEntry() {
    final RegExpMatch? m = RegExp(r'<activity-alias[^>]*android:name="\.SourceLinks"[\s\S]*?</activity-alias>').firstMatch(manifest);
    expect(m, isNotNull, reason: 'the manifest has the .SourceLinks entry');
    return m!.group(0)!;
  }

  group('the manifest', () {
    test('the entry is off until switched on, and opens web links', () {
      final String entry = sourceLinksEntry();
      expect(entry, contains('android:targetActivity=".MainActivity"'));
      expect(entry, contains('android:enabled="false"'));
      expect(entry, contains('android:exported="true"'));
      expect(entry, contains('android.intent.action.VIEW'));
      expect(entry, contains('android.intent.category.BROWSABLE'));
      expect(entry, contains('android.intent.category.DEFAULT'));
      expect(entry, contains('android:scheme="https"'));
      expect(entry, contains('android:scheme="http"'));
      expect(entry, isNot(contains('autoVerify')), reason: 'these sites are not ours to verify');
    });

    test('it names exactly the built-in sites, each with its subdomains', () {
      final Set<String> declared = {
        for (final m in RegExp('android:host="([^"]+)"').allMatches(sourceLinksEntry())) m.group(1)!,
      };
      final Set<String> expected = {for (final s in SourceLinks.sites) ...[s, '*.$s']};
      expect(declared, expected);
    });

    test("Flutter's own link handling is off, so app_links alone routes links", () {
      expect(manifest, contains('android:name="flutter_deeplinking_enabled"'));
      expect(RegExp(r'flutter_deeplinking_enabled"\s+android:value="false"').hasMatch(manifest), isTrue);
    });

    test('the app may ask which browser is the default (to hand its own links on)', () {
      final RegExpMatch? q = RegExp(r'<queries>[\s\S]*?</queries>').firstMatch(manifest);
      expect(q, isNotNull);
      expect(q!.group(0), contains('android.intent.action.VIEW'));
      expect(q.group(0), contains('android:scheme="https"'));
    });

    test('the native side switches the entry and hands its own links to the browser', () {
      final String kt = File('android/app/src/main/kotlin/com/noaisu/loliSnatcher/MainActivity.kt').readAsStringSync();
      expect(kt, contains('"setSourceLinks"'));
      expect(kt, contains('.SourceLinks"'));
      expect(kt, contains('override fun onNewIntent'));
      expect(kt, contains('referrer'));
    });
  });

  group('the list of sites', () {
    test('every site the app knows is on it', () {
      final String editPage = File('lib/src/pages/settings/booru_edit_page.dart').readAsStringSync();
      final Set<String> known = {
        for (final m in RegExp(r"booruURLController\.text = 'https?://([a-z0-9][a-z0-9.-]*\.[a-z]+)'").allMatches(editPage)) m.group(1)!,
        ...DoujinDataHandler.knownDoujinHosts,
        ...const BakemonoProfile().hosts,
        ...const KemonoProfile().hosts,
        'danbooru.donmai.us', 'safebooru.donmai.us', 'aibooru.online', 'gelbooru.com', 'rule34.xxx',
        'safebooru.org', 'realbooru.com', 'xbooru.com', 'e621.net', 'e926.net', 'yande.re',
        'konachan.com', 'chan.sankakucomplex.com', 'idol.sankakucomplex.com', 'rule34.paheal.net',
        'rule34.us', 'rule34hentai.net', 'derpibooru.org', 'nozomi.la', 'inkbunny.net',
      };
      final List<String> missing = [for (final h in known) if (!SourceLinks.covers(h)) h];
      expect(missing, isEmpty, reason: 'add these to SourceLinks.sites and the manifest');
    });

    test('a host is covered by its site or a subdomain of it, nothing else', () {
      expect(SourceLinks.covers('e621.net'), isTrue);
      expect(SourceLinks.covers('www.e621.net'), isTrue);
      expect(SourceLinks.covers('WWW.Gelbooru.com'), isTrue);
      expect(SourceLinks.covers('note621.net'), isFalse);
      expect(SourceLinks.covers('e621.net.example.org'), isFalse);
      expect(SourceLinks.covers(''), isFalse);
    });

    test('your sources split into covered and not covered; your own lists are not sources', () {
      Booru b(String name, BooruType type, String url) => Booru(name, type, '', url, '');
      final r = SourceLinks.coverage([
        b('Danbooru', BooruType.Danbooru, 'https://danbooru.donmai.us'),
        b('Blacked booru', BooruType.Gelbooru, 'https://blacked.example.net'),
        b('Downloads', BooruType.Downloads, ''),
        b('Merge', BooruType.Merge, ''),
      ]);
      expect(r.covered.map((b) => b.name), ['Danbooru']);
      expect(r.uncovered.map((b) => b.name), ['Blacked booru']);
    });
  });

  group('the switch', () {
    late Directory tempDir;
    late List<bool> applied;

    setUp(() {
      SettingsHandler.register();
      tempDir = Directory.systemTemp.createTempSync('source_links_test');
      SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
      applied = [];
      SourceLinks.apply = (on) async => applied.add(on);
    });

    tearDown(() {
      SourceLinks.resetForTests();
      SettingsHandler.instance.openSourceLinks = false;
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('it is off by default, and saved and restored with the settings', () {
      final settings = SettingsHandler.instance;
      expect(settings.openSourceLinks, isFalse);
      settings.setByString('openSourceLinks', true);
      expect(settings.openSourceLinks, isTrue);
      expect(settings.getByString('openSourceLinks'), isTrue);
    });

    test('at start the entry follows the saved switch', () async {
      SettingsHandler.instance.openSourceLinks = true;
      await SourceLinks.applySaved();
      SettingsHandler.instance.openSourceLinks = false;
      await SourceLinks.applySaved();
      expect(applied, [true, false]);
    });

    testWidgets('Settings → Links: the switch, and which sources it covers', (tester) async {
      SettingsHandler.instance.booruList
        ..clear()
        ..addAll([
          Booru('Danbooru', BooruType.Danbooru, '', 'https://danbooru.donmai.us', ''),
          Booru('Blacked booru', BooruType.Gelbooru, '', 'https://blacked.example.net', ''),
        ]);
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            // The settings app bar's auto-sized title asserts at the test's
            // default 22 px (as in backup_page_test).
            theme: ThemeData(appBarTheme: const AppBarTheme(titleTextStyle: TextStyle(fontSize: 20))),
            home: const LinksPage(),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Open source links in LoliSnatcher'), findsOneWidget);
      expect(find.textContaining('Danbooru'), findsWidgets);
      expect(find.textContaining('Blacked booru (blacked.example.net)'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(SettingsHandler.instance.openSourceLinks, isTrue);
      expect(applied, [true]);
      SettingsHandler.instance.booruList.clear();
    });
  });
}
