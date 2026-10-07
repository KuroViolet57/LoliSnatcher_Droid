import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the zoom button reaches a fast GIF and a media_kit video', () {
    final String handler = File('lib/features/viewer/logic/viewer_handler.dart').readAsStringSync();
    expect(handler, contains('case GifViewer()'));
    expect(handler, contains('case MediaKitPlayerView()'));

    final String gif = File('lib/features/viewer/ui/media/gif_viewer.dart').readAsStringSync();
    expect(gif, contains('class GifViewerState'));
    expect(gif, contains('void doubleTapZoom()'));
    expect(gif, contains('void resetZoom()'));
    expect(gif, contains('PhotoView.customChild'));

    final String mediaKit = File('lib/features/video/ui/media_kit_player_view.dart').readAsStringSync();
    expect(mediaKit, contains('class MediaKitPlayerViewState'));
    expect(mediaKit, contains('void doubleTapZoom()'));
    expect(mediaKit, contains('void resetZoom()'));
    expect(mediaKit, contains('PhotoView.customChild'));
  });
}
