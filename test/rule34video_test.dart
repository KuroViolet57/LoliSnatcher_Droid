import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/rule34video_handler.dart';
import 'package:lolisnatcher/src/boorus/rule34video_query.dart';
import 'package:lolisnatcher/src/boorus/rule34video_tag_catalog.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_tag_store.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// rule34video.com, against pages captured from the live site on 2026-09-06
/// (test/fixtures/rule34video_*.html: scripts other than the player data,
/// styles and the svg sprite removed; every `v-acctoken` redacted).
String fixture(String name) => File('test/fixtures/rule34video_$name.html').readAsStringSync();

/// What `parseListFromResponse` reads off a Response.
class _Resp {
  _Resp(this.data);
  final String data;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  final Booru booru = Booru('rule34video', BooruType.Rule34Video, '', 'https://rule34video.com', '');
  Rule34VideoHandler handler() => Rule34VideoHandler(booru, Rule34VideoHandler.pageSize);
  Rule34VideoQuery parse(String q, {List<String> groups = const [], Map<String, String> tags = const {}}) =>
      Rule34VideoQuery.parse(q, defaultGroups: groups, knownTagIds: tags);

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('rule34video');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    TagHandler.register();
    Rule34VideoHandler.knownTagIds.clear();
    Rule34VideoHandler.knownUploaderIds.clear();
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('grammar', () {
    test('empty is the newest list; words are a text search with spaces', () {
      final q = parse('');
      expect(q.route, Rule34VideoRoute.latest);
      expect(q.groups, isEmpty);
      expect(q.sort, isNull);
      expect(q.error, isNull);
      final s = parse('  genshin_impact   futa ');
      expect(s.route, Rule34VideoRoute.search);
      expect(s.text, 'genshin impact futa');
      expect(s.source, 'genshin_impact   futa');
    });

    test('type: takes names or ids, repeats union, unknown refuses', () {
      expect(parse('type:gay').groups, ['192']);
      expect(parse('type:gay').route, Rule34VideoRoute.latest);
      expect(parse('type:Gay type:15 type:futa').groups, ['192', '15']);
      expect(parse('type:blorp').error, contains('no content type "blorp"'));
    });

    test('sort: takes app words or KVS keys; relevant sends nothing; unknown refuses', () {
      expect(parse('sort:viewed').sort, 'video_viewed');
      expect(parse('sort:post_date').sort, 'post_date');
      expect(parse('sort:relevant').sort, isNull);
      expect(parse('sort:bogus').error, contains('no sort "bogus"'));
    });

    test('per-source defaults stand in for a missing type: or sort:, and lose to an explicit one', () {
      expect(Rule34VideoQuery.parse('', defaultGroups: ['15']).groups, ['15']);
      expect(Rule34VideoQuery.parse('type:gay', defaultGroups: ['15']).groups, ['192']);
      expect(Rule34VideoQuery.parse('', defaultSort: 'newest').sort, 'post_date');
      expect(Rule34VideoQuery.parse('', defaultSort: 'rating').sort, 'rating');
      expect(Rule34VideoQuery.parse('sort:viewed', defaultSort: 'newest').sort, 'video_viewed');
      expect(Rule34VideoQuery.parse('', defaultSort: 'nonsense').sort, isNull);
    });

    test('tag: needs an id; a known one routes at once', () {
      final unknown = parse('tag:Makima_(Chainsaw_Man)');
      expect(unknown.route, Rule34VideoRoute.tag);
      expect(unknown.name, 'makima_(chainsaw_man)');
      expect(unknown.key, isNull);
      expect(unknown.needsResolution, isTrue);
      final known = parse('tag:makima_(chainsaw_man)', tags: {'makima_(chainsaw_man)': '33605'});
      expect(known.key, '33605');
      expect(known.needsResolution, isFalse);
    });

    test('one bare word the session knows as a tag opens the tag page', () {
      final q = parse('blowjob', tags: {'blowjob': '22'});
      expect(q.route, Rule34VideoRoute.tag);
      expect(q.key, '22');
      expect(parse('blowjob deep', tags: {'blowjob': '22'}).route, Rule34VideoRoute.search);
    });

    test('artist: and category: carry the KVS slug; uploader: a member id or a known name', () {
      final a = parse('artist:NSFW_Sonia_VA_(VA)');
      expect(a.route, Rule34VideoRoute.artist);
      expect(a.name, 'nsfw_sonia_va_(va)');
      expect(a.key, 'nsfw-sonia-va-va');
      final c = parse('category:Chainsaw_Man');
      expect(c.route, Rule34VideoRoute.category);
      expect(c.key, 'chainsaw-man');
      expect(parse('uploader:5352973').key, '5352973');
      final byName = parse('uploader:booty234');
      expect(byName.key, isNull);
      expect(byName.needsResolution, isTrue);
      expect(
        Rule34VideoQuery.parse('uploader:booty234', knownUploaderIds: {'booty234': '5352973'}).key,
        '5352973',
      );
    });

    test('two facets, or a facet with words, are refused rather than answered wrongly', () {
      expect(parse('artist:x category:y').error, Rule34VideoQuery.refusal);
      expect(parse('artist:x words').error, Rule34VideoQuery.refusal);
      expect(parse('tag:a tag:b').error, Rule34VideoQuery.refusal);
      expect(parse('artist:x type:gay sort:newest').error, isNull, reason: 'type/sort are not facets');
    });

    test('the phone filters only a typed text search', () {
      expect(parse('genshin', groups: ['192']).filtersOnPhone, isTrue);
      expect(parse('genshin').filtersOnPhone, isFalse);
      expect(parse('type:gay').filtersOnPhone, isFalse);
      expect(parse('artist:x type:gay').filtersOnPhone, isFalse);
    });

    test('kvsSlug spells the slug the site uses', () {
      expect(Rule34VideoQuery.kvsSlug('2D'), '2d');
      expect(Rule34VideoQuery.kvsSlug('101 dalmatians'), '101-dalmatians');
      expect(Rule34VideoQuery.kvsSlug('NSFW_Sonia_VA (VA)'), 'nsfw-sonia-va-va');
      expect(Rule34VideoQuery.kvsSlug('chainsaw_man'), 'chainsaw-man');
    });
  });

