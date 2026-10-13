import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/surface_texture_resize.dart';

import 'package:lolisnatcher/features/video/logic/first_frame_clock.dart';
import 'package:lolisnatcher/features/video/logic/media_kit_engine.dart';
import 'package:lolisnatcher/models/settings/mpv_build.dart';

/// Fresh review of builds 153 + 154 (2026-10-14): findings 1, 2, 4 and 5.
/// Report: docs/superpowers/plans/2026-10-14-media-kit-engine-review.md.
void main() {
  group('finding 1: a build that would not open', () {
    setUp(MediaKitEngine.resetForTest);

    void failingMpv041(String lib) {
      if (lib == 'libmpvls.so') throw ArgumentError('dlopen failed');
    }

    test('the engine remembers which build fell back', () {
      expect(MediaKitEngine.fellBackFrom, isNull);
      MediaKitEngine.ensureInitialized('mpv041', open: failingMpv041, log: (_) {});
      expect(MediaKitEngine.loaded, MpvBuild.classic);
      expect(MediaKitEngine.fellBackFrom, MpvBuild.mpv041);
    });

    test('a restart is not promised when it would fall back again', () {
      MediaKitEngine.ensureInitialized('mpv041', open: failingMpv041, log: (_) {});
      expect(MediaKitEngine.restartNeeded('mpv041'), isFalse, reason: 'a restart repeats the same fallback');
      expect(MediaKitEngine.restartNeeded('classic'), isFalse);
    });

    test('the Settings line says the build would not open, not "restart"', () {
      MediaKitEngine.ensureInitialized('mpv041', open: failingMpv041, log: (_) {});
      final String s = MediaKitEngine.statusText('mpv041');
      expect(s, contains('${MpvBuild.mpv041.label} would not open'));
      expect(s, contains('${MpvBuild.classic.label} plays the videos'));
      expect(s, isNot(contains('Restart the app to switch')));
    });

    test('without a fallback the line is what 153 showed', () {
      expect(MediaKitEngine.statusText('classic'), 'Nothing loaded yet in this run.');
      MediaKitEngine.ensureInitialized('classic', open: (_) {}, log: (_) {});
      expect(MediaKitEngine.statusText('classic'), 'Loaded now: ${MpvBuild.classic.label}.');
      expect(MediaKitEngine.statusText('mpv041'), 'Loaded now: ${MpvBuild.classic.label}. Restart the app to switch.');
      expect(MediaKitEngine.fellBackFrom, isNull);
    });

    test('the Settings page uses the engine line', () {
      final String page = File('lib/features/settings/ui/video_page.dart').readAsStringSync();
      expect(page, contains('MediaKitEngine.statusText(mediaKitLibmpv)'));
    });
  });

  group('finding 2: the SurfaceTexture resize re-init', () {
    test('runs only for an attached SurfaceTexture of a live player', () {
      expect(reapplySurfaceSizeAfterResize(surfaceProducer: false, widBefore: 42, disposed: false), isTrue);
      expect(reapplySurfaceSizeAfterResize(surfaceProducer: true, widBefore: 42, disposed: false), isFalse);
      expect(reapplySurfaceSizeAfterResize(surfaceProducer: false, widBefore: null, disposed: false), isFalse);
      expect(reapplySurfaceSizeAfterResize(surfaceProducer: false, widBefore: 0, disposed: false), isFalse);
      expect(
        reapplySurfaceSizeAfterResize(surfaceProducer: false, widBefore: 42, disposed: true),
        isFalse,
        reason: 'a pool slot disposed during SetSurfaceSize must not get mpv calls',
      );
    });

    test('the controller asks the helper and swallows a dispose that lands in between', () {
      final String real = File(
        'third_party/media_kit_video/lib/src/video_controller/android_video_controller/real.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      expect(real, contains('reapplySurfaceSizeAfterResize('));
      expect(real, contains('disposed: platform.disposed'));
      expect(real, contains('widListener().catchError('));
      expect(real, isNot(contains('if (!configuration.enableAndroidSurfaceProducer && widBefore != null && widBefore != 0) {')));
    });
  });

  group('finding 4: a reused player is timed from its rewind', () {
    test('a stale position from before the rewind is not a first frame', () {
      final FirstFrameClock c = FirstFrameClock()..afterRewind(parked: const Duration(seconds: 7), target: Duration.zero);
      expect(c.onPosition(const Duration(seconds: 7), 5), isNull, reason: 'where the slot was parked');
      expect(c.onPosition(Duration.zero, 40), isNull);
      expect(c.onPosition(const Duration(milliseconds: 33), 180), 180);
      expect(c.onPosition(const Duration(milliseconds: 66), 210), isNull);
    });

    // Recheck 2026-10-14, issue A: a 1 s window missed these three.
    test('a slot parked in its first second (or a short loop) is not read at its parked spot', () {
      const Duration parked = Duration(milliseconds: 420);
      final FirstFrameClock c = FirstFrameClock()..afterRewind(parked: parked, target: Duration.zero);
      expect(c.onPosition(parked, 3), isNull);
      expect(c.onPosition(parked, 4), isNull, reason: 'a paused player repeats the same position');
      expect(c.onPosition(const Duration(milliseconds: 21), 150), 150);
    });

    test('a slot resumed at a saved position is still timed', () {
      final FirstFrameClock c = FirstFrameClock()
        ..afterRewind(parked: const Duration(seconds: 3), target: const Duration(seconds: 12));
      expect(c.onPosition(const Duration(seconds: 3), 2), isNull);
      expect(c.onPosition(const Duration(milliseconds: 12033), 260), 260);
    });

    test('nothing to tell apart: parked at the start or exactly where it resumes', () {
      final FirstFrameClock fresh = FirstFrameClock()..afterRewind(parked: Duration.zero, target: Duration.zero);
      expect(fresh.onPosition(const Duration(milliseconds: 33), 300), 300);
      final FirstFrameClock same = FirstFrameClock()
        ..afterRewind(parked: const Duration(seconds: 5), target: const Duration(seconds: 5));
      expect(same.onPosition(const Duration(seconds: 5), 90), 90);
    });

    test('a new player is timed as before', () {
      final FirstFrameClock c = FirstFrameClock();
      expect(c.onPosition(const Duration(milliseconds: 33), 410), 410);
    });

    test('the view arms it for reused slots before listening', () {
      final String view = File('lib/features/video/ui/media_kit_player_view.dart').readAsStringSync();
      final int parked = view.indexOf('final Duration parked = entry.player.state.position;');
      final int seek = view.indexOf('await entry.player.seek(target);');
      final int arm = view.indexOf('_firstFrame.afterRewind(parked: parked, target: target)');
      final int listen = view.indexOf('_positionSub = entry.player.stream.position.listen');
      expect(parked, greaterThan(0));
      expect(parked, lessThan(seek), reason: 'the parked spot is read before the seek moves it');
      expect(arm, greaterThan(seek));
      expect(arm, lessThan(listen));
    });
  });

  test('finding 5: the (i) texts say Classic has no Vulkan at all', () {
    final String page = File('lib/features/settings/ui/video_page.dart').readAsStringSync();
    expect(page, isNot(contains('decodes in software with both builds')));
    expect(page, contains('always with Classic'));
  });
}
