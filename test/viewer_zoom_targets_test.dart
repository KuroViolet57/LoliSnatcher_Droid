import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the zoom button reaches a fast GIF and a media_kit video', () {
    final String handler = File('lib/features/viewer/logic/viewer_handler.dart').readAsStringSync();
    // Reached through the logic-layer ViewerZoomTarget, not by importing the
    // ui pages (test/viewer_zoom_target_test.dart drives it).
    expect(handler, contains('case final ViewerZoomTarget target:'));

    final String gif = File('lib/features/viewer/ui/media/gif_viewer.dart').readAsStringSync();
    expect(gif, contains('class GifViewerState extends State<GifViewer> implements ViewerZoomTarget'));
    expect(gif, contains('void doubleTapZoom()'));
    expect(gif, contains('void resetZoom()'));
    expect(gif, contains('PhotoView.customChild'));

    final String mediaKit = File('lib/features/video/ui/media_kit_player_view.dart').readAsStringSync();
    expect(mediaKit, contains('class MediaKitPlayerViewState extends State<MediaKitPlayerView> with TraceLifecycle implements ViewerZoomTarget'));
    expect(mediaKit, contains('void doubleTapZoom()'));
    expect(mediaKit, contains('void resetZoom()'));
    expect(mediaKit, contains('PhotoView.customChild'));
  });
}