  group('urls', () {
    test('every route, first and later pages, sort and the literal-comma flag1', () {
      final h = handler();
      expect(h.urlFor(parse(''), 1), 'https://rule34video.com/latest-updates/');
      expect(h.urlFor(parse(''), 2), 'https://rule34video.com/latest-updates/2/');
      expect(
        h.urlFor(parse('type:gay type:futa sort:newest'), 1),
        'https://rule34video.com/latest-updates/?sort_by=post_date&flag1=192,15',
      );
      expect(h.urlFor(parse('tag:x', tags: {'x': '22'}), 3), 'https://rule34video.com/tags/22/3/');
      expect(
        h.urlFor(parse('tag:x sort:viewed type:gay', tags: {'x': '22'}), 1),
        'https://rule34video.com/tags/22/?sort_by=video_viewed&flag1=192',
      );
      expect(h.urlFor(parse('artist:Paranoiddroid'), 1), 'https://rule34video.com/models/paranoiddroid/');
      expect(h.urlFor(parse('category:chainsaw_man'), 2), 'https://rule34video.com/categories/chainsaw-man/2/');
      expect(h.urlFor(parse('uploader:5352973'), 1), 'https://rule34video.com/members/5352973/videos/');
    });

    test('text search pages with from_videos and never carries flag1', () {
      final h = handler();
      expect(h.urlFor(parse('genshin_impact'), 1), 'https://rule34video.com/search/genshin%20impact/');
      expect(h.urlFor(parse('genshin_impact'), 2), 'https://rule34video.com/search/genshin%20impact/?from_videos=2');
      final filtered = h.urlFor(parse('genshin sort:viewed', groups: ['192', '15']), 2);
      expect(filtered, 'https://rule34video.com/search/genshin/?sort_by=video_viewed&from_videos=2');
      expect(filtered, isNot(contains('flag1')));
    });

    test('an unresolved tag or uploader searches the name instead of showing everything', () {
      final h = handler();
      expect(h.urlFor(parse('tag:makima_(chainsaw_man)'), 1), 'https://rule34video.com/search/makima%20(chainsaw%20man)/');
      expect(h.urlFor(parse('uploader:booty234'), 1), 'https://rule34video.com/search/booty234/');
    });

    test('makeURL: page from the handler counter, refusal locks with the message', () {
      final h = handler();
      expect(h.makeURL(''), 'https://rule34video.com/latest-updates/');
      h.pageNum = 1;
      expect(h.makeURL(''), 'https://rule34video.com/latest-updates/2/');
      expect(h.makeURL('artist:x category:y'), '');
      expect(h.locked, isTrue);
      expect(h.errorString, Rule34VideoQuery.refusal);
    });

    test('the entered URL is the site, trailing slash or not', () {
      final h = Rule34VideoHandler(Booru('r', BooruType.Rule34Video, '', 'https://rule34video.com/', ''), 24);
      expect(h.site, 'https://rule34video.com');
      expect(Rule34VideoHandler(Booru('r', BooruType.Rule34Video, '', '', ''), 24).site, 'https://rule34video.com');
    });
  });

