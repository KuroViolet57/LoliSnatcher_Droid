import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/gelbooru_handler.dart';
import 'package:lolisnatcher/src/boorus/nhentai_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/saved_search.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/doujin_migration.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/boorus/mergebooru_handler.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// The round-2 gate: doujin data and booru data are fully separate systems.
/// These tests pin the boundary — the booru blacklist must never filter a
/// doujin feed (even with identical tag names), doujin stores start empty,
/// scoping works, and the one-time migration moves doujin entries out of the
/// shared stores without touching booru rows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  Booru nhentaiBooru() => Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');
  Booru gelbooruBooru() => Booru('gelbooru', BooruType.Gelbooru, '', 'https://gelbooru.com', '');

  BooruItem doujinItem(String id, List<String> tags) => BooruItem(
    fileURL: 'https://i1.nhentai.net/galleries/$id/1.png',
    sampleURL: 'https://i1.nhentai.net/galleries/$id/1.png',
    thumbnailURL: 'https://t1.nhentai.net/galleries/$id/thumb.png',
    tagsList: [for (final t in tags) Tag(t)],
    postURL: 'https://nhentai.net/g/$id/',
    serverId: id,
  );

  BooruItem booruItem(String id, List<String> tags) => BooruItem(
    fileURL: 'https://img.gelbooru.com/images/$id.png',
    sampleURL: 'https://img.gelbooru.com/samples/$id.png',
    thumbnailURL: 'https://img.gelbooru.com/thumbs/$id.png',
    tagsList: [for (final t in tags) Tag(t)],
    postURL: 'https://gelbooru.com/index.php?page=post&id=$id',
    serverId: id,
  );

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    TagHandler.register();
    tempDir = Directory.systemTemp.createTempSync('doujin_separation_test');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
  });

  tearDown(() {
    SettingsHandler.instance.hiddenTags.clear();
    SettingsHandler.instance.hiddenTagsPerBooru.clear();
    SettingsHandler.instance.markedTags.clear();
    SettingsHandler.instance.invalidateBlacklistCache();
    SettingsHandler.instance.filterHated = false;
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('blacklist separation', () {
    test('ACID: booru global blacklist never filters doujin items, even with identical tag names', () {
      final settings = SettingsHandler.instance;
      // The user's real setup: a big booru blacklist with tags that ALSO
      // exist on nhentai.
      settings.hiddenTags.addAll(['netorare', 'ryona', 'guro', 'vore']);
      settings.invalidateBlacklistCache();
      settings.filterHated = true;

      final doujin = NHentaiHandler(nhentaiBooru(), 20);
      doujin.fetched.addAll([
        doujinItem('1001', ['netorare', 'big breasts']),
        doujinItem('1002', ['ryona']),
        doujinItem('1003', ['vanilla']),
      ]);
      doujin.filterFetched();
      // ALL doujin items survive — the booru blacklist has zero effect here.
      expect(doujin.filteredFetched.length, 3);

      // Control: the SAME tags on a booru handler DO get filtered.
      final booru = GelbooruHandler(gelbooruBooru(), 20);
      booru.fetched.addAll([
        booruItem('2001', ['netorare', 'big breasts']),
        booruItem('2002', ['vanilla']),
      ]);
      booru.filterFetched();
      expect(booru.filteredFetched.length, 1);
      expect(booru.filteredFetched.first.serverId, '2002');
    });

    test('booru PER-BOORU blacklist never filters doujin items either', () {
      final settings = SettingsHandler.instance;
      // Direct map write: addTagToBooruHiddenList would also fire an async
      // settings.json save that outlives the test's temp dir.
      settings.hiddenTagsPerBooru.putIfAbsent('nhentai', () => <String>{}).add('netorare');
      settings.invalidateBlacklistCache();
      settings.filterHated = true;

      final doujin = NHentaiHandler(nhentaiBooru(), 20);
      doujin.fetched.add(doujinItem('1001', ['netorare']));
      doujin.filterFetched();
      expect(doujin.filteredFetched.length, 1);
    });

    test('doujin blacklist DOES filter doujin items, and never booru items', () {
      SourceSettingsHandler.instance.updateGlobal((s) => s.tagBlacklist = 'netorare, guro');

      final doujin = NHentaiHandler(nhentaiBooru(), 20);
      doujin.fetched.addAll([
        doujinItem('1001', ['netorare']),
        doujinItem('1002', ['vanilla']),
      ]);
      doujin.filterFetched();
      expect(doujin.filteredFetched.length, 1);
      expect(doujin.filteredFetched.first.serverId, '1002');

      // Booru feeds ignore the doujin blacklist entirely.
      final booru = GelbooruHandler(gelbooruBooru(), 20);
      booru.fetched.add(booruItem('2001', ['netorare']));
      booru.filterFetched();
      expect(booru.filteredFetched.length, 1);
    });

    test('MERGE feeds: attribution is per ITEM — booru blacklist skips doujin items, doujin blacklist skips booru items', () {
      final settings = SettingsHandler.instance;
      settings.hiddenTags.add('netorare');
      settings.invalidateBlacklistCache();
      settings.filterHated = true;
      SourceSettingsHandler.instance.updateGlobal((s) => s.tagBlacklist = 'guro');

      // A non-doujin handler carrying BOTH kinds of items, like a merge tab.
      final mixed = GelbooruHandler(gelbooruBooru(), 20);
      mixed.fetched.addAll([
        doujinItem('1001', ['netorare']), // booru blacklist must NOT hide it
        doujinItem('1002', ['guro']), // doujin blacklist MUST hide it
        booruItem('2001', ['netorare']), // booru blacklist MUST hide it
        booruItem('2002', ['guro']), // doujin blacklist must NOT hide it
      ]);
      mixed.filterFetched();
      expect(mixed.filteredFetched.map((e) => e.serverId).toList(), ['1001', '2002']);
    });

    test('per-source blacklist extend vs override', () {
      final source = SourceSettingsHandler.instance;
      final booru = nhentaiBooru();
      source.updateGlobal((s) => s.tagBlacklist = 'guro');
      source.update(booru, (s) => s.tagBlacklist = 'netorare');

      // extend (default): both lists apply
      expect(source.tagBlacklist(booru).toSet(), {'guro', 'netorare'});

      // override: only the source's own list applies
      source.update(booru, (s) => s.blacklistMode = 'override');
      expect(source.tagBlacklist(booru).toSet(), {'netorare'});
    });
  });

  group('hidden state (blur/crossed-eye path) is domain-scoped', () {
    test('REGRESSION: booru global blacklist must NOT blur doujin items (isHidden stays false)', () {
      final settings = SettingsHandler.instance;
      // The user's real repro: `vore` sits in a 109-tag booru global
      // blacklist and blurred a doujin card in the nhentai feed.
      settings.hiddenTags.add('vore');
      settings.invalidateBlacklistCache();

      final doujin = doujinItem('1001', ['vore', 'big breasts']);
      expect(doujin.isHidden, isFalse);

      // Control: the same tag on a booru item DOES report hidden.
      final booru = booruItem('2001', ['vore']);
      expect(booru.isHidden, isTrue);
    });

    test('doujin blacklist DOES drive isHidden for doujin items, never for booru items', () {
      SourceSettingsHandler.instance.updateGlobal((s) => s.tagBlacklist = 'vore');

      expect(doujinItem('1001', ['vore']).isHidden, isTrue);
      expect(doujinItem('1002', ['vanilla']).isHidden, isFalse);
      // Booru item with the same tag: booru blacklist is empty, so no blur.
      expect(booruItem('2001', ['vore']).isHidden, isFalse);
    });

    test('doujin blacklist matches namespaced/spaced item tags', () {
      SourceSettingsHandler.instance.updateGlobal((s) => s.tagBlacklist = 'big breasts');
      expect(doujinItem('1001', ['tag:Big Breasts']).isHidden, isTrue);
    });

    test('parseTagsListForItem: hidden badges come from the right blacklist per domain', () {
      final settings = SettingsHandler.instance;
      settings.hiddenTags.add('vore');
      settings.invalidateBlacklistCache();
      SourceSettingsHandler.instance.updateGlobal((s) => s.tagBlacklist = 'netorare');

      // Doujin item: booru-blacklisted tag gets NO badge, doujin-blacklisted
      // tag does.
      final doujinData = settings.parseTagsListForItem(doujinItem('1001', ['vore', 'netorare', 'vanilla']));
      expect(doujinData.hiddenTags, ['netorare']);

      // Booru item: exactly the opposite.
      final booruData = settings.parseTagsListForItem(booruItem('2001', ['vore', 'netorare', 'vanilla']));
      expect(booruData.hiddenTags, ['vore']);
    });
  });

  group('favourite/marked tags are domain-scoped both directions', () {
    test('REGRESSION: booru-starred tags must NOT decorate doujin items', () {
      final settings = SettingsHandler.instance;
      // The user's repro: `blowjob` marked on a booru gilded doujin chips.
      settings.markedTags.add('blowjob');

      final doujin = doujinItem('1001', ['blowjob', 'vanilla']);
      expect(doujin.isMarked, isFalse);
      expect(settings.parseTagsListForItem(doujin).markedTags, isEmpty);

      // Control: the same tag on a booru item IS marked.
      final booru = booruItem('2001', ['blowjob']);
      expect(booru.isMarked, isTrue);
      expect(settings.parseTagsListForItem(booru).markedTags, ['blowjob']);
    });

    test('doujin-starred tags decorate doujin items only, never booru items', () {
      DoujinDataHandler.instance.starTag('blowjob');

      final doujin = doujinItem('1001', ['blowjob', 'vanilla']);
      expect(doujin.isMarked, isTrue);
      expect(SettingsHandler.instance.parseTagsListForItem(doujin).markedTags, ['blowjob']);

      final booru = booruItem('2001', ['blowjob']);
      expect(booru.isMarked, isFalse);
      expect(SettingsHandler.instance.parseTagsListForItem(booru).markedTags, isEmpty);
    });

    test('star store normalizes namespaces/spacing/case', () {
      final store = DoujinDataHandler.instance;
      store.starTag('tag:Big Breasts');
      expect(store.starredTags, {'big_breasts'});
      expect(store.isTagStarred('BIG BREASTS'), isTrue);
      expect(store.isTagStarred('artist:big_breasts'), isTrue);
      store.unstarTag('Big_Breasts');
      expect(store.starredTags, isEmpty);
    });

    test('starred tags round-trip through export/import', () {
      final store = DoujinDataHandler.instance;
      store.starTag('netorare');
      store.starTag('vanilla');
      final json = store.exportJson();
      store.resetForTests();
      expect(store.starredTags, isEmpty);
      store.importJson(json);
      expect(store.starredTags, {'netorare', 'vanilla'});
    });

    test('booru marked-tags list and doujin star store never mix', () {
      SettingsHandler.instance.markedTags.add('booru_only');
      DoujinDataHandler.instance.starTag('doujin_only');
      expect(SettingsHandler.instance.markedTags.contains('doujin_only'), isFalse);
      expect(DoujinDataHandler.instance.starredTags.contains('booru_only'), isFalse);
    });
  });

  group('gate round 5: tag types and history stay in their own domain', () {
    test('typeForDisplay never reads the booru tag map on a doujin source', () {
      final tagHandler = TagHandler.instance;
      // A booru has typed `glasses` as a character.
      tagHandler.addTagsWithType(['glasses'], TagType.character);

      // On a booru that classification still applies...
      expect(tagHandler.typeForDisplay('glasses', gelbooruBooru()), TagType.character);
      // ...but a doujin source uses the site's own type, which for a plain
      // nhentai tag is none - never the booru's.
      expect(tagHandler.typeForDisplay('glasses', nhentaiBooru()), TagType.none);
      expect(tagHandler.colourForDisplay('glasses', nhentaiBooru()), isNull);

      // The site's OWN type always wins, on either domain.
      expect(
        tagHandler.typeForDisplay('glasses', nhentaiBooru(), ownType: TagType.artist),
        TagType.artist,
      );
    });

    test('a merge feed does not queue doujin tags into the shared tag store', () async {
      final merge = MergebooruHandler(Booru('Merge', BooruType.Merge, '', '', ''), 20)
        ..booruList = [gelbooruBooru(), nhentaiBooru()];
      // A merge handler is a booru handler, so it DOES populate the store...
      expect(merge.storeTagsGlobally, isTrue);

      final int before = TagHandler.instance.untypedQueue.value.length;
      await merge.populateTagHandler([doujinItem('1001', ['netorare', 'glasses'])]);
      // ...but not for the doujin items it carries: queueing those would send
      // doujin tag names to an unrelated booru's tag API.
      expect(TagHandler.instance.untypedQueue.value.length, before);

      // A booru item in the same feed still goes through.
      await merge.populateTagHandler([booruItem('2001', ['unseen_booru_tag'])]);
      expect(TagHandler.instance.untypedQueue.value.length, greaterThan(before));
      TagHandler.instance.untypedQueue.value = [];
    });
  });

  group('fresh doujin stores are empty', () {
    test('pins for a fresh doujin source are empty even with booru pins around', () {
      // (booru pins live in the DB, which isn't even open here — but the
      // doujin store must be empty regardless of anything booru-side)
      expect(DoujinDataHandler.instance.pinsFor(nhentaiBooru()), isEmpty);
      expect(DoujinDataHandler.instance.favourites, isEmpty);
      expect(DoujinDataHandler.instance.collections, isEmpty);
      expect(DoujinDataHandler.instance.followed, isEmpty);
      expect(DoujinDataHandler.instance.history, isEmpty);
      expect(DoujinDataHandler.instance.savedSearches, isEmpty);
    });
  });

  group('scoped queries', () {
    test('pins: per-source + doujin-global, never cross-source', () {
      final store = DoujinDataHandler.instance;
      final nh = nhentaiBooru();
      final other = Booru('other-doujin', BooruType.NHentai, '', 'https://other.example', '');

      store.addPin('alpha', nh); // scoped to nhentai.net
      store.addPin('beta', nh, global: true); // all doujin sources

      expect(store.pinsFor(nh).map((p) => p.tag).toSet(), {'alpha', 'beta'});
      expect(store.pinsFor(other).map((p) => p.tag).toSet(), {'beta'});
      expect(store.isPinned('alpha', nh), isTrue);
      expect(store.isPinned('alpha', other), isFalse);

      store.removePin('beta', nh);
      expect(store.pinsFor(other), isEmpty);
    });

    test('saved searches: Global view shows all, source chip narrows', () {
      final store = DoujinDataHandler.instance;
      final nh = nhentaiBooru();
      final other = Booru('other-doujin', BooruType.NHentai, '', 'https://other.example', '');

      store.addSavedSearch(name: 'a', query: 'tag:"vanilla"', booru: nh);
      store.addSavedSearch(name: 'b', query: 'artist:"x"', booru: other);

      expect(store.savedSearchesFor(null).length, 2); // Global
      expect(store.savedSearchesFor('nhentai.net').map((s) => s.name), ['a']);
      expect(store.savedSearchesFor('other.example').map((s) => s.name), ['b']);
    });

    test('follows are per-source', () {
      final store = DoujinDataHandler.instance;
      final nh = nhentaiBooru();
      final other = Booru('other-doujin', BooruType.NHentai, '', 'https://other.example', '');
      expect(store.toggleFollow('shindol', nh), isTrue);
      expect(store.isFollowed('shindol', nh), isTrue);
      expect(store.isFollowed('shindol', other), isFalse);
      expect(store.toggleFollow('shindol', nh), isFalse);
      expect(store.followed, isEmpty);
    });
  });

  group('favourites', () {
    test('doujin favourite lands in the doujin store and flips the item flag', () {
      final store = DoujinDataHandler.instance;
      final item = doujinItem('1001', ['vanilla']);
      expect(store.isFavourite(item), isFalse);
      expect(store.toggleFavourite(item, nhentaiBooru()), isTrue);
      expect(store.isFavourite(item), isTrue);
      expect(item.isFavourite.value, isTrue);
      expect(store.favouritesList().single.serverId, '1001');
      expect(store.toggleFavourite(item, nhentaiBooru()), isFalse);
      expect(store.favourites, isEmpty);
    });

    test('toggleFavouriteSynced without an API key: local toggle, no sync attempt', () async {
      final handler = NHentaiHandler(nhentaiBooru(), 20);
      final item = doujinItem('1001', ['vanilla']);
      final result = await DoujinDataHandler.instance.toggleFavouriteSynced(item, handler);
      expect(result.nowFavourite, isTrue);
      expect(result.syncAttempted, isFalse);
      expect(DoujinDataHandler.instance.isFavourite(item), isTrue);
    });
  });

  group('migration', () {
    /// A realistic dataset in DB-row shape: ~10k favourites (120 of them
    /// nhentai), history, per-source + global pins, saved searches, and a
    /// mixed collection.
    DoujinMigrationPlan buildPlan() {
      final favouriteRows = <Map<String, Object?>>[
        for (int i = 0; i < 9754; i++)
          {
            'id': i + 1,
            'postURL': i % 80 == 0
                ? 'https://nhentai.net/g/${100000 + i}/'
                : 'https://gelbooru.com/index.php?page=post&id=$i',
            'thumbnailURL': 'https://thumbs.example/$i.png',
          },
      ];
      final viewedRows = <Map<String, Object?>>[
        for (int i = 0; i < 1806; i++)
          {
            'postKey': i % 10 == 0
                ? 'https://nhentai.net/g/${200000 + i}/'
                : 'https://rule34.xxx/index.php?page=post&id=$i',
            'itemJson': jsonEncode({
              'postURL': i % 10 == 0
                  ? 'https://nhentai.net/g/${200000 + i}/'
                  : 'https://rule34.xxx/index.php?page=post&id=$i',
              'thumbnailURL': 'https://thumbs.example/v$i.png',
              'serverId': i % 10 == 0 ? '${200000 + i}' : '$i',
            }),
            'viewedAt': 1000000 + i,
          },
      ];
      final pinRows = <Map<String, Object?>>[
        {'id': 1, 'tagName': 'vanilla', 'booruType': 'NHentai', 'booruName': 'nhentai', 'label': null},
        {'id': 2, 'tagName': 'landscape', 'booruType': 'Gelbooru', 'booruName': 'gelbooru', 'label': null},
        {'id': 3, 'tagName': 'global_pin', 'booruType': null, 'booruName': null, 'label': null},
      ];
      // Payloads in the REAL TabBackup compact schema ('t'/'b'/'sb') — the
      // exact bytes SavedSearch.payloadJson writes to the DB.
      final savedSearchRows = <Map<String, Object?>>[
        {
          'id': 1,
          'name': 'doujin search',
          'payload': jsonEncode({'t': 'tag:"vanilla"', 'b': 'nhentai'}),
          'createdAt': 1,
        },
        {
          'id': 2,
          'name': 'booru search',
          'payload': jsonEncode({'t': 'landscape', 'b': 'gelbooru'}),
          'createdAt': 2,
        },
        {
          // doujin-primary MERGE search: stays booru-side (secondaries would
          // be lost in the doujin store).
          'id': 3,
          'name': 'merge search',
          'payload': jsonEncode({
            't': 'vanilla',
            'b': 'nhentai',
            'sb': ['gelbooru'],
          }),
          'createdAt': 3,
        },
      ];
      final collectionRows = <Map<String, Object?>>[
        {'id': 1, 'name': 'Best'},
      ];
      final collectionItemRows = <Map<String, Object?>>[
        {'collectionId': 1, 'booruItemID': 501, 'addedAt': 10},
        {'collectionId': 1, 'booruItemID': 502, 'addedAt': 11},
      ];
      final booruItemsById = <int, Map<String, Object?>>{
        501: {'id': 501, 'postURL': 'https://nhentai.net/g/300001/', 'thumbnailURL': ''},
        502: {'id': 502, 'postURL': 'https://gelbooru.com/index.php?page=post&id=502', 'thumbnailURL': ''},
      };

      return planDoujinMigration(
        doujinHosts: {'nhentai.net'},
        doujinBooruNames: {'nhentai': 'nhentai.net'},
        favouriteRows: favouriteRows,
        viewedRows: viewedRows,
        pinRows: pinRows,
        savedSearchRows: savedSearchRows,
        collectionRows: collectionRows,
        collectionItemRows: collectionItemRows,
        booruItemsById: booruItemsById,
      );
    }

    test('plan moves exactly the doujin rows and leaves every booru row alone', () {
      final plan = buildPlan();

      // favourites: ceil(9754/80) nhentai rows
      const int expectedDoujinFavs = 122; // i = 0, 80, ..., 9680 → 122 rows
      expect(plan.favourites.length, expectedDoujinFavs);
      expect(plan.favouriteItemIdsToClear.length, expectedDoujinFavs);
      // no gelbooru row is ever cleared
      expect(
        plan.favourites.every((e) => e.postURL.startsWith('https://nhentai.net/')),
        isTrue,
      );
      // serverId derived from the /g/<id>/ URL
      expect(plan.favourites.first.serverId, '100000');
      expect(plan.favourites.first.booruHost, 'nhentai.net');

      // history: every 10th of 1806 → 181
      expect(plan.history.length, 181);
      expect(plan.historyKeysToDelete.length, 181);
      expect(plan.history.every((e) => e.booruHost == 'nhentai.net'), isTrue);

      // pins: only the nhentai-scoped one; global + gelbooru stay put
      expect(plan.pins, [(tag: 'vanilla', host: 'nhentai.net')]);
      expect(plan.pinIdsToDelete, [1]);

      // saved searches: only the single-source nhentai one — the gelbooru
      // one and the doujin-primary MERGE one both stay booru-side
      expect(plan.savedSearches.single.query, 'tag:"vanilla"');
      expect(plan.savedSearchIdsToDelete, [1]);

      // collections: the nhentai member moves, the gelbooru one stays
      expect(plan.collections['Best']!.single.postURL, 'https://nhentai.net/g/300001/');
      expect(plan.collectionItemsToDelete, [(collectionId: 1, booruItemId: 501)]);
    });

    test('applying the plan fills the store; applying twice is idempotent', () {
      final store = DoujinDataHandler.instance;
      final plan = buildPlan();

      applyPlanToStore(plan, store);
      final int favs = store.favourites.length;
      final int history = store.history.length;
      expect(favs, plan.favourites.length);
      expect(history, plan.history.length);
      expect(store.pins.length, 1);
      expect(store.savedSearches.length, 1);
      expect(store.collections.single.name, 'Best');
      expect(store.collections.single.items.length, 1);

      // Interrupted-migration rerun: nothing duplicates.
      applyPlanToStore(plan, store);
      expect(store.favourites.length, favs);
      expect(store.history.length, history);
      expect(store.pins.length, 1);
      expect(store.savedSearches.length, 1);
      expect(store.collections.single.items.length, 1);
    });

    test('planner parses the EXACT payload SavedSearch.payloadJson writes (schema coupling pin)', () {
      final String payload = SavedSearch(
        id: null,
        name: 'x',
        tags: 'tag:"vanilla"',
        booru: 'nhentai',
        createdAt: DateTime.now(),
      ).payloadJson();
      final plan = planDoujinMigration(
        doujinHosts: {'nhentai.net'},
        doujinBooruNames: {'nhentai': 'nhentai.net'},
        favouriteRows: const [],
        viewedRows: const [],
        pinRows: const [],
        savedSearchRows: [
          {'id': 9, 'name': 'x', 'payload': payload, 'createdAt': 1},
        ],
        collectionRows: const [],
        collectionItemRows: const [],
        booruItemsById: const {},
      );
      expect(plan.savedSearches.single.query, 'tag:"vanilla"');
      expect(plan.savedSearchIdsToDelete, [9]);
    });

    test('history migration respects the cap', () {
      final store = DoujinDataHandler.instance;
      final plan = planDoujinMigration(
        doujinHosts: {'nhentai.net'},
        doujinBooruNames: const {},
        favouriteRows: const [],
        viewedRows: [
          for (int i = 0; i < 1500; i++)
            {
              'postKey': 'https://nhentai.net/g/$i/',
              'itemJson': jsonEncode({'postURL': 'https://nhentai.net/g/$i/', 'serverId': '$i'}),
              // never 0: a zero addedAt is treated as "unknown, use now"
              'viewedAt': 1000 + i,
            },
        ],
        pinRows: const [],
        savedSearchRows: const [],
        collectionRows: const [],
        collectionItemRows: const [],
        booruItemsById: const {},
      );
      applyPlanToStore(plan, store);
      expect(store.history.length, DoujinDataHandler.historyCap);
      // newest first
      expect(store.history.first.serverId, '1499');
    });
  });

  group('backup round-trip', () {
    test('export → wipe → import restores every doujin system', () {
      final store = DoujinDataHandler.instance;
      final nh = nhentaiBooru();
      final item = doujinItem('1001', ['vanilla']);

      store.toggleFavourite(item, nh);
      store.addHistory(item, nh);
      store.addPin('alpha', nh);
      store.addPin('beta', nh, global: true);
      store.addSavedSearch(name: 's', query: 'q', booru: nh);
      store.toggleFollow('shindol', nh);
      final collection = store.createCollection('Best');
      store.addToCollection(collection, item, nh);
      store.migrationDone = true;
      store.save();

      final exported = jsonEncode(store.exportJson());

      // Wipe (fresh install), then restore from the backup payload.
      store.resetForTests();
      expect(store.favourites, isEmpty);
      store.importJson(jsonDecode(exported) as Map<String, dynamic>);

      expect(store.favourites.length, 1);
      expect(store.history.length, 1);
      expect(store.pinsFor(nh).map((p) => p.tag).toSet(), {'alpha', 'beta'});
      expect(store.savedSearchesFor('nhentai.net').single.query, 'q');
      expect(store.isFollowed('shindol', nh), isTrue);
      expect(store.collections.single.name, 'Best');
      expect(store.collections.single.items.single.serverId, '1001');
      expect(store.migrationDone, isTrue);
      expect(store.lastBookmarkCollectionId, store.collections.single.id);
    });

    test('file round-trip: save() then fresh load reads the same data', () {
      final store = DoujinDataHandler.instance;
      final nh = nhentaiBooru();
      store.toggleFavourite(doujinItem('1001', ['vanilla']), nh);
      store.addPin('alpha', nh);
      store.save();

      store.resetForTests();
      store.ensureLoaded();
      expect(store.favourites.length, 1);
      expect(store.pinsFor(nh).single.tag, 'alpha');
    });

    test('sourceSettings blacklist round-trips through its file too', () {
      final source = SourceSettingsHandler.instance;
      final nh = nhentaiBooru();
      source.updateGlobal((s) => s.tagBlacklist = 'guro');
      source.update(nh, (s) {
        s.tagBlacklist = 'netorare';
        s.blacklistMode = 'override';
      });

      source.resetForTests();
      expect(source.tagBlacklist(nh).toSet(), {'netorare'});
      expect(source.blacklistMode(nh), 'override');
    });
  });
}
