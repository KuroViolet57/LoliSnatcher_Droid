import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/asmhentai_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/eahentai_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/faccina_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/hitomi_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/schale_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail_card_build.dart';

/// Round 4 fix 3: the new sources' cards looked nothing like nhentai's.
///
/// Most of that turned out to be downstream of the first two fixes — grey boxes
/// were thumbnails failing, the missing language badge was the tag name format.
/// What is asserted here is the part that has to be true independently: every
/// doujin source renders through the SAME card widget and the SAME per-source
/// settings, rather than a source quietly falling back to the plain booru
/// thumbnail.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    SnatchHandler.register();
    tempDir = Directory.systemTemp.createTempSync('card_per_source');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
  });

  tearDown(() {
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Booru booruOf(BooruType type, String url) => Booru(type.name, type, '', url, '');

  /// One handler per source, each with a gallery whose tags came through its
  /// own parser — so this exercises the real tag shape, not a hand-made one.
  Map<String, ({BooruHandler handler, BooruItem item})> sources() {
    final Map<String, ({BooruHandler handler, BooruItem item})> out = {};

    BooruItem itemFor(BooruHandler h, List<dynamic> tags, String post) {
      final item = BooruItem(
        fileURL: 'https://images.invalid/1.png',
        sampleURL: 'https://images.invalid/1.png',
        thumbnailURL: 'https://thumbs.invalid/1.png',
        tagsList: tags.cast(),
        postURL: post,
        serverId: '1',
      )..description = 'A Title';
      h.fetched.add(item);
      return item;
    }

    final hitomi = HitomiHandler(booruOf(BooruType.Hitomi, 'https://hitomi.la'), 20);
    out['hitomi'] = (
      handler: hitomi,
      item: itemFor(
        hitomi,
        hitomi.tagsFromGallery({
          'artists': [
            {'artist': 'remora'},
          ],
          'tags': [
            {'tag': 'bikini', 'female': '1', 'male': ''},
          ],
          'language': 'english',
          'type': 'doujinshi',
        }),
        'https://hitomi.la/galleries/1.html',
      ),
    );

    final schale = SchaleHandler(booruOf(BooruType.NiyaNiya, 'https://niyaniya.moe'), 20);
    out['niyaniya'] = (
      handler: schale,
      item: itemFor(
        schale,
        schale.tagsFromDetail({
          'tags': [
            {'name': 'shindol', 'namespace': 1},
            {'name': 'busty', 'namespace': 9},
            {'name': 'english', 'namespace': 11},
          ],
        }),
        'https://niyaniya.moe/g/1/abc',
      ),
    );

    final faccina = FaccinaHandler(booruOf(BooruType.Faccina, 'https://hentalk.pw'), 20);
    out['hentalk'] = (
      handler: faccina,
      item: itemFor(
        faccina,
        faccina.tagsFromArchive({
          'tags': [
            {'namespace': 'artist', 'name': 'wakahi chan'},
            {'namespace': '', 'name': 'big breasts'},
          ],
        }),
        'https://hentalk.pw/g/1',
      ),
    );

    final ea = EaHentaiHandler(booruOf(BooruType.EaHentai, 'https://eahentai.com'), 20);
    out['eahentai'] = (
      handler: ea,
      item: itemFor(
        ea,
        ea.tagsFromPayload('{"author":"someone","tags":"big breasts|glasses"}'),
        'https://eahentai.com/a/1',
      ),
    );

    final asm = AsmHentaiHandler(booruOf(BooruType.AsmHentai, 'https://asmhentai.com'), 20);
    out['asmhentai'] = (
      handler: asm,
      item: itemFor(
        asm,
        [asm.namespacedTag('sleeping', 'tag'), asm.namespacedTag('english', 'language')],
        'https://asmhentai.com/g/1/',
      ),
    );

    return out;
  }

  Widget host(Widget card) => MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 148, height: 260, child: card)),
    ),
  );

  testWidgets('every source renders through the shared doujin card', (tester) async {
    for (final entry in sources().entries) {
      await tester.pumpWidget(
        host(
          ThumbnailCardBuild(
            index: 0,
            item: entry.value.item,
            handler: entry.value.handler,
            scrollController: AutoScrollController(),
            selectable: false,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // The doujin card is the one that puts tag chips under the cover. A
      // source falling back to the plain booru thumbnail shows none.
      expect(
        find.byType(ThumbnailCardBuild),
        findsOneWidget,
        reason: '${entry.key} did not build a card',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: '${entry.key} threw while building its card',
      );
    }
  });

  testWidgets('chips show bare tag names, never a raw namespace prefix', (tester) async {
    for (final entry in sources().entries) {
      await tester.pumpWidget(
        host(
          ThumbnailCardBuild(
            index: 0,
            item: entry.value.item,
            handler: entry.value.handler,
            scrollController: AutoScrollController(),
            selectable: false,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      for (final tag in entry.value.item.tagsList) {
        expect(
          tag.fullString.contains(':'),
          isFalse,
          reason: '${entry.key} still carries a raw namespace in "${tag.fullString}"',
        );
      }
    }
  });

  testWidgets('the language badge appears wherever the source reports a language', (tester) async {
    // hitomi, niyaniya and asmhentai all carry language data; before fix 2 the
    // badge looked for a tag called `english` and only ever saw
    // `language:english`, so it showed on none of them.
    for (final name in ['hitomi', 'niyaniya', 'asmhentai']) {
      final entry = sources()[name]!;
      await tester.pumpWidget(
        host(
          ThumbnailCardBuild(
            index: 0,
            item: entry.item,
            handler: entry.handler,
            scrollController: AutoScrollController(),
            selectable: false,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('EN'), findsOneWidget, reason: '$name showed no language badge');
    }
  });

  testWidgets('a source with no language data shows no badge rather than an empty one', (tester) async {
    // hentalk and eahentai publish no language namespace at all. The badge has
    // to be absent, not blank.
    for (final name in ['hentalk', 'eahentai']) {
      final entry = sources()[name]!;
      await tester.pumpWidget(
        host(
          ThumbnailCardBuild(
            index: 0,
            item: entry.item,
            handler: entry.handler,
            scrollController: AutoScrollController(),
            selectable: false,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      for (final code in ['EN', 'JP', 'CH', 'KR']) {
        expect(find.text(code), findsNothing, reason: '$name rendered a $code badge from nothing');
      }
    }
  });

  testWidgets('the per-source cover setting is honoured, not hardcoded', (tester) async {
    final entry = sources()['hitomi']!;
    SourceSettingsHandler.instance.update(
      entry.handler.booru,
      (s) => s.coverDisplay = 'crop',
    );

    await tester.pumpWidget(
      host(
        ThumbnailCardBuild(
          index: 0,
          item: entry.item,
          handler: entry.handler,
          scrollController: AutoScrollController(),
          selectable: false,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      SourceSettingsHandler.instance.coverDisplay(entry.handler.booru),
      'crop',
      reason: 'the card read a hardcoded cover mode instead of the source setting',
    );
  });
}