  group('listing', () {
    test('the newest page: 23 cards, the total, and a card read in full', () {
      final h = handler()..current = parse('');
      final List cards = h.parseListFromResponse(_Resp(fixture('latest')));
      expect(cards, hasLength(23));
      expect(h.totalCount.value, 323195);
      final BooruItem item = h.parseItemFromResponse(cards.first, 0)!;
      expect(item.serverId, '4593515');
      expect(item.postURL, 'https://rule34video.com/video/4593515/release-jinx-in-yordle-heaven/');
      expect(item.thumbnailURL, 'https://rule34video.com/contents/videos_screenshots/4593000/4593515/320x180/1.jpg');
      expect(item.sampleURL, 'https://rule34video.com/contents/videos_screenshots/4593000/4593515/336x189/1.jpg');
      expect(item.fileURL, item.thumbnailURL, reason: 'placeholder until the video page is read');
      expect(item.fileExt, 'jpg', reason: 'the placeholder is honest about its bytes; loadItem sets mp4');
      expect(item.mediaType.value, MediaType.needToLoadItem);
      expect(item.possibleMediaType.value, MediaType.video);
      expect(item.tagsList.map((t) => t.fullString), containsAll(['type:futa', 'hd']));
      expect(item.description, '[Release] Jinx in Yordle Heaven\n4:25 · 200 views · 17 minutes ago');
      expect(item.score, '100% (2)');
      for (final c in cards) {
        expect(h.parseItemFromResponse(c, 0), isNotNull);
      }
    });

    test('badges: Futa where the site says so, everything else indistinguishable', () {
      final List<dom.Element> cards = Rule34VideoHandler.cardsOf(html.parse(fixture('latest')));
      final futa = cards.where((c) => Rule34VideoHandler.groupsOfCard(c).contains('15'));
      expect(futa, hasLength(3));
      final plain = cards.where((c) => Rule34VideoHandler.groupsOfCard(c) == Rule34VideoHandler.unbadgedGroups);
      expect(plain, hasLength(20));
      final gay = Rule34VideoHandler.cardsOf(html.parse(fixture('latest_gay')));
      expect(gay, hasLength(23));
      expect(gay.every((c) => Rule34VideoHandler.groupsOfCard(c).contains('192')), isTrue);
    });

    test('cardPasses: a combo badge counts for both, an unbadged card for the other three', () {
      final combo = html.parse('<div class="item thumb" data-video-card-id="1"><div class="futa">Gay &amp; Futa</div></div>')
          .querySelector('div.item')!;
      expect(Rule34VideoHandler.groupsOfCard(combo), {'192', '15'});
      expect(Rule34VideoHandler.cardPasses(combo, ['15']), isTrue);
      expect(Rule34VideoHandler.cardPasses(combo, ['2109']), isFalse);
      final plain = html.parse('<div class="item thumb" data-video-card-id="2"></div>').querySelector('div.item')!;
      expect(Rule34VideoHandler.cardPasses(plain, ['2109']), isTrue);
      expect(Rule34VideoHandler.cardPasses(plain, ['4747']), isTrue);
      expect(Rule34VideoHandler.cardPasses(plain, ['192']), isFalse);
      expect(Rule34VideoHandler.cardPasses(plain, const []), isTrue);
    });

    test('a typed text search is filtered on the phone and its total is questionable', () {
      final h = handler()..current = parse('genshin', groups: ['15']);
      expect(h.current.filtersOnPhone, isTrue);
      final List cards = h.parseListFromResponse(_Resp(fixture('search_genshin')));
      expect(cards, hasLength(1));
      expect(h.countIsQuestionable, isTrue);
      expect(h.totalCount.value, 16211);
      final all = handler()..current = parse('genshin');
      expect(all.parseListFromResponse(_Resp(fixture('search_genshin'))), hasLength(24));
      expect(all.countIsQuestionable, isFalse);
    });

    test('pagination: a next page is a from: link past the current page', () {
      expect(Rule34VideoHandler.hasNextPage(html.parse(fixture('search_genshin')), 1), isTrue);
      expect(Rule34VideoHandler.hasNextPage(html.parse(fixture('search')), 1), isFalse, reason: '16 results, one page');
      expect(Rule34VideoHandler.hasNextPage(html.parse(fixture('latest')), 14052), isFalse);
      expect(Rule34VideoHandler.cardsOf(html.parse(fixture('search'))), hasLength(16));
      expect(Rule34VideoHandler.cardsOf(html.parse(fixture('tag'))), hasLength(23));
    });

    test('a DDoS-Guard page names itself instead of an empty grid', () {
      final h = handler()..current = parse('');
      final List cards = h.parseListFromResponse(
        _Resp('<html><head><title>DDoS-Guard</title></head><body><script src="/.well-known/ddos-guard/check"></script></body></html>'),
      );
      expect(cards, isEmpty);
      expect(h.errorString, contains('DDoS-Guard'));
    });

    test("the home page's group toggles still carry the ids the grammar hardcodes", () {
      final doc = html.parse(fixture('home'));
      final Map<String, String> seen = {
        for (final e in doc.querySelectorAll('.js-tags'))
          if ((e.attributes['data-tags'] ?? '').isNotEmpty)
            (e.attributes['data-name'] ?? '').toLowerCase(): e.attributes['data-tags']!,
      };
      expect(seen, Rule34VideoQuery.groupIds);
    });
  });

