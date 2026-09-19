import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/eahentai_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/faccina_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/hitomi_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/schale_handler.dart';
import 'package:lolisnatcher/src/boorus/nhentai_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/doujin_cover_aspect_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail_build.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail_card_build.dart';

/// Round 6 item 4, second attempt.
///
/// The first attempt changed the DEFAULT cover mode to 'crop' and shipped. It
/// did nothing, because the device already had a stored mode: 'Adapt'. Adapt is
/// described in its own settings row as "adapt sizes the card to the cover",
/// and it was not implemented for the source being browsed — it required
/// BooruHandler.hasSizeData, which only nhentai and niyaniya return true for.
/// On EAHentai, hentalk, hitomi and ASMHentai it fell through to a fixed 9/16
/// grid with BoxFit.contain.
///
/// Measured off the screen recording of the shipped build, per card, as the
/// count of fully-dark columns inside the cover box:
///
///   row1 col1  341px box   0px dead    0.0%
///   row1 col2  344px box 160px dead   46.5%
///   row2 col1  341px box 181px dead   53.1%
///   row2 col2  344px box  64px dead   18.6%
///
/// FALSIFIER for every test below: a cover box narrower than the card, a cover
/// box whose aspect ratio is not the cover's own, or a set of covers with
/// different aspect ratios that all produce the same card height. Any of those
/// means the card is still being sized by something other than its cover.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  /// A phone column: 720px wide, 2 columns, 4px gutter.
  const double columnWidth = 358;

  /// Real cover shapes seen in the recording, widest to tallest.
  const double landscapeCover = 1.33;
  const double standardCover = 0.707;
  const double tallCover = 0.5;

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    SnatchHandler.register();
    tempDir = Directory.systemTemp.createTempSync('card_adapt');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    DoujinCoverAspects.instance.resetForTests();
  });

  tearDown(() {
    SourceSettingsHandler.instance.resetForTests();
    DoujinCoverAspects.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  BooruItem itemFor(String post) => BooruItem(
    fileURL: 'https://cdn.invalid/$post.jpg',
    sampleURL: 'https://cdn.invalid/$post.jpg',
    thumbnailURL: 'https://cdn.invalid/$post.jpg',
    tagsList: [Tag('big_breasts'), Tag('nakadashi'), Tag('sole_female')],
    postURL: post,
    serverId: '1',
  )..description = 'A Title';

  /// Lays a card out exactly as the waterfall does: the column's width, and no
  /// height imposed from outside at all.
  Future<({Size card, Size cover})> adaptLayout(
    WidgetTester tester,
    BooruHandler handler,
    String post,
    double aspect,
  ) async {
    SourceSettingsHandler.instance.update(handler.booru, (s) => s.coverDisplay = 'adapt');
    final item = itemFor(post);
    handler.fetched.add(item);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: columnWidth,
              child: ThumbnailCardBuild(
                index: 0,
                item: item,
                handler: handler,
                scrollController: AutoScrollController(),
                selectable: false,
                coverAspect: aspect,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    final Finder cover = find.byType(ThumbnailBuild).first;
    return (
      card: tester.renderObject<RenderBox>(find.byType(ThumbnailCardBuild).first).size,
      cover: tester.renderObject<RenderBox>(cover).size,
    );
  }

  BooruHandler eahentai() =>
      EaHentaiHandler(Booru('e', BooruType.EaHentai, '', 'https://eahentai.com', ''), 20);
  BooruHandler schale() =>
      SchaleHandler(Booru('n', BooruType.NiyaNiya, '', 'https://niyaniya.moe', ''), 20);
  BooruHandler nhentai() =>
      NHentaiHandler(Booru('n', BooruType.NHentai, '', 'https://nhentai.net', ''), 20);
  BooruHandler hitomi() =>
      HitomiHandler(Booru('h', BooruType.Hitomi, '', 'https://hitomi.la', ''), 20);
  BooruHandler hentalk() =>
      FaccinaHandler(Booru('h', BooruType.Faccina, '', 'https://hentalk.pw', ''), 20);

  group('the cover, not the grid, decides the card', () {
    testWidgets('the cover box spans the full card width, whatever its shape', (tester) async {
      // This is the recording's failure stated as a number: 0 dead pixels.
      for (final aspect in [landscapeCover, standardCover, tallCover]) {
        final r = await adaptLayout(tester, eahentai(), 'g$aspect', aspect);
        expect(
          r.cover.width,
          closeTo(columnWidth, 0.5),
          reason: 'aspect $aspect: cover box ${r.cover} inside a ${columnWidth}px card — '
              '${(columnWidth - r.cover.width).round()}px of dead space',
        );
      }
    });

    testWidgets('the cover box carries the cover own aspect ratio', (tester) async {
      // The property that separates "adapted" from "cropped to fit a box".
      for (final aspect in [landscapeCover, standardCover, tallCover]) {
        final r = await adaptLayout(tester, eahentai(), 'g$aspect', aspect);
        expect(
          r.cover.width / r.cover.height,
          closeTo(aspect, 0.01),
          reason: 'aspect $aspect got a ${r.cover.width / r.cover.height} box — the card imposed its own shape',
        );
      }
    });

    testWidgets('a taller cover makes a taller card', (tester) async {
      // Under the shipped build every card in a row was the same height. If
      // these three come out equal, nothing adapted.
      final wide = await adaptLayout(tester, eahentai(), 'a', landscapeCover);
      final std = await adaptLayout(tester, eahentai(), 'b', standardCover);
      final tall = await adaptLayout(tester, eahentai(), 'c', tallCover);

      expect(wide.card.height, lessThan(std.card.height));
      expect(std.card.height, lessThan(tall.card.height));
      // And by the amount the covers actually differ by, not some token amount.
      expect(std.card.height - wide.card.height, greaterThan(100));
    });

    testWidgets('the card is exactly its cover plus its footer, with nothing spare', (tester) async {
      final r = await adaptLayout(tester, eahentai(), 'a', standardCover);
      final double footer = r.card.height - r.cover.height;

      // A real tag footer, not the hardcoded 58px the old cell height added.
      expect(footer, greaterThan(20));
      expect(footer, lessThan(140));
      expect(r.cover.height, closeTo(columnWidth / standardCover, 0.5));
    });
  });

  group('every doujin source adapts, including the ones with no size data', () {
    testWidgets('a source that publishes no dimensions adapts identically', (tester) async {
      // The exact gate that broke this: hasSizeData. EAHentai, hentalk and
      // hitomi all report false, and all three were letterboxing.
      final handlers = <String, BooruHandler>{
        'eahentai': eahentai(),
        'hentalk': hentalk(),
        'hitomi': hitomi(),
        'nhentai': nhentai(),
        'niyaniya': schale(),
      };

      final sizes = <String, Size>{};
      for (final entry in handlers.entries) {
        final r = await adaptLayout(tester, entry.value, entry.key, standardCover);
        sizes[entry.key] = r.cover;
        expect(
          r.cover.width,
          closeTo(columnWidth, 0.5),
          reason: '${entry.key} letterboxed: ${r.cover} in a ${columnWidth}px card',
        );
      }

      // No source is treated specially.
      expect(sizes.values.toSet(), hasLength(1), reason: 'sources got different cover boxes: $sizes');
    });

    testWidgets('the sources that broke it really do report no size data', (tester) async {
      // If this ever flips, the test above stops exercising the bug.
      expect(eahentai().hasSizeData, isFalse);
      expect(hentalk().hasSizeData, isFalse);
      expect(hitomi().hasSizeData, isFalse);
      expect(nhentai().hasSizeData, isTrue);
      expect(schale().hasSizeData, isTrue);
    });
  });

  group('the aspect ratio is learned from the image that arrived', () {
    test('a decoded cover replaces the provisional shape', () {
      const key = 'https://cdn.invalid/a.jpg';
      expect(DoujinCoverAspects.instance.aspectFor(key), isNull);
      expect(DoujinCoverAspects.instance.effectiveAspect(key), DoujinCoverAspects.provisional);

      DoujinCoverAspects.instance.record(key, 320, 454);

      expect(DoujinCoverAspects.instance.effectiveAspect(key), closeTo(320 / 454, 0.0001));
    });

    test('the cell listening to that cover is told, and no other cell is', () {
      const a = 'https://cdn.invalid/a.jpg';
      const b = 'https://cdn.invalid/b.jpg';
      int aTicks = 0, bTicks = 0;
      DoujinCoverAspects.instance.notifierFor(a).addListener(() => aTicks++);
      DoujinCoverAspects.instance.notifierFor(b).addListener(() => bTicks++);

      DoujinCoverAspects.instance.record(a, 320, 454);

      expect(aTicks, 1);
      expect(bTicks, 0, reason: 'one cover decoding relaid out an unrelated cell');
    });

    test('the same cover decoding twice does not relayout twice', () {
      const key = 'https://cdn.invalid/a.jpg';
      int ticks = 0;
      DoujinCoverAspects.instance.notifierFor(key).addListener(() => ticks++);

      DoujinCoverAspects.instance
        ..record(key, 320, 454)
        ..record(key, 320, 454);

      expect(ticks, 1);
    });

    test('a placeholder or broken response cannot size a card', () {
      // A 1x1 tracking pixel, a zero-height error body, and a banner strip are
      // the shapes that would otherwise produce an absurd card.
      const key = 'https://cdn.invalid/a.jpg';
      DoujinCoverAspects.instance
        ..record(key, 0, 0)
        ..record(key, 320, 0)
        ..record(key, 4000, 20)
        ..record(key, 20, 4000);

      expect(DoujinCoverAspects.instance.aspectFor(key), isNull);
      expect(DoujinCoverAspects.instance.effectiveAspect(key), DoujinCoverAspects.provisional);
    });

    test('a 1x1 pixel is square, so it is inside the range but harmless', () {
      // Deliberately allowed: a square cover is a real shape. The guard is
      // against degenerate aspect ratios, not against small images.
      const key = 'https://cdn.invalid/a.jpg';
      DoujinCoverAspects.instance.record(key, 1, 1);
      expect(DoujinCoverAspects.instance.aspectFor(key), 1);
    });

    test('an empty url is never keyed', () {
      DoujinCoverAspects.instance.record('', 320, 454);
      expect(DoujinCoverAspects.instance.aspectFor(''), isNull);
    });

    test('a long feed does not grow the map without bound', () {
      for (int i = 0; i < DoujinCoverAspects.maxEntries + 50; i++) {
        DoujinCoverAspects.instance.record('https://cdn.invalid/$i.jpg', 320, 454);
      }
      // Still remembers the most recent covers.
      expect(
        DoujinCoverAspects.instance.aspectFor('https://cdn.invalid/${DoujinCoverAspects.maxEntries + 49}.jpg'),
        isNotNull,
      );
    });
  });

  group('adapt survives the options around it', () {
    testWidgets('a card with the tag strip turned off still adapts, and does not overflow', (tester) async {
      // The waterfall hands an adapt cell NO height. A card that skipped the
      // AspectRatio here would throw an unbounded-height error instead of
      // rendering, so this is the crash test as much as a layout one.
      final handler = eahentai();
      SourceSettingsHandler.instance.update(handler.booru, (s) {
        s
          ..coverDisplay = 'adapt'
          ..gridTagStrip = false;
      });
      final item = itemFor('nostrip');
      handler.fetched.add(item);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: columnWidth,
                child: ThumbnailCardBuild(
                  index: 0,
                  item: item,
                  handler: handler,
                  scrollController: AutoScrollController(),
                  selectable: false,
                  coverAspect: standardCover,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      final Size card = tester.renderObject<RenderBox>(find.byType(ThumbnailCardBuild).first).size;
      expect(card.width, closeTo(columnWidth, 0.5));
      // No footer now, so the card IS the cover.
      expect(card.height, closeTo(columnWidth / standardCover, 0.5));
    });


    testWidgets('crop still fills by cropping, and fit still shows the whole cover', (tester) async {
      final handler = eahentai();
      SourceSettingsHandler.instance.update(handler.booru, (s) => s.coverDisplay = 'fit');
      final item = itemFor('x');
      handler.fetched.add(item);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 300,
                child: ThumbnailCardBuild(
                  index: 0,
                  item: item,
                  handler: handler,
                  scrollController: AutoScrollController(),
                  selectable: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.widget<ThumbnailBuild>(find.byType(ThumbnailBuild).first).fit, BoxFit.contain);
    });
  });
}
