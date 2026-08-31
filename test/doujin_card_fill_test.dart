import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/faccina_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/hitomi_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/schale_handler.dart';
import 'package:lolisnatcher/src/boorus/nhentai_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail_build.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail_card_build.dart';

/// Round 6 item 4.
///
/// Last round I said feed thumbnails would fill their card once images loaded.
/// I never rendered one, and it was false. This measures, off a real layout
/// pass, the box the card gives the cover and how large a real source cover is
/// painted inside it.
///
/// The measurement that found it: the cover box is 200x226 (aspect 0.885) while
/// niyaniya's covers are 320x454 (aspect 0.705). Under the old default the
/// image painted 159x226 — 41px, a fifth of the card's width, left empty. The
/// box was never source-specific, which was my other wrong guess; the default
/// cover mode was simply "show the whole cover" rather than "fill the card".
///
/// Falsifier for each test: a painted size materially smaller than its box
/// means the cover is not filling the card.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  /// What niyaniya actually serves, and the shape that exposed this.
  const Size sourceCover = Size(320, 454);

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    SnatchHandler.register();
    tempDir = Directory.systemTemp.createTempSync('card_fill');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
  });

  tearDown(() {
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  BooruItem itemFor(String post) => BooruItem(
    fileURL: 'https://cdn.invalid/a.jpg',
    sampleURL: 'https://cdn.invalid/a.jpg',
    thumbnailURL: 'https://cdn.invalid/a.jpg',
    tagsList: [Tag('big_breasts'), Tag('nakadashi'), Tag('sole_female')],
    postURL: post,
    serverId: '1',
  )..description = 'A Title';

  /// Lays a card out and reports the cover box, the fit it asked for, and how
  /// large a real source cover would be painted inside it.
  Future<({Size box, BoxFit fit, Size painted})> layout(
    WidgetTester tester,
    BooruHandler handler,
    String post,
  ) async {
    final item = itemFor(post);
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

    final Finder cover = find.byType(ThumbnailBuild).first;
    final Size box = tester.renderObject<RenderBox>(cover).size;
    final BoxFit fit = tester.widget<ThumbnailBuild>(cover).fit ?? BoxFit.contain;
    return (box: box, fit: fit, painted: applyBoxFit(fit, sourceCover, box).destination);
  }

  BooruHandler schale() =>
      SchaleHandler(Booru('n', BooruType.NiyaNiya, '', 'https://niyaniya.moe', ''), 20);
  BooruHandler nhentai() =>
      NHentaiHandler(Booru('n', BooruType.NHentai, '', 'https://nhentai.net', ''), 20);
  BooruHandler hitomi() =>
      HitomiHandler(Booru('h', BooruType.Hitomi, '', 'https://hitomi.la', ''), 20);
  BooruHandler hentalk() =>
      FaccinaHandler(Booru('h', BooruType.Faccina, '', 'https://hentalk.pw', ''), 20);

  testWidgets('a cover fills its card rather than leaving side bars', (tester) async {
    final r = await layout(tester, schale(), 'https://niyaniya.moe/g/1/k');

    expect(
      r.painted.width,
      closeTo(r.box.width, 1),
      reason: 'painted ${r.painted} in ${r.box} with ${r.fit} — dead space horizontally',
    );
    expect(
      r.painted.height,
      closeTo(r.box.height, 1),
      reason: 'painted ${r.painted} in ${r.box} with ${r.fit} — dead space vertically',
    );
  });

  testWidgets('every source fills identically, including nhentai', (tester) async {
    // The comparison that was asked for. Any difference here is the card
    // treating a source specially, which it must not.
    final results = <String, ({Size box, BoxFit fit, Size painted})>{
      'niyaniya': await layout(tester, schale(), 'https://niyaniya.moe/g/1/k'),
      'nhentai': await layout(tester, nhentai(), 'https://nhentai.net/g/1/'),
      'hitomi': await layout(tester, hitomi(), 'https://hitomi.la/galleries/1.html'),
      'hentalk': await layout(tester, hentalk(), 'https://hentalk.pw/g/1'),
    };

    for (final entry in results.entries) {
      expect(
        entry.value.painted.width,
        closeTo(entry.value.box.width, 1),
        reason: '${entry.key} painted ${entry.value.painted} in ${entry.value.box}',
      );
    }

    // And the geometry itself is the same everywhere.
    final Set<Size> boxes = results.values.map((r) => r.box).toSet();
    expect(boxes, hasLength(1), reason: 'sources were given different cover boxes: $boxes');
  });

  testWidgets('the old default is what left the dead space', (tester) async {
    // Kept as a record of the real failure: under 'fit' the same card paints a
    // fifth of its width empty. This is the number that made my previous claim
    // false.
    final r = await layout(tester, schale(), 'https://niyaniya.moe/g/1/k');
    final Size underFit = applyBoxFit(BoxFit.contain, sourceCover, r.box).destination;

    expect(underFit.width, lessThan(r.box.width - 30));
    expect(r.painted.width, greaterThan(underFit.width));
  });

  testWidgets('a source can still choose to see the whole cover', (tester) async {
    // Filling is the default, not a lock-in.
    SourceSettingsHandler.instance.update(
      Booru('n', BooruType.NiyaNiya, '', 'https://niyaniya.moe', ''),
      (s) => s.coverDisplay = 'fit',
    );
    final r = await layout(tester, schale(), 'https://niyaniya.moe/g/1/k');

    expect(r.fit, BoxFit.contain);
  });
}