  group('video page', () {
    test('flashvars: the object is read, the best file is the 720p one', () {
      final vars = Rule34VideoHandler.flashvarsOf(fixture('video'));
      expect(vars.keys, containsAll(['video_url', 'video_alt_url', 'video_alt_url2', 'preview_url', 'video_title']));
      expect(vars['video_alt_url2_text'], '720p');
      final best = Rule34VideoHandler.bestVideoOf(vars)!;
      expect(best.label, '720p');
      expect(best.url, contains('_720p.mp4'));
      expect(best.url, contains('v-acctoken=REDACTED'));
      expect(best.url, startsWith('https://rule34video.com/get_file/'));
    });

    test('bestVideoOf judges by the label, not the key order; flashvarsOf unescapes', () {
      final best = Rule34VideoHandler.bestVideoOf({
        'video_url': 'a',
        'video_url_text': '360p',
        'video_alt_url': 'b',
        'video_alt_url_text': '1080p',
        'video_alt_url2': 'c',
        'video_alt_url2_text': '720p',
      })!;
      expect(best.url, 'b');
      expect(Rule34VideoHandler.bestVideoOf({'preview_url': 'x'}), isNull);
      final vars = Rule34VideoHandler.flashvarsOf(r"var flashvars = { video_title: 'it\'s', video_url: 'https:\/\/h\/f.mp4' };");
      expect(vars['video_title'], "it's");
      expect(vars['video_url'], 'https://h/f.mp4');
      expect(Rule34VideoHandler.flashvarsOf('<html></html>'), isEmpty);
    });

    test('applyVideoPage: file, preview, typed tags, uploader, info line, session ids', () async {
      final h = handler();
      final item = BooruItem(
        fileURL: 'thumb.jpg',
        sampleURL: 'thumb.jpg',
        thumbnailURL: 'thumb.jpg',
        tagsList: [Tag('type:futa', tagType: TagType.meta), Tag('hd', tagType: TagType.meta)],
        postURL: 'https://rule34video.com/video/4592499/makima-trained-power/',
      );
      final String? error = await h.applyVideoPage(item, fixture('video'), remember: false);
      expect(error, isNull);
      expect(item.fileURL, contains('_720p.mp4'));
      expect(item.fileExt, 'mp4');
      expect(item.mediaType.value, MediaType.video);
      expect(item.possibleMediaType.value, isNull);
      expect(item.sampleURL, 'https://rule34video.com/contents/videos_screenshots/4592000/4592499/preview.jpg');
      expect(item.isUpdated, isTrue);
      final Map<String, TagType> tags = {for (final t in item.tagsList) t.fullString: t.tagType};
      expect(tags['makima_(chainsaw_man)'], TagType.none);
      expect(tags['category:chainsaw_man'], TagType.copyright);
      expect(tags['category:2d'], TagType.copyright);
      expect(tags['artist:paranoiddroid'], TagType.artist);
      expect(tags['artist:nsfw_sonia_va_(va)'], TagType.artist);
      expect(tags['uploader:booty234'], TagType.meta);
      expect(tags['type:futa'], TagType.meta, reason: 'what the card said survives');
      expect(tags['hd'], TagType.meta);
      expect(item.uploaderId, '5352973');
      expect(item.uploaderName, 'booty234');
      expect(item.description, 'Makima trained Power\n1 hour ago · 619 views · 0:44');
      expect(item.score, '100% (5)');
      expect(Rule34VideoHandler.knownTagIds['makima_(chainsaw_man)'], '33605');
      expect(Rule34VideoHandler.knownUploaderIds['booty234'], '5352973');
      expect(h.tagNamespace('artist:paranoiddroid'), 'artist');
      expect(h.tagNamespace('hd'), 'type');
      expect(h.tagNamespace('makima_(chainsaw_man)'), 'tag');
    });

    test('no player data is an error, a DDoS-Guard page is named', () async {
      final h = handler();
      BooruItem item() => BooruItem(fileURL: 't', sampleURL: 't', thumbnailURL: 't', tagsList: const [], postURL: 'p');
      expect(await h.applyVideoPage(item(), '<html><body>gone</body></html>', remember: false), contains('no player data'));
      expect(await h.applyVideoPage(item(), '<html>ddos-guard</html>', remember: false), contains('DDoS-Guard'));
    });
  });

