import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_site_filters.dart';
import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/civitai_handler.dart';
import 'package:lolisnatcher/src/boorus/danbooru_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/doujin_filters.dart';
import 'package:lolisnatcher/src/boorus/hanime1_handler.dart';
import 'package:lolisnatcher/src/boorus/philomena_handler.dart';
import 'package:lolisnatcher/src/boorus/rule34dev_handler.dart';
import 'package:lolisnatcher/src/boorus/sankaku_handler.dart';
import 'package:lolisnatcher/src/boorus/worldxyz_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

/// r46: the long tail. Every fixed choice list a handler already declares (the
/// site's own words, parsed by that handler) becomes a filter, not only sort,
/// order and rating; Derpibooru gains its range fields, checked live on
/// 2026-09-15 (score.gte, faves.gte, width.gte, animated, duration.gte, joined
/// by commas).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  Booru b(String name, BooruType type, String url) => Booru(name, type, '', url, '');
  List<String> values(DoujinFilterSpec spec, String key) => spec.group(key)!.options.map((o) => o.value).toList();

  setUp(() {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('booru_long_tail');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test("Civitai: sort, period, NSFW level, media type and base model", () {
    final DoujinFilterSpec spec = CivitaiHandler(b('Civitai', BooruType.Civitai, 'https://civitai.com'), 20).siteFilters!;
    expect(spec.groups.map((g) => g.key), containsAll(['sort', 'period', 'nsfw', 'type', 'basemodel']));
    expect(values(spec, 'nsfw'), containsAll(['', 'none', 'soft', 'mature', 'x', 'xxx', 'all']));
    expect(values(spec, 'type'), ['', 'image', 'video']);
    expect(values(spec, 'sort'), containsAll(['newest', 'oldest', 'reactions', 'random']));
  });

  test('Rule34.dev: the site it searches', () {
    final DoujinFilterSpec spec = Rule34DevHandler(b('Rule34.dev', BooruType.Rule34Dev, 'https://app.rule34.dev'), 20).siteFilters!;
    expect(values(spec, 'source'), ['', 'r34', 'gel', 'e621', 'r34paheal']);
  });

  test("r34 World's sort; Sankaku's order, rating and parent, with its real none", () {
    final DoujinFilterSpec world = WorldXyzHandler(b('r34', BooruType.World, 'https://rule34.xyz'), 20).siteFilters!;
    expect(values(world, 'sort'), containsAll(['date', 'oldest', 'likes', 'views', 'random']));
    final DoujinFilterSpec sankaku = SankakuHandler(b('Sankaku', BooruType.Sankaku, 'https://chan.sankakucomplex.com'), 20).siteFilters!;
    expect(sankaku.groups.map((g) => g.key), containsAll(['order', 'rating', 'parent']));
    expect(values(sankaku, 'parent'), ['', 'any', 'none']);
  });

  test("Hanime1: its genres", () {
    final DoujinFilterSpec spec = Hanime1Handler(b('Hanime1', BooruType.Hanime1, 'https://hanime1.me'), 20).siteFilters!;
    expect(spec.group('genre')!.options.length, greaterThan(2));
  });

  test('a list keeps every value; sort and order still drop ascending twins and technical orders', () {
    final DoujinFilterSpec spec = BooruSiteFilters.fromMetaTags(
      DanbooruHandler(b('d', BooruType.Danbooru, 'https://danbooru.donmai.us'), 20).availableMetaTags(),
    )!;
    expect(values(spec, 'status'), containsAll(['any', 'pending', 'deleted', 'active']));
    expect(values(spec, 'parent'), containsAll(['any', 'none']));
    expect(values(spec, 'order'), isNot(contains('score_asc')));
    expect(values(spec, 'order'), isNot(contains('md5')));
    for (final DoujinFilterGroup g in spec.groups) {
      final List<String> v = g.options.map((o) => o.value).toList();
      expect(v.toSet(), hasLength(v.length), reason: '${g.key}: one option per value');
    }
  });

  test('Derpibooru: score, favorites, width, animated and length go inside q, joined by commas', () {
    final PhilomenaHandler h = PhilomenaHandler(b('DerpiBooru', BooruType.Philomena, 'https://derpibooru.org'), 20)..pageNum = 1;
    final DoujinFilterSpec spec = h.siteFilters!;
    expect(spec.groups.map((g) => g.key), containsAll(['filter', 'sf', 'sd', 'score.gte', 'faves.gte', 'width.gte', 'animated', 'duration.gte']));
    expect(values(spec, 'animated'), ['', 'true', 'false']);
    final Uri u = Uri.parse(h.makeURL('pony score.gte:100 animated:true sf:score'));
    expect(u.queryParameters['q'], 'pony,score.gte:100,animated:true');
    expect(u.queryParameters['sf'], 'score');
  });
}
