import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/modular_ui.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail.dart';
import 'package:lolisnatcher/src/widgets/video/media_kit_player_view.dart';

/// r52: swiping between videos slid in a black panel, and the video popped in
/// once its player attached at the end of the swipe. The page now shows the
/// post thumbnail until the video's first frame is on screen (Modular UI).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final Booru booru = Booru('e621', BooruType.e621, '', 'https://e621.net', '');
  late Directory tempDir;

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    SnatchHandler.register();
    TagHandler.register();
    NavigationHandler.register();
    tempDir = Directory.systemTemp.createTempSync('media_kit_cover');
    SettingsHandler.instance
      ..path = '${tempDir.path}${Platform.pathSeparator}'
      ..preloadVideos = false;
    SettingsHandler.instance.modularUi.clear();
  });

  tearDown(() {
    SettingsHandler.instance.modularUi.clear();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('the cover stays until the first frame is drawn, and only while switched on', () {
    expect(MediaKitPlayerView.showCover(enabled: true, hasPlayer: false, firstFrame: false), isTrue);
    expect(MediaKitPlayerView.showCover(enabled: true, hasPlayer: true, firstFrame: false), isTrue);
    expect(MediaKitPlayerView.showCover(enabled: true, hasPlayer: true, firstFrame: true), isFalse);
    expect(MediaKitPlayerView.showCover(enabled: false, hasPlayer: false, firstFrame: false), isFalse);
    expect(ModularUi.all, contains(ModularUi.viewerVideoCover));
    expect(ModularUi.isOn(ModularUi.viewerVideoCover), isTrue);
  });

  testWidgets('a page whose player is not made yet shows the post thumbnail, not a black panel', (tester) async {
    final BooruItem item = BooruItem(
      fileURL: 'https://static1.e621.invalid/data/aa/bb/clip.webm',
      sampleURL: 'https://static1.e621.invalid/data/sample/aa/bb/clip.jpg',
      thumbnailURL: 'https://static1.e621.invalid/data/preview/aa/bb/clip.jpg',
      tagsList: [],
      postURL: 'https://e621.net/posts/1',
    );
    await tester.pumpWidget(
      MaterialApp(home: MediaKitPlayerView(item, booru: booru, isViewed: false, key: const ValueKey('on'))),
    );
    await tester.pump();
    tester.takeException();
    expect(find.byType(Thumbnail), findsOneWidget);

    SettingsHandler.instance.modularUi[ModularUi.viewerVideoCover.key] = false;
    await tester.pumpWidget(
      MaterialApp(home: MediaKitPlayerView(item, booru: booru, isViewed: false, key: const ValueKey('off'))),
    );
    await tester.pump();
    tester.takeException();
    expect(find.byType(Thumbnail), findsNothing, reason: 'switched off: the black panel as before');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    tester.takeException();
  });
}