  group('tag builder catalog', () {
    test('three namespaces, bare tags and prefixed artists/categories, exact block URLs', () {
      final catalog = handler().tagCatalog! as Rule34VideoTagCatalog;
      expect(catalog.namespaces.map((n) => n.key), ['tag', 'artist', 'category']);
      expect(catalog.namespaces.map((n) => n.type), [TagType.none, TagType.artist, TagType.copyright]);
      expect(catalog.searchTerm(const BooruTagEntry(name: 'blowjob', tagType: TagType.none, namespace: 'tag')), 'blowjob');
      expect(
        catalog.searchTerm(const BooruTagEntry(name: 'paranoiddroid', tagType: TagType.artist, namespace: 'artist')),
        'artist:paranoiddroid',
      );
      const site = 'https://rule34video.com';
      expect(
        Rule34VideoTagCatalog.blockUrl(site, 'tag', 0),
        '$site/tags/?mode=async&function=get_block&block_id=list_tags_tags_list&sort_by=tag&from=1',
      );
      expect(
        Rule34VideoTagCatalog.blockUrl(site, 'artist', 4),
        '$site/models/?mode=async&function=get_block&block_id=list_models_models_list&sort_by=model_viewed&from=5',
      );
      expect(
        Rule34VideoTagCatalog.blockUrl(site, 'category', 0),
        '$site/categories/?mode=async&function=get_block&block_id=list_categories_categories_list&sort_by=total_videos&from=1',
      );
      expect(Rule34VideoTagCatalog.blockUrl(site, 'nope', 0), isNull);
    });

    test('a tags fragment: 120 rows with ids and counts', () {
      final rows = Rule34VideoTagCatalog.parseTags(fixture('tags_fragment'));
      // 120 anchors; alisa_bosconovitch_(tekken) is listed twice (ids 269 and
      // 39239, a case variant) and the snapshot is name-keyed, so one row.
      expect(rows, hasLength(119));
      expect(rows.first.name, 'aiba_manami_(my_hero_academia)');
      expect(rows.first.sourceId, '54399');
      expect(rows.first.count, 9);
      expect(rows.every((e) => e.namespace == 'tag' && e.tagType == TagType.none && e.sourceId != null), isTrue);
      expect(rows.every((e) => !e.name.contains(' ')), isTrue);
    });

    test('an artists fragment: 48 rows keyed by slug, no counts', () {
      final rows = Rule34VideoTagCatalog.parseModels(fixture('models_fragment'));
      expect(rows, hasLength(48));
      expect(rows.first.name, 'amplected');
      expect(rows.first.sourceId, 'amplected');
      expect(rows.every((e) => e.namespace == 'artist' && e.tagType == TagType.artist && e.count == 0), isTrue);
    });

    test('a categories fragment: 36 rows keyed by slug', () {
      final rows = Rule34VideoTagCatalog.parseCategories(fixture('categories_fragment'));
      expect(rows, hasLength(36));
      expect(rows.every((e) => e.namespace == 'category' && e.tagType == TagType.copyright), isTrue);
      expect(rows.every((e) => (e.sourceId ?? '').isNotEmpty && !e.name.contains(' ')), isTrue);
    });

    test('the last fragment is read off the pagination', () {
      expect(Rule34VideoTagCatalog.lastShardOf(fixture('tags_index')), 74);
      expect(Rule34VideoTagCatalog.lastShardOf(fixture('models_index')), 299);
      expect(Rule34VideoTagCatalog.lastShardOf(fixture('categories_index')), 68);
      expect(Rule34VideoTagCatalog.lastShardOf(fixture('tags_fragment')), isNotNull);
      expect(Rule34VideoTagCatalog.lastShardOf('<div class="list"></div>'), isNull);
    });
  });

  group('capabilities', () {
    test('no credentials, no size data, no animated filter, open media, local suggestions', () {
      final h = handler();
      expect(h.usesUserId, isFalse);
      expect(h.usesApiKey, isFalse);
      expect(h.hasSizeData, isFalse);
      expect(h.animatedPreviewFilters, isEmpty);
      expect(h.getMediaHeaders(), isEmpty);
      expect(h.hasTagSuggestions, isTrue);
      expect(h.hasLoadItemSupport, isTrue);
      expect(h.shouldUpdateIteminTagView, isTrue);
      expect(h.hasNativeOrSupport, isFalse);
      expect(h.tagCatalog, isNotNull);
      expect(h.getHeaders()['Referer'], 'https://rule34video.com/');
      expect(h.getHeaders()['User-Agent'], isNotEmpty);
      expect(BooruType.Rule34Video.isRule34Video, isTrue);
      expect(BooruType.Rule34Video.alias, 'Rule34Video');
    });

    test('the content filter is a capability: five options, and a metatag with the same values', () {
      final h = handler();
      expect(h.contentTypeOptions.map((v) => v.value), ['straight', 'gay', 'futa', 'music', 'iwara']);
      final metaTags = h.availableMetaTags();
      expect(metaTags.whereType<SortMetaTag>(), hasLength(1));
      expect(metaTags.whereType<SortMetaTag>().single.values.map((v) => v.value), Rule34VideoQuery.sorts.keys);
      final type = metaTags.whereType<MetaTagWithValues>().firstWhere((m) => m.keyName == 'type');
      expect(type.values.map((v) => v.value), h.contentTypeOptions.map((v) => v.value));
      expect(metaTags.whereType<StringMetaTag>().map((m) => m.keyName), containsAll(['tag', 'artist', 'category', 'uploader']));
      expect(h.tagNamespaceSections.map((s) => s.$1), ['artist', 'category', 'uploader', 'type', 'tag']);
    });

    test("suggestions without a snapshot: the type values and this session's ids", () async {
      final h = handler();
      Rule34VideoHandler.knownTagIds['futanari'] = '15';
      final result = await h.getTagSuggestions('fu');
      final tags = result.getOrElse((_) => []).map((s) => s.tag).toList();
      expect(tags, containsAll(['type:futa', 'futanari']));
      expect((await h.getTagSuggestions('')).getOrElse((_) => []), isEmpty);
    });
  });

