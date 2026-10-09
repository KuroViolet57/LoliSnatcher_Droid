import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_view/photo_view.dart';

import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_zoom_target.dart';
import 'package:lolisnatcher/models/booru_item.dart';

/// The zoom button drives any viewer page whose State implements
/// ViewerZoomTarget (the fast GIF and the media_kit video), without the
/// handler importing those ui pages.
void main() {
  testWidgets('the zoom button zooms, resets and reads a ViewerZoomTarget page', (WidgetTester tester) async {
    final BooruItem item = BooruItem(fileURL: 'f', sampleURL: 's', thumbnailURL: 't', tagsList: const [], postURL: 'p');
    final ViewerHandler handler = ViewerHandler();
    handler.current.value = item;

    await tester.pumpWidget(_FakeZoomPage(key: item.key));
    final _FakeZoomPageState page = tester.state(find.byType(_FakeZoomPage));

    handler.toggleZoom();
    expect(page.zoomIns, 1);
    expect(page.resets, 0);

    handler.isZoomed.value = true;
    handler.toggleZoom();
    expect(page.resets, 1);

    page.isZoomed.value = true;
    handler.isZoomed.value = false;
    handler.isLoaded.value = true;
    handler.setNewState(item.key);
    tester.binding.scheduleFrame(); // a page change always has a frame coming
    await tester.pump();
    expect(handler.isZoomed.value, isTrue);
    expect(handler.isLoaded.value, isFalse); // the page reports no player yet
    expect(handler.isStopped.value, isFalse);
    expect(handler.isFullscreen.value, isFalse);
    expect(handler.viewState.value, page.viewController.value);
  });

  test('the handler no longer imports the GIF and media_kit pages', () {
    // Checked by test/architecture_test.dart too; kept here so the zoom
    // test names the reason.
    final String handler = File('lib/features/viewer/logic/viewer_handler.dart').readAsStringSync();
    expect(handler, isNot(contains('ui/media/gif_viewer.dart')));
    expect(handler, isNot(contains('ui/media_kit_player_view.dart')));
  });
}

class _FakeZoomPage extends StatefulWidget {
  const _FakeZoomPage({super.key});

  @override
  State<_FakeZoomPage> createState() => _FakeZoomPageState();
}

class _FakeZoomPageState extends State<_FakeZoomPage> implements ViewerZoomTarget {
  @override
  final PhotoViewController viewController = PhotoViewController();
  @override
  final ValueNotifier<bool> isZoomed = ValueNotifier(false);
  @override
  bool get isZoomTargetLoaded => false;

  int zoomIns = 0;
  int resets = 0;

  @override
  void doubleTapZoom() => zoomIns++;

  @override
  void resetZoom() => resets++;

  @override
  void dispose() {
    viewController.dispose();
    isZoomed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
