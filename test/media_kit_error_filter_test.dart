import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/widgets/video/media_kit_player_view.dart';

/// r77: a frame grab that comes before mpv has drawn anything makes mpv say
/// "Taking screenshot failed." at error level, and media_kit reports that as
/// a player error. On the phone that marked the player broken (12 times on
/// 19 Sep). Only mpv's two screenshot messages, and only within 15 s of a grab
/// on that player, are not player errors.
void main() {
  const Duration grab = Duration(minutes: 7, seconds: 5);

  test('the two screenshot messages right after a grab are not player errors', () {
    expect(MediaKitPlayerView.isScreenshotNoise('Taking screenshot failed.', lastGrabAt: grab, now: grab + const Duration(milliseconds: 11)), isTrue);
    expect(MediaKitPlayerView.isScreenshotNoise('Error writing screenshot!\n', lastGrabAt: grab, now: grab + const Duration(seconds: 1)), isTrue);
  });

  test('without a grab, or long after it, they count like any error', () {
    expect(MediaKitPlayerView.isScreenshotNoise('Taking screenshot failed.', lastGrabAt: null, now: grab), isFalse);
    expect(MediaKitPlayerView.isScreenshotNoise('Taking screenshot failed.', lastGrabAt: grab, now: grab + const Duration(seconds: 16)), isFalse);
  });

  test('anything else stays a player error, even when it mentions a screenshot', () {
    final Duration now = grab + const Duration(milliseconds: 50);
    expect(MediaKitPlayerView.isScreenshotNoise('Failed to open https://img.example/screenshot.mp4.', lastGrabAt: grab, now: now), isFalse);
    expect(MediaKitPlayerView.isScreenshotNoise('Could not open codec.', lastGrabAt: grab, now: now), isFalse);
    expect(MediaKitPlayerView.isScreenshotNoise('tcp: ffurl_read returned 0xffffff92', lastGrabAt: grab, now: now), isFalse);
  });
}