  group('against a database', () {
    late bool dbReady;

    setUp(() async {
      dbReady = false;
      try {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        final db = SettingsHandler.instance.dbHandler;
        db.db = await databaseFactory.openDatabase(inMemoryDatabasePath);
        await db.updateTable();
        await db.createCriticalIndexes();
        SettingsHandler.instance.dbEnabled = true;
        dbReady = true;
      } catch (e) {
        // ignore: avoid_print
        print('sqlite unavailable on this test host: $e');
      }
    });

    tearDown(() async {
      try {
        await SettingsHandler.instance.dbHandler.db?.close();
      } catch (_) {}
      SettingsHandler.instance.dbHandler.db = null;
    });

    test('a snapshot row routes a bare name or tag: to /tags/{id}/; an unknown one searches', () async {
      if (!dbReady) return;
      await BooruTagStore.record(booru, const [
        BooruTagEntry(name: 'blowjob', tagType: TagType.none, count: 45223, namespace: 'tag', sourceId: '22'),
        BooruTagEntry(name: 'paranoiddroid', tagType: TagType.artist, namespace: 'artist', sourceId: 'paranoiddroid'),
      ]);
      final h = handler();
      final bare = await h.resolveQuery('blowjob');
      expect(bare.route, Rule34VideoRoute.tag);
      expect(bare.key, '22');
      expect(h.urlFor(bare, 1), 'https://rule34video.com/tags/22/');
      final typed = await h.resolveQuery('tag:blowjob type:futa');
      expect(h.urlFor(typed, 2), 'https://rule34video.com/tags/22/2/?flag1=15');
      final unknown = await h.resolveQuery('tag:nothing_here');
      expect(unknown.route, Rule34VideoRoute.search);
      expect(unknown.text, 'nothing here');
      final artist = await h.resolveQuery('artist:paranoiddroid');
      expect(artist.key, 'paranoiddroid');
      expect(Rule34VideoHandler.knownTagIds['blowjob'], '22', reason: 'the session remembers what the store said');
    });

    test('suggestions come from the snapshot, with the prefix the search wants', () async {
      if (!dbReady) return;
      await BooruTagStore.record(booru, const [
        BooruTagEntry(name: 'blowjob', tagType: TagType.none, count: 45223, namespace: 'tag', sourceId: '22'),
        BooruTagEntry(name: 'paranoiddroid', tagType: TagType.artist, namespace: 'artist', sourceId: 'paranoiddroid'),
        BooruTagEntry(name: 'chainsaw_man', tagType: TagType.copyright, namespace: 'category', sourceId: 'chainsaw-man'),
      ]);
      final h = handler();
      expect((await h.getTagSuggestions('para')).getOrElse((_) => []).map((s) => s.tag), contains('artist:paranoiddroid'));
      expect((await h.getTagSuggestions('blow')).getOrElse((_) => []).map((s) => s.tag), contains('blowjob'));
      expect((await h.getTagSuggestions('chain')).getOrElse((_) => []).map((s) => s.tag), contains('category:chainsaw_man'));
    });

    test('a video page stores the names the snapshot lacks and leaves the ones it has alone', () async {
      if (!dbReady) return;
      await BooruTagStore.record(booru, const [
        BooruTagEntry(name: 'makima_(chainsaw_man)', tagType: TagType.none, count: 500, namespace: 'tag', sourceId: '33605'),
      ]);
      final h = handler();
      final item = BooruItem(fileURL: 't', sampleURL: 't', thumbnailURL: 't', tagsList: const [], postURL: 'p');
      expect(await h.applyVideoPage(item, fixture('video')), isNull);
      expect(await BooruTagStore.findId(booru, 'tag', 'makima_(chainsaw_man)'), '33605');
      final kept = await BooruTagStore.lookup(booru, ['makima_(chainsaw_man)']);
      expect(kept['makima_(chainsaw_man)']?.count, 500, reason: 'an index row is not clobbered');
      expect(await BooruTagStore.findId(booru, 'artist', 'paranoiddroid'), 'paranoiddroid');
      expect(await BooruTagStore.findId(booru, 'category', 'chainsaw_man'), 'chainsaw-man');
      final resolved = await handler().resolveQuery('artist:paranoiddroid');
      expect(handler().urlFor(resolved, 1), 'https://rule34video.com/models/paranoiddroid/');
    });

    test('a multi-word snapshot tag routes to its tag page too, not only a one-word one (r28 review)', () async {
      if (!dbReady) return;
      await BooruTagStore.record(booru, const [
        BooruTagEntry(name: 'makima_(chainsaw_man)', tagType: TagType.none, count: 500, namespace: 'tag', sourceId: '33605'),
      ]);
      final h = handler();
      final q = await h.resolveQuery('makima_(chainsaw_man)');
      expect(q.route, Rule34VideoRoute.tag);
      expect(q.key, '33605');
      expect(h.urlFor(q, 1), 'https://rule34video.com/tags/33605/');
      final typed = await h.resolveQuery('makima_(chainsaw_man) type:futa');
      expect(typed.route, Rule34VideoRoute.tag);
      expect(h.urlFor(typed, 1), 'https://rule34video.com/tags/33605/?flag1=15');
      final two = await h.resolveQuery('makima_(chainsaw_man) power');
      expect(two.route, Rule34VideoRoute.search, reason: 'two words are a text search');
    });
  });

