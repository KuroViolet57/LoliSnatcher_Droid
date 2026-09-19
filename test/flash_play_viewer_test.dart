import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/furaffinity_handler.dart';
import 'package:lolisnatcher/src/boorus/furaffinity_parser.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/pages/flash_player_page.dart';
import 'package:lolisnatcher/src/widgets/video/flash_play_viewer.dart';

/// r48: a Flash post in the viewer is its thumbnail and a Play button. Before,
/// the viewer loaded the post ("Loading item data"), then tried to guess a
/// video or image type and ended on "Failed to guess the file extension",
/// although the top bar already knew it was Flash.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final Booru fa = Booru('FurAffinity', BooruType.FurAffinity, '', 'https://www.furaffinity.net', '');

  setUp(() {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('flash_play_viewer');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  BooruItem item({required List<Tag> tags, String fileURL = 'https://t.invalid/1@600-1.jpg', String? ext, MediaType type = MediaType.needToLoadItem}) {
    final BooruItem i = BooruItem(
      fileURL: fileURL,
      sampleURL: fileURL,
      thumbnailURL: 'https://t.invalid/1@200-1.jpg',
      tagsList: tags,
      postURL: 'https://www.furaffinity.net/view/1/',
      serverId: '1',
      fileExt: ext,
    );
    i.mediaType.value = type;
    return i;
  }

  test('which posts get the Play screen: Flash by listing or by file, never a picture, a GIF or a video', () {
    expect(FlashPlayViewer.shouldShow(item(tags: [FurAffinityParser.typeTag('flash')])), isTrue, reason: 'a FurAffinity listing says flash');
    expect(FlashPlayViewer.shouldShow(item(tags: [], fileURL: 'https://static1.e621.net/data/a/b/c.swf', ext: 'swf', type: MediaType.unknown)), isTrue);
    expect(FlashPlayViewer.shouldShow(item(tags: [FurAffinityParser.typeTag('image')])), isFalse);
    expect(FlashPlayViewer.shouldShow(item(tags: [], fileURL: 'https://d.invalid/a.gif', ext: 'gif', type: MediaType.animation)), isFalse);
    expect(FlashPlayViewer.shouldShow(item(tags: [], fileURL: 'https://d.invalid/a.mp4', ext: 'mp4', type: MediaType.video)), isFalse);
  });

  testWidgets('the Play screen: a Play button in the middle that opens the Flash player', (tester) async {
    final BooruItem flash = item(
      tags: [FurAffinityParser.typeTag('flash')],
      fileURL: 'https://d.furaffinity.net/art/a/1/a.swf',
      ext: 'swf',
      type: MediaType.unknown,
    );
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: Scaffold(
            body: FlashPlayViewer(
              item: flash,
              handler: FurAffinityHandler(fa, 48),
              loadInBackground: false,
              background: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('flash-play')), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.textContaining('Failed to guess'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('flash-play')));
    await tester.pump();
    final Object? first = tester.takeException();
    await tester.pump(const Duration(milliseconds: 400));
    final Object? second = tester.takeException();
    expect(find.byType(FlashPlayerPage), findsOneWidget, reason: 'Play opened the Flash player');
    // Unit tests have no webview platform, so the page's webview asserts while
    // it builds; that, and only that, is expected here.
    for (final Object? e in [first, second]) {
      if (e != null) expect('$e', contains('InAppWebViewPlatform'));
    }
  });

  test('the player page takes the post site as its origin, so e621 serves its movie too', () {
    expect(FlashPlayerPage.baseUrlFor(item(tags: [])), 'https://www.furaffinity.net/');
    final BooruItem e621 = BooruItem(
      fileURL: 'https://static1.e621.net/data/a/b/c.swf',
      sampleURL: '',
      thumbnailURL: '',
      tagsList: const [],
      postURL: 'https://e621.net/posts/123?',
      serverId: '123',
      fileExt: 'swf',
    );
    expect(FlashPlayerPage.baseUrlFor(e621), 'https://e621.net/');
    expect(FlashPlayerPage.baseUrlFor(BooruItem(fileURL: '', sampleURL: '', thumbnailURL: '', tagsList: const [], postURL: '')), FlashPlayerPage.baseUrl);
  });
}
