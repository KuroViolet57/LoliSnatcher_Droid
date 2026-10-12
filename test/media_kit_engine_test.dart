import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/src/player/native/utils/android_helper.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/android_gpu_options.dart';

import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/video/logic/first_frame_clock.dart';
import 'package:lolisnatcher/features/video/logic/media_kit_engine.dart';
import 'package:lolisnatcher/models/settings/mpv_build.dart';

/// Token 153: our own libmpv (mpv 0.41) ships next to the classic one and is
/// picked in Settings -> Video. See docs/superpowers/specs/2026-10-12-media-kit-engine-design.md.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MpvBuild', () {
    test('classic is the default and unknown values read as classic', () {
      expect(MpvBuild.fromSetting(null), MpvBuild.classic);
      expect(MpvBuild.fromSetting(''), MpvBuild.classic);
      expect(MpvBuild.fromSetting('nope'), MpvBuild.classic);
      expect(MpvBuild.fromSetting('classic'), MpvBuild.classic);
      expect(MpvBuild.fromSetting('mpv041'), MpvBuild.mpv041);
    });

    test('each build has its own library file', () {
      expect(MpvBuild.classic.libraryName, 'libmpv.so');
      expect(MpvBuild.mpv041.libraryName, 'libmpvls.so');
      expect(MpvBuild.settingOptions, ['classic', 'mpv041']);
      expect(MpvBuild.mpv041.setting, 'mpv041');
    });
  });

  group('MediaKitEngine', () {
    setUp(MediaKitEngine.resetForTest);

    test('the first call picks the library; later calls never re-resolve', () {
      final List<String> opened = [];
      expect(MediaKitEngine.ensureInitialized('mpv041', open: opened.add), MpvBuild.mpv041);
      expect(MediaKitEngine.ensureInitialized('classic', open: opened.add), MpvBuild.mpv041);
      expect(opened, ['libmpvls.so'], reason: 'a second resolve would switch libraries under live players');
      expect(MediaKitEngine.loaded, MpvBuild.mpv041);
    });

    test('a new library that will not open falls back to classic and says so', () {
      final List<String> opened = [];
      final List<String> logs = [];
      final MpvBuild b = MediaKitEngine.ensureInitialized(
        'mpv041',
        open: (String lib) {
          if (lib == 'libmpvls.so') throw ArgumentError('dlopen failed');
          opened.add(lib);
        },
        log: logs.add,
      );
      expect(b, MpvBuild.classic);
      expect(opened, ['libmpv.so']);
      expect(logs.join('\n'), contains('libmpvls.so'));
      expect(logs.join('\n'), contains('classic'));
    });

    test('restart is needed only when the setting differs from what is loaded', () {
      expect(MediaKitEngine.restartNeeded('mpv041'), isFalse, reason: 'nothing loaded yet');
      MediaKitEngine.ensureInitialized('classic', open: (_) {});
      expect(MediaKitEngine.restartNeeded('classic'), isFalse);
      expect(MediaKitEngine.restartNeeded('mpv041'), isTrue);
    });

    test('the engine line names the build, file and versions', () {
      expect(
        MediaKitEngine.engineLine(MpvBuild.mpv041, mpvVersion: 'mpv v0.41.0-110', ffmpegVersion: 'n7.1.3'),
        'media_kit engine: mpv041 (libmpvls.so) · mpv v0.41.0-110 · FFmpeg n7.1.3',
      );
    });

    test('nothing else calls MediaKit.ensureInitialized', () {
      final List<String> callers = [
        for (final FileSystemEntity f in Directory('lib').listSync(recursive: true))
          if (f is File && f.path.endsWith('.dart') && f.readAsStringSync().contains('MediaKit.ensureInitialized(')) f.path,
      ];
      expect(callers.map((String p) => p.replaceAll(r'\', '/')), ['lib/features/video/logic/media_kit_engine.dart']);
    });
  });

  test('media_kit hands the JavaVM to the library it was told to use', () {
    expect(AndroidHelper.libmpvName(null), 'libmpv.so');
    expect(AndroidHelper.libmpvName('libmpvls.so'), 'libmpvls.so');
    final String real = File('third_party/media_kit/lib/src/player/native/player/real.dart').readAsStringSync();
    expect(real, contains('AndroidHelper.ensureInitialized(libmpv: libmpv)'));
  });

  test('vo=gpu keeps the OpenGL context; gpu-next may use Vulkan', () {
    expect(androidGpuOptions('gpu'), {'opengl-es': 'yes', 'gpu-context': 'android'});
    expect(androidGpuOptions(null), {'opengl-es': 'yes', 'gpu-context': 'android'});
    expect(androidGpuOptions('gpu-next'), {'gpu-api': 'vulkan,opengl'});
  });

  test('the libs package copies both jars, each checked by SHA-256', () {
    final String gradle = File('third_party/media_kit_libs_android_video/android/build.gradle').readAsStringSync();
    expect(gradle, contains('default-arm64-v8a.jar'));
    expect(gradle, contains('2A906875AF68BE8C98C4A83C236BC24053F46E0ACCF62B115993EF1D740E98CC'));
    expect(gradle, contains('ls-arm64-v8a.jar'));
    expect(gradle, contains('1274F9F4CD9EA8F777D0E3FB761EB986A79648090715C1A25206E1B679339AA8'));
    expect(File('third_party/libmpv-android/ls-arm64-v8a.jar').existsSync(), isTrue);
  });

  test('the setting is in the schema, defaults to classic and survives a reload', () async {
    SettingsHandler.register();
    final String schema = File('lib/core/settings/settings_handler/schema.dart').readAsStringSync();
    expect(schema, contains("'mediaKitLibmpv'"));
    expect(SettingsHandler.instance.mediaKitLibmpv, 'classic');
    final Directory tempDir = Directory.systemTemp.createTempSync('mpv_build');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    try {
      await SettingsHandler.instance.loadFromJSON('{"mediaKitLibmpv": "mpv041"}', false);
      expect(SettingsHandler.instance.mediaKitLibmpv, 'mpv041');
      expect(SettingsHandler.instance.toJson()['mediaKitLibmpv'], 'mpv041');
      await SettingsHandler.instance.loadFromJSON('{"mediaKitLibmpv": "bogus"}', false);
      expect(SettingsHandler.instance.mediaKitLibmpv, 'classic');
    } finally {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('FirstFrameClock', () {
    test('reports once, at the first position past zero', () {
      final FirstFrameClock c = FirstFrameClock();
      expect(c.onPosition(Duration.zero, 120), isNull);
      expect(c.onPosition(const Duration(milliseconds: 33), 410), 410);
      expect(c.onPosition(const Duration(milliseconds: 66), 450), isNull);
    });

    test('the line says how the player was got', () {
      expect(FirstFrameClock.line(410, 'reused', MpvBuild.mpv041), 'video: playing after 410 ms (reused, mpv041)');
    });
  });
}