  group('r28 review fixes', () {
    tearDown(SourceSettingsHandler.instance.resetForTests);

    test('an empty search honours the per-source content-type and sort defaults', () async {
      SourceSettingsHandler.instance.update(booru, (s) {
        s.contentTypes = 'gay';
        s.defaultSort = 'newest';
      });
      final h = handler();
      expect(h.makeURL(''), 'https://rule34video.com/latest-updates/?sort_by=post_date&flag1=192');
      final q = await h.resolveQuery('');
      expect(q.groups, ['192']);
      expect(q.sort, 'post_date');
      expect(h.urlFor(q, 2), 'https://rule34video.com/latest-updates/2/?sort_by=post_date&flag1=192');
      expect(h.makeURL('type:futa'), 'https://rule34video.com/latest-updates/?sort_by=post_date&flag1=15');
    });

    test('a changed default applies to the next list, never to the one on screen (review)', () {
      SourceSettingsHandler.instance.update(booru, (s) => s.contentTypes = 'gay');
      final h = handler();
      expect(h.makeURL(''), 'https://rule34video.com/latest-updates/?flag1=192');
      h.fetched.add(BooruItem(fileURL: 't', sampleURL: 't', thumbnailURL: 't', tagsList: const [], postURL: 'p'));
      SourceSettingsHandler.instance.update(booru, (s) => s.contentTypes = 'futa');
      h.pageNum = 1;
      expect(h.makeURL(''), 'https://rule34video.com/latest-updates/2/?flag1=192', reason: 'page 2 of the list on screen keeps its filter');
      h.fetched.clear();
      h.pageNum = -1;
      expect(h.makeURL(''), 'https://rule34video.com/latest-updates/?flag1=15', reason: 'a fresh list picks up the new default');
    });

    test('a facet with no value is refused, not answered with everything', () {
      expect(parse('artist:').error, isNotNull);
      expect(parse('tag:').error, isNotNull);
      expect(parse('category: chainsaw').error, isNotNull, reason: 'a space after the colon leaves the facet empty');
      expect(parse('uploader:').error, isNotNull);
    });

    test('the grammar keeps the bare words so a single underscored tag can be looked up', () {
      expect(parse('makima_(chainsaw_man) type:gay').words, ['makima_(chainsaw_man)']);
      expect(parse('makima_(chainsaw_man) power').words, ['makima_(chainsaw_man)', 'power']);
      expect(parse('type:gay').words, isEmpty);
    });

    test('an unopened card does not claim an extension its bytes do not have', () {
      final h = handler()..current = parse('');
      final List cards = h.parseListFromResponse(_Resp(fixture('latest')));
      final BooruItem item = h.parseItemFromResponse(cards.first, 0)!;
      expect(item.fileExt, 'jpg', reason: 'the placeholder is the thumbnail; a download before opening saves what it is');
      expect(item.mediaType.value, MediaType.needToLoadItem);
      expect(item.possibleMediaType.value, MediaType.video);
    });

    test('the info line labels the middle value as views only when it is a number', () {
      expect(Rule34VideoHandler.infoLine(['1 hour ago', '619', '0:44']), '1 hour ago · 619 views · 0:44');
      expect(Rule34VideoHandler.infoLine(['1 hour ago', '2.1K', '0:44']), '1 hour ago · 2.1K views · 0:44');
      // The live site writes the exact count after the rounded one.
      expect(Rule34VideoHandler.infoLine(['1 hour ago', '2.5K (2,511)', '2:59']), '1 hour ago · 2.5K (2,511) views · 2:59');
      expect(Rule34VideoHandler.infoLine(['1 hour ago', 'Uploaded by x', '2:59']), '1 hour ago · Uploaded by x · 2:59');
      expect(Rule34VideoHandler.infoLine(['1 hour ago', '0:44']), '1 hour ago · 0:44');
      expect(Rule34VideoHandler.infoLine([]), '');
    });

    String page({required bool futa, required bool next, String id = '1'}) =>
        '<html><body><div id="custom_list_videos_x_items"><div class="item thumb" data-video-card-id="$id"> '
        '<a class="th" href="https://rule34video.com/video/$id/a/"><img class="thumb" data-original="https://x/$id.jpg"/> '
        '${futa ? '<div class="futa">Futa</div>' : ''}</a></div></div> '
        // The pagination names a far last page, so hops are limited by the budget, not by the site.
        '${next ? '<a data-parameters="from:99"></a>' : ''}</body></html>';
    Response<dynamic> resp(String body) => Response(requestOptions: RequestOptions(path: '/'), statusCode: 200, data: body);

    test('the phone-side walk keeps paging when it ran out of hops with pages left, and stops at the end', () async {
      final h = handler()..current = parse('genshin', groups: ['15']);
      final List<Uri> asked = [];
      Future<Response<dynamic>> fetchEmpty(Uri uri) async {
        asked.add(uri);
        return resp(page(futa: false, next: true, id: '${asked.length + 1}'));
      }

      final Response<dynamic> last = await h.walkFiltered(resp(page(futa: false, next: true)), fetchEmpty);
      expect(asked, hasLength(Rule34VideoHandler.maxFilterHops));
      expect(asked.first.toString(), 'https://rule34video.com/search/genshin/?from_videos=2');
      expect(
        Rule34VideoHandler.cardsOf(html.parse(last.data as String)).where((c) => Rule34VideoHandler.cardPasses(c, ['15'])),
        isEmpty,
      );
      expect(h.moreAfterWalk, isTrue, reason: 'the site had more pages; the grid must not be told it is the end');
      expect(h.pageNum, Rule34VideoHandler.maxFilterHops, reason: 'the next grid fetch asks the page after the last one walked');
      expect(asked.last.toString(), 'https://rule34video.com/search/genshin/?from_videos=${Rule34VideoHandler.maxFilterHops + 1}');
      h.locked = true;
      h.unlockAfterWalk();
      expect(h.locked, isFalse);

      // A page with a passing card ends the walk and leaves the lock alone.
      final h2 = handler()..current = parse('genshin', groups: ['15']);
      int calls = 0;
      final Response<dynamic> hit = await h2.walkFiltered(resp(page(futa: false, next: true)), (uri) async {
        calls++;
        return resp(page(futa: true, next: true, id: '9'));
      });
      expect(calls, 1);
      expect(hit.data, contains('data-video-card-id="9"'));
      expect(h2.moreAfterWalk, isFalse);
      h2.locked = true;
      h2.unlockAfterWalk();
      expect(h2.locked, isTrue);

      // No next page: stop, and let the base lock.
      final h3 = handler()..current = parse('genshin', groups: ['15']);
      final Response<dynamic> end = await h3.walkFiltered(
        resp(page(futa: false, next: false)),
        (uri) async => throw StateError('must not fetch'),
      );
      expect(end.data, contains('data-video-card-id="1"'));
      expect(h3.moreAfterWalk, isFalse);
    });

    test('a search whose walk finds nothing keeps looking a few rounds, then says so instead of "no results" (review)', () async {
      final List<String> asked = [];
      Future<Response<dynamic>> serve(Uri uri) async {
        asked.add(uri.toString());
        final int p = int.tryParse(uri.queryParameters['from_videos'] ?? '1') ?? 1;
        return resp(page(futa: p == 40, next: true, id: '$p'));
      }

      final h = handler()..listingFetch = serve;
      final List<BooruItem> got = List<BooruItem>.from(await h.search('genshin type:futa', null));
      expect(got, isEmpty);
      expect(asked.toSet().length, asked.length, reason: 'no page fetched twice');
      expect(asked.length, (Rule34VideoHandler.maxFilterHops + 1) * (Rule34VideoHandler.maxEmptyRounds + 1));
      expect(h.locked, isFalse, reason: 'the site has more; Retry must be possible');
      expect(h.errorString, contains('first ${asked.length} pages'));
      expect(h.errorString, contains('futa'));

      // From further down the list the walk reaches the matching page and says nothing.
      final h2 = handler()..listingFetch = serve;
      h2.pageNum = 33;
      final List<BooruItem> found = List<BooruItem>.from(await h2.search('genshin type:futa', null));
      expect(found.map((i) => i.serverId), ['40']);
      expect(h2.errorString, isEmpty);
      expect(h2.locked, isFalse);
    });

    test('the catalog: an empty fragment is an empty shard, a challenge page is an error, 404 is the end', () async {
      final _FakeFetch h = _FakeFetch(booru);
      final catalog = h.tagCatalog! as Rule34VideoTagCatalog;
      h.answers[Rule34VideoTagCatalog.blockUrl(h.site, 'tag', 0)!] = (status: 200, body: fixture('tags_fragment'));
      h.answers[Rule34VideoTagCatalog.blockUrl(h.site, 'tag', 1)!] =
          (status: 200, body: '<div class="list_items" id="list_tags_tags_list_items"></div>');
      h.answers[Rule34VideoTagCatalog.blockUrl(h.site, 'tag', 2)!] =
          (status: 200, body: '<html><script src="/.well-known/ddos-guard/check.js"></script></html>');
      h.answers[Rule34VideoTagCatalog.blockUrl(h.site, 'artist', 0)!] = (status: 404, body: '');
      expect(await catalog.shardAt('tag', 0), hasLength(119));
      expect(await catalog.shardAt('tag', 1), isEmpty, reason: 'a real, empty shard keeps the walk resumable');
      await expectLater(catalog.shardAt('tag', 2), throwsA(isA<Exception>()));
      expect(await catalog.shardAt('artist', 0), isNull);
      final int before = h.fetches;
      expect(await catalog.shardAt('tag', 74), isNull, reason: 'past the last fragment the first page reported');
      expect(h.fetches, before, reason: 'no request past the end');

      // No rows AND no pagination before any page was seen: the markup changed,
      // which must not be walked to the pull cap as forty empty requests.
      final _FakeFetch fresh = _FakeFetch(booru);
      fresh.answers[Rule34VideoTagCatalog.blockUrl(fresh.site, 'category', 0)!] =
          (status: 200, body: '<div class="list_items" id="x_items"></div>');
      await expectLater((fresh.tagCatalog! as Rule34VideoTagCatalog).shardAt('category', 0), throwsA(isA<Exception>()));
    });
  });
}

/// A handler whose page fetches are answered from a map.
class _FakeFetch extends Rule34VideoHandler {
  _FakeFetch(Booru booru) : super(booru, Rule34VideoHandler.pageSize);
  final Map<String, ({int status, String body})> answers = {};
  int fetches = 0;

  @override
  Future<({int status, String body})> fetchPage(String url, {CancelToken? cancelToken}) async {
    fetches++;
    return answers[url] ?? (status: 500, body: '');
  }
}
