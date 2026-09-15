import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/furaffinity_parser.dart';
import 'package:lolisnatcher/src/boorus/linked_media.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/modular_ui.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/furaffinity_session_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/pages/furaffinity_post_page.dart';
import 'package:lolisnatcher/src/pages/linked_media_page.dart';
import 'package:lolisnatcher/src/widgets/linked_media_sheet.dart';

/// r49: where the linked media shows — the post page's "Linked media"
/// section and the viewer's link button on animated posts whose file is a
/// still picture (a Modular UI switch) — and what a tap opens.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final Booru fa = Booru('FurAffinity', BooruType.FurAffinity, '', 'https://www.furaffinity.net', '');
  final Booru e621 = Booru('e621', BooruType.e621, '', 'https://e621.net', '');
  String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    TagHandler.register();
    tempDir = Directory.systemTemp.createTempSync('linked_media_ui');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SettingsHandler.instance.modularUi.clear();
    FurAffinitySessionHandler.instance.resetForTests();
  });

  tearDown(() {
    SettingsHandler.instance.booruList.remove(e621);
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  BooruItem post(List<String> tags, {MediaType type = MediaType.needToLoadItem}) {
    final BooruItem item = BooruItem(
      fileURL: 'https://t.invalid/1@600-1.jpg',
      sampleURL: '',
      thumbnailURL: 'https://t.invalid/1@200-1.jpg',
      tagsList: [for (final String t in tags) Tag(t)],
      postURL: 'https://www.furaffinity.net/view/1/',
      serverId: '1',
    );
    item.mediaType.value = type;
    return item;
  }

  test('the link button: animated posts whose file is a still picture; not GIFs, videos or Flash; a Modular UI switch', () {
    expect(LinkedMediaButton.offerFor(post(['artist:x', 'animated'])), isTrue);
    expect(LinkedMediaButton.offerFor(post(['category:3d_animation'])), isTrue);
    expect(LinkedMediaButton.offerFor(post(['animated'], type: MediaType.video)), isFalse);
    expect(LinkedMediaButton.offerFor(post(['animated'], type: MediaType.animation)), isFalse);
    expect(LinkedMediaButton.offerFor(post(['animated', FurAffinityParser.typeTag('flash').fullString])), isFalse);
    expect(LinkedMediaButton.offerFor(post(['fox'])), isFalse);
    expect(ModularUi.all, contains(ModularUi.viewerLinkedMedia));
    expect(ModularUi.isOn(ModularUi.viewerLinkedMedia), isTrue);
  });

  testWidgets('the list says what each link is; a file opens the linked media player', (tester) async {
    final List<LinkedMedia> items = [
      LinkedMedia(url: 'https://e621.net/posts/4011234', kind: LinkedMediaKind.sourcePost, booru: e621, postId: '4011234'),
      const LinkedMedia(url: 'https://files.example.com/final.mp4', kind: LinkedMediaKind.media),
      const LinkedMedia(url: 'https://x.com/artist/status/1', kind: LinkedMediaKind.page),
    ];
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(home: Scaffold(body: LinkedMediaList(items: items, title: 'A post'))),
      ),
    );
    expect(find.text('Open on e621'), findsOneWidget);
    expect(find.text('Play the video'), findsOneWidget);
    expect(find.text('Open x.com'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('linked-media-1')));
    await tester.pump();
    final Object? first = tester.takeException();
    await tester.pump(const Duration(milliseconds: 400));
    final Object? second = tester.takeException();
    expect(find.byType(LinkedMediaPage), findsOneWidget);
    // Unit tests have no webview platform: only that assertion is expected.
    for (final Object? e in [first, second]) {
      if (e != null) expect('$e', contains('InAppWebViewPlatform'));
    }
  });

  testWidgets("the post page lists the description's links, an installed source's post first-class", (tester) async {
    SettingsHandler.instance.booruList.add(e621);
    tester.view.physicalSize = const Size(420, 7000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const String marker = 'submission-description-text user-submitted-links">';
    final String html = fixture('furaffinity_view_folders.html').replaceFirst(
      marker,
      '${marker}Full video: <a class="auto_link " href="https://e621.net/posts/4011234">https://e621.net/posts/4011234</a> ',
    );
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: FurAffinityPostPage(
            booru: fa,
            item: post(['animated']),
            fetchPage: (String url) async => html,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Linked media'), findsOneWidget);
    expect(find.text('Open on e621'), findsOneWidget);
  });
}
