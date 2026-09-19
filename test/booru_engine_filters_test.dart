import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/danbooru_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/doujin_filters.dart';
import 'package:lolisnatcher/src/boorus/gelbooru_alikes_handler.dart';
import 'package:lolisnatcher/src/boorus/gelbooru_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';

/// r45: the Danbooru and Gelbooru engines get the whole of their search help
/// as Filters, in each site's own words — every value checked against the live
/// sites on 2026-09-15 (danbooru; tbib and xbooru for the gelbooru engine).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  Booru b(String name, BooruType type, String url) => Booru(name, type, '', url, '');

  setUp(() {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('booru_engine_filters');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
  });

  tearDown(() {
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  void singleChoicesFromSiteDefault(DoujinFilterSpec spec) {
    for (final DoujinFilterGroup g in spec.groups) {
      expect(g.multi, isFalse, reason: '${g.key}: a repeated metatag does not combine on these engines');
      expect(g.options.first.value, '', reason: '${g.key} starts at the site default');
    }
  }

  test('the danbooru engine (danbooru, AiBooru, AllTheFallen): its cheatsheet as filters', () {
    for (final String url in ['https://danbooru.donmai.us', 'https://aibooru.online', 'https://booru.allthefallen.moe']) {
      final DoujinFilterSpec spec = DanbooruHandler(b('d', BooruType.Danbooru, url), 20).siteFilters!;
      expect(
        spec.groups.map((g) => g.key),
        containsAll(['order', 'rating', 'filetype', 'age', 'score', 'favcount', 'status', 'parent', 'child', 'commentary', 'duration']),
        reason: url,
      );
      singleChoicesFromSiteDefault(spec);
      expect(spec.group('rating')!.options.map((o) => o.value), containsAll(['general', 'sensitive', 'questionable', 'explicit', 'g,s', 'q,e']));
      expect(spec.group('order')!.options.map((o) => o.value), containsAll(['rank', 'score', 'favcount', 'random']));
      expect(spec.group('filetype')!.options.map((o) => o.value), containsAll(['mp4', 'webm', 'gif', 'zip']));
      expect(spec.group('age')!.options.map((o) => o.value), contains('<1w'));
      expect(spec.group('score')!.options.map((o) => o.value), contains('>=100'));
    }
  });

  test('a default saved with the r43 filters (rating:general, order:score) still applies', () {
    final Booru danbooru = b('danbooru', BooruType.Danbooru, 'https://danbooru.donmai.us');
    SourceSettingsHandler.instance.update(danbooru, (s) => s.defaultFilters = 'rating:general order:score');
    expect(DanbooruHandler(danbooru, 20).sourceQuery('cat'), 'cat order:score rating:general');
  });

  test("the gelbooru engine: gelbooru.com's rating words, the booru.org words elsewhere, rule34.xxx's aspect ratio", () {
    final DoujinFilterSpec gel = GelbooruHandler(b('g', BooruType.Gelbooru, 'https://gelbooru.com'), 20).siteFilters!;
    expect(gel.group('rating')!.options.map((o) => o.value), ['', 'general', 'sensitive', 'questionable', 'explicit']);
    expect(gel.group('sort')!.options.map((o) => o.value), containsAll(['score', 'updated', 'random', 'id:asc']));
    expect(gel.group('score')!.options.map((o) => o.value), contains('>=10'));
    expect(gel.group('width')!.options.map((o) => o.value), contains('>=1920'));
    expect(gel.group('aspectratio'), isNull);
    singleChoicesFromSiteDefault(gel);

    final DoujinFilterSpec r34 = GelbooruAlikesHandler(b('r', BooruType.GelbooruAlike, 'https://rule34.xxx'), 20).siteFilters!;
    expect(r34.group('rating')!.options.map((o) => o.value), ['', 'safe', 'questionable', 'explicit']);
    expect(r34.group('aspectratio')!.options.map((o) => o.value), containsAll(['16:9', '9:16']));
    singleChoicesFromSiteDefault(r34);

    final DoujinFilterSpec tbib = GelbooruAlikesHandler(b('t', BooruType.GelbooruAlike, 'https://tbib.org'), 20).siteFilters!;
    expect(tbib.group('aspectratio'), isNull);
    expect(tbib.group('sort'), isNotNull);
  });

  test('a local view on these engines still has no filters', () {
    expect(DanbooruHandler(b('Favourites', BooruType.Favourites, ''), 20).siteFilters, isNull);
  });
}
