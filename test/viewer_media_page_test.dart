import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_view/photo_view.dart';

import 'package:lolisnatcher/features/video/ui/video_viewer.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_media_page.dart';
import 'package:lolisnatcher/features/viewer/ui/media/image_viewer.dart';
import 'package:lolisnatcher/models/booru_item.dart';

/// M3 (token 151): ViewerHandler drives the image and the ExoPlayer video
/// pages through ViewerMediaPage / ViewerVideoPage instead of importing them.
void main() {
  BooruItem item(String id) => BooruItem(fileURL: 'f$id', sampleURL: 's$id', thumbnailURL: 't$id', tagsList: const [], postURL: 'p$id');

  testWidgets('the handler reads and drives a ViewerMediaPage', (WidgetTester tester) async {
    final BooruItem image = item('1');
    final BooruItem video = item('2');
    final ViewerHandler handler = ViewerHandler();

    await tester.pumpWidget(
      Column(
        children: [
          _FakePage(key: image.key),
          _FakeVideoPage(key: video.key),
        ],
      ),
    );
    final _FakePageState imagePage = tester.state(find.byKey(image.key));
    final _FakePageState videoPage = tester.state(find.byKey(video.key));

    // setNewState copies the page's state into the handler.
    handler.current.value = video;
    videoPage.isZoomed.value = true;
    videoPage.isStopped.value = true;
    videoPage.loaded = true;
    videoPage.fullScreen = true;
    handler.setNewState(video.key);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(handler.isZoomed.value, isTrue);
    expect(handler.isLoaded.value, isTrue);
    expect(handler.isStopped.value, isTrue);
    expect(handler.isFullscreen.value, isTrue);
    expect(handler.viewState.value, videoPage.viewController.value);

    // Zoom and force load go to the current page.
    handler.current.value = image;
    handler.isZoomed.value = false;
    handler.toggleZoom();
    handler.isZoomed.value = true;
    handler.toggleZoom();
    handler.forceLoadCurrentItem();
    expect(imagePage.calls, ['doubleTapZoom', 'resetZoom', 'forceLoad']);
    expect(videoPage.calls, isEmpty);

    // Extra UI, mute and pause go to every active page; mute/pause only to video pages.
    handler.addViewed(image.key);
    handler.addViewed(video.key);
    handler.hideExtraUi();
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(imagePage.extraUi.value, isFalse);
    expect(videoPage.extraUi.value, isFalse);
    handler.showExtraUi();
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(imagePage.extraUi.value, isTrue);
    expect(videoPage.extraUi.value, isTrue);

    handler.toggleMuteAllVideos();
    handler.toggleMuteAllVideos(mute: false);
    handler.pauseAllVideos();
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(videoPage.calls, ['volume 0.0', 'volume 1.0', 'pause']);
    expect(imagePage.calls, ['doubleTapZoom', 'resetZoom', 'forceLoad']);
  });

  test('the image and video pages implement the interfaces', () {
    // Type checks without building the pages (their fields read handlers).
    bool isA2<A, B>() => <A>[] is List<B>;
    expect(isA2<ImageViewerState, ViewerMediaPage>(), isTrue);
    expect(isA2<ImageViewerState, ViewerVideoPage>(), isFalse);
    expect(isA2<VideoViewerState, ViewerMediaPage>(), isTrue);
    expect(isA2<VideoViewerState, ViewerVideoPage>(), isTrue);
  });

  test('the handler no longer imports the image and video pages', () {
    final String handler = File('lib/features/viewer/logic/viewer_handler.dart').readAsStringSync();
    expect(handler, isNot(contains('ui/media/image_viewer.dart')));
    expect(handler, isNot(contains('ui/video_viewer.dart')));
  });
}

class _FakePage extends StatefulWidget {
  const _FakePage({super.key});

  @override
  State<_FakePage> createState() => _FakePageState();
}

class _FakeVideoPage extends _FakePage {
  const _FakeVideoPage({super.key});

  @override
  State<_FakePage> createState() => _FakeVideoPageState();
}

class _FakePageState extends State<_FakePage> implements ViewerMediaPage {
  @override
  final PhotoViewController viewController = PhotoViewController();
  @override
  final ValueNotifier<bool> isZoomed = ValueNotifier(false);
  @override
  final ValueNotifier<bool> isStopped = ValueNotifier(false);
  @override
  final ValueNotifier<bool> extraUi = ValueNotifier(true);

  bool loaded = false;
  bool fullScreen = false;
  final List<String> calls = [];

  @override
  bool get isMediaLoaded => loaded;
  @override
  bool get isMediaFullScreen => fullScreen;

  @override
  void doubleTapZoom() => calls.add('doubleTapZoom');
  @override
  void resetZoom() => calls.add('resetZoom');
  @override
  void forceLoad() => calls.add('forceLoad');

  @override
  void dispose() {
    viewController.dispose();
    isZoomed.dispose();
    isStopped.dispose();
    extraUi.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox(height: 10);
}

/// Only video pages implement ViewerVideoPage, so only they get mute and pause.
class _FakeVideoPageState extends _FakePageState implements ViewerVideoPage {
  @override
  void setVolume(double volume) => calls.add('volume $volume');

  @override
  void pause() => calls.add('pause');
}
