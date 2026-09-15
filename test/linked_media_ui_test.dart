import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/furaffinity_handler.dart';
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
/// r50: each row says what the link is and where it goes.
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

  test("r52: the link button is offered once the post's links are known, for any file, in the share button's place", () {
    LinkedMediaStore.resetForTests();
    final BooruItem gif = post(['animated', FurAffinityParser.typeTag('image').fullString], type: MediaType.animation);
    expect(LinkedMediaButton.offerFor(gif), isFalse, reason: 'nothing known yet');
    LinkedMediaStore.remember(gif.postURL, [
      LinkedMedia(url: 'https://e621.net/posts/2197695', kind: LinkedMediaKind.sourcePost, booru: e621, postId: '2197695'),
    ]);
    expect(LinkedMediaButton.offerFor(gif), isTrue, reason: 'a GIF can link its full video too');
    expect(LinkedMediaButton.replacesShare, isTrue);
    SettingsHandler.instance.modularUi[ModularUi.viewerLinkedMediaReplacesShare.key] = false;
    expect(LinkedMediaButton.replacesShare, isFalse);
    SettingsHandler.instance.modularUi[ModularUi.viewerLinkedMedia.key] = false;
    expect(LinkedMediaButton.offerFor(gif), isFalse, reason: 'the button switched off');
    SettingsHandler.instance.modularUi.clear();
    LinkedMediaStore.remember(gif.postURL, const []);
    expect(LinkedMediaButton.offerFor(gif), isFalse);
    expect(ModularUi.all, containsAll([ModularUi.viewerLinkedMedia, ModularUi.viewerLinkedMediaReplacesShare]));
  });

  test("r52: loading a FurAffinity post remembers the media links of its description", () {
    LinkedMediaStore.resetForTests();
    SettingsHandler.instance.booruList.add(e621);
    const String marker = 'submission-description-text user-submitted-links">';
    final String html = fixture('furaffinity_view_folders.html').replaceFirst(
      marker,
      '${marker}WEBM version with sound only: https://e621.net/posts/2197699Character(s): Mal0<br />'
          'Voice: <a class="auto_link" href="http://dshooves.live/">http://dshooves.live/</a> ',
    );
    final BooruItem item = post(['animated']);
    FurAffinityHandler(fa, 20).applySubmission(item, FurAffinityParser.submission(html)!);
    final List<LinkedMedia> links = LinkedMediaStore.linksFor(item.postURL)!;
    expect(links.map((l) => (l.url, l.title)).toList(), [
      ('https://e621.net/posts/2197699', 'WEBM version with sound only'),
      // The fixture's own description links another submission: media, named by its line.
      ('https://www.furaffinity.net/view/61869875/', 'full colours made this pic last year from my wip sketch'),
    ], reason: 'the voice actor site is left out');
  });

  testWidgets('each row: what the link is, where it goes, and a badge; a file opens the linked media player', (tester) async {
    final List<LinkedMedia> items = [
      LinkedMedia(url: 'https://e621.net/posts/4011234', kind: LinkedMediaKind.sourcePost, booru: e621, postId: '4011234'),
      const LinkedMedia(url: 'https://files.example.com/final.mp4', kind: LinkedMediaKind.media),
      const LinkedMedia(url: 'https://x.com/artist/status/1', kind: LinkedMediaKind.page, text: 'My X'),
    ];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: LinkedMediaList(items: items, title: 'A post'))));
    expect(find.text('e621 post #4011234'), findsOneWidget);
    expect(find.text('Opens in the app · e621'), findsOneWidget);
    expect(find.text('In app'), findsOneWidget);
    expect(find.text('final.mp4'), findsOneWidget);
    expect(find.text('Video'), findsOneWidget);
    expect(find.text('My X'), findsOneWidget);
    expect(find.text('Opens the web page · x.com'), findsOneWidget);
    expect(find.text('Web'), findsOneWidget);
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

  testWidgets("the post page lists the description's links, unwrapped, an installed source's post first-class", (tester) async {
    SettingsHandler.instance.booruList.add(e621);
    tester.view.physicalSize = const Size(420, 7000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const String marker = 'submission-description-text user-submitted-links">';
    final String html = fixture('furaffinity_view_folders.html').replaceFirst(
      marker,
      '${marker}Full video: <a class="auto_link_shortened" '
          'href="https://www.furaffinity.net/externalurl/?q=https%3A%2F%2Fe621.net%2Fposts%2F4011234">Full animation</a> ',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: FurAffinityPostPage(booru: fa, item: post(['animated']), fetchPage: (String url) async => html),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Linked media'), findsOneWidget);
    expect(find.text('Full animation'), findsWidgets);
    expect(find.text('Opens in the app · e621'), findsOneWidget);
  });
}
