import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/worldxyz_handler.dart';
import 'package:lolisnatcher/src/boorus/sankaku_handler.dart';
import 'package:lolisnatcher/src/boorus/rule34dev_handler.dart';
import 'package:lolisnatcher/src/boorus/hanime1_handler.dart';
import 'package:lolisnatcher/src/boorus/civitai_handler.dart';
import 'package:lolisnatcher/src/boorus/booru_site_filters.dart';
import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/doujin_filters.dart';
import 'package:lolisnatcher/src/boorus/e621_handler.dart';
import 'package:lolisnatcher/src/boorus/furaffinity_handler.dart';
import 'package:lolisnatcher/src/boorus/philomena_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/preview/main_search_query_editor_page.dart';

/// r45: every declared Filters card builds, one key per chip. danbooru's
/// parent:/child: groups have a real `none` value next to the site default,
/// and the default chip was keyed `none` too: the duplicate key crashed the
/// whole card, in the search window and in the source settings.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('filter_chip_keys');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Booru b(String name, BooruType type, String url) => Booru(name, type, '', url, '');

  final Map<String, DoujinFilterSpec Function()> specs = {
    'e621': () => e621Handler(b('e621', BooruType.e621, 'https://e621.net'), 20).doujinFilters,
    'danbooru': () => BooruEngineFilters.danbooru,
    'gelbooru.com': () => BooruEngineFilters.gelbooru(booruOrgRatings: false),
    'rule34.xxx': () => BooruEngineFilters.gelbooru(booruOrgRatings: true, aspectRatio: true),
    'derpibooru': () => PhilomenaHandler(b('derpi', BooruType.Philomena, 'https://derpibooru.org'), 20).doujinFilters,
    'furaffinity': () => FurAffinityHandler(b('FurAffinity', BooruType.FurAffinity, 'https://www.furaffinity.net'), 48).doujinFilters,
    // r46: cards made from the handlers' own choice lists.
    'civitai': () => CivitaiHandler(b('Civitai', BooruType.Civitai, 'https://civitai.com'), 20).siteFilters!,
    'rule34.dev': () => Rule34DevHandler(b('Rule34.dev', BooruType.Rule34Dev, 'https://app.rule34.dev'), 20).siteFilters!,
    'sankaku': () => SankakuHandler(b('Sankaku', BooruType.Sankaku, 'https://chan.sankakucomplex.com'), 20).siteFilters!,
    'r34 world': () => WorldXyzHandler(b('r34', BooruType.World, 'https://rule34.xyz'), 20).siteFilters!,
    'hanime1': () => Hanime1Handler(b('Hanime1', BooruType.Hanime1, 'https://hanime1.me'), 20).siteFilters!,
  };

  for (final MapEntry<String, DoujinFilterSpec Function()> entry in specs.entries) {
    testWidgets('the ${entry.key} Filters card builds, one key per chip', (tester) async {
      final DoujinFilterSpec spec = entry.value();
      for (final DoujinFilterGroup g in spec.groups) {
        final List<String> values = g.options.map((o) => o.value).toList();
        expect(values.toSet(), hasLength(values.length), reason: '${entry.key} ${g.key}: two options with one value');
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DoujinFiltersBlock(spec: spec, query: '', onQueryChanged: (_) {}),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final List<Key?> keys = find.byType(FilterChip).evaluate().map((e) => e.widget.key).toList();
      expect(keys, isNotEmpty);
      expect(keys.toSet(), hasLength(keys.length), reason: 'duplicate chip keys crash the card');
    });
  }
}
