import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lolisnatcher/features/video/logic/double_tap_skip.dart';
import 'package:lolisnatcher/models/settings/video_engine_choice.dart';

void main() {
  test('double-tap skip matches the amounts LoliControls already uses', () {
    final DoubleTapSkip right = doubleTapSkip(
      screenWidth: 600,
      tapX: 550,
      duration: const Duration(seconds: 30),
      position: const Duration(seconds: 4),
    );
    expect(right.side, 1);
    expect(right.skipSeconds, 5);
    expect(right.newPosition, const Duration(seconds: 9));

    // The side band starts strictly past the middle plus one sixth.
    final DoubleTapSkip edge = doubleTapSkip(
      screenWidth: 600,
      tapX: 400,
      duration: const Duration(seconds: 30),
      position: const Duration(seconds: 4),
    );
    expect(edge.side, 0);
    expect(edge.newPosition, isNull);

    final DoubleTapSkip justRight = doubleTapSkip(
      screenWidth: 600,
      tapX: 401,
      duration: const Duration(seconds: 60),
      position: Duration.zero,
    );
    expect(justRight.side, 1);
    expect(justRight.skipSeconds, 5);

    final DoubleTapSkip justLeft = doubleTapSkip(
      screenWidth: 600,
      tapX: 199,
      duration: const Duration(seconds: 61),
      position: const Duration(seconds: 20),
    );
    expect(justLeft.side, -1);
    expect(justLeft.skipSeconds, 10);
    expect(justLeft.newPosition, const Duration(seconds: 10));

    final DoubleTapSkip center = doubleTapSkip(
      screenWidth: 600,
      tapX: 300,
      duration: const Duration(seconds: 30),
      position: const Duration(seconds: 4),
    );
    expect(center.side, 0);
    expect(center.newPosition, isNull);

    final DoubleTapSkip tiny = doubleTapSkip(
      screenWidth: 600,
      tapX: 10,
      duration: const Duration(seconds: 5),
      position: Duration.zero,
    );
    expect(tiny.skipSeconds, 0);
    expect(tiny.newPosition, isNull);

    final DoubleTapSkip ten = doubleTapSkip(
      screenWidth: 600,
      tapX: 10,
      duration: const Duration(seconds: 10),
      position: const Duration(seconds: 1),
    );
    expect(ten.skipSeconds, 1);
    expect(ten.side, -1);
    expect(ten.newPosition, Duration.zero);

    final DoubleTapSkip ending = doubleTapSkip(
      screenWidth: 600,
      tapX: 590,
      duration: const Duration(seconds: 121),
      position: const Duration(seconds: 120),
    );
    expect(ending.skipSeconds, 10);
    expect(ending.newPosition, const Duration(seconds: 121));
  });

  test('Media3 and mpvlib win on Android and do not change desktop', () {
    expect(
      viewerVideoEngine(
        isAndroid: true,
        choice: VideoEngineChoice.media3,
        useMediaKitPlayer: true,
        useBetterPlayer: true,
      ),
      ViewerVideoEngine.media3,
    );
    expect(
      viewerVideoEngine(
        isAndroid: true,
        choice: VideoEngineChoice.mpvlibVulkan,
        useMediaKitPlayer: true,
        useBetterPlayer: false,
      ),
      ViewerVideoEngine.mpvlib,
    );
    expect(
      viewerVideoEngine(
        isAndroid: true,
        choice: VideoEngineChoice.mpvlibOpengl,
        useMediaKitPlayer: false,
        useBetterPlayer: true,
      ),
      ViewerVideoEngine.mpvlib,
    );
    expect(
      viewerVideoEngine(
        isAndroid: true,
        choice: VideoEngineChoice.off,
        useMediaKitPlayer: true,
        useBetterPlayer: true,
      ),
      ViewerVideoEngine.mediaKit,
    );
    expect(
      viewerVideoEngine(
        isAndroid: true,
        choice: VideoEngineChoice.off,
        useMediaKitPlayer: false,
        useBetterPlayer: true,
      ),
      ViewerVideoEngine.betterPlayer,
    );
    expect(
      viewerVideoEngine(
        isAndroid: true,
        choice: VideoEngineChoice.off,
        useMediaKitPlayer: false,
        useBetterPlayer: false,
      ),
      ViewerVideoEngine.chewie,
    );
    expect(
      viewerVideoEngine(
        isAndroid: false,
        choice: VideoEngineChoice.mpvlibVulkan,
        useMediaKitPlayer: true,
        useBetterPlayer: true,
      ),
      ViewerVideoEngine.chewie,
    );

    expect(videoEngineChoiceFromString('nope'), VideoEngineChoice.off);
    expect(videoEngineChoiceFromString(null), VideoEngineChoice.off);
    expect(videoEngineChoiceFromString('media3'), VideoEngineChoice.media3);
    expect(mpvlibVariantFileText(VideoEngineChoice.mpvlibVulkan), 'vulkan');
    expect(mpvlibVariantFileText(VideoEngineChoice.mpvlibOpengl), 'opengl');
    expect(mpvlibVariantFileText(VideoEngineChoice.media3), 'off');
    expect(mpvlibVariantFileText(VideoEngineChoice.off), 'off');
    expect(VideoEngineChoice.mpvlibVulkan.usesVulkan, isTrue);
    expect(VideoEngineChoice.mpvlibOpengl.usesVulkan, isFalse);
  });

  test('the viewer keeps LoliControls when the new engines are selected', () {
    final String viewer = File('lib/features/video/ui/video_viewer.dart').readAsStringSync();
    final String controls = File('lib/features/video/ui/loli_controls.dart').readAsStringSync();
    final String gallery = File('lib/features/viewer/ui/gallery_view_page.dart').readAsStringSync();
    final String postFiles = File('lib/features/viewer/ui/post_files_page.dart').readAsStringSync();
    final String schema = File('lib/core/settings/settings_handler/schema.dart').readAsStringSync();
    expect(controls, contains('doubleTapSkip('));
    expect(viewer, contains('LoliControls('));
    expect(viewer, contains('BridgedVideoController'));
    expect(gallery, contains('viewerVideoEngine('));
    expect(postFiles, contains('viewerVideoEngine('));
    expect(schema, contains("'videoEngineChoice'"));
    expect(schema, contains("'off'"));
  });
}
