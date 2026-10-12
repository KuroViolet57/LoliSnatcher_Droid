import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/video/logic/engine_measurements.dart';
import 'package:lolisnatcher/features/video/logic/media_kit_engine_options.dart';
import 'package:lolisnatcher/models/settings/mpv_build.dart';
import 'package:lolisnatcher/models/settings/mpv_hardware_decoding.dart';
import 'package:lolisnatcher/models/settings/mpv_video_output.dart';

/// Token 154: engine step 2 - measured times in the (i) window, the decoder
/// chain and the SurfaceTexture fallback, each behind its own switch.
/// Plan: docs/superpowers/plans/2026-10-12-media-kit-engine-step2.md.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SettingsHandler.register();
    final SettingsHandler s = SettingsHandler.instance;
    s.altVideoPlayerHwAccel = true;
    s.altVideoPlayerVO = MpvVideoOutput.gpu;
    s.altVideoPlayerHWDEC = MpvHardwareDecoding.vulkan;
    s.mediaKitHwdecChain = false;
    s.mediaKitSurfaceTexture = false;
  });

  group('defaults keep what 153 sent', () {
    test('both switches start off', () {
      SettingsHandler.unregister();
      SettingsHandler.register();
      expect(SettingsHandler.instance.mediaKitHwdecChain, isFalse);
      expect(SettingsHandler.instance.mediaKitSurfaceTexture, isFalse);
    });

    test('off: hwdec from the dropdown and the SurfaceProducer path', () {
      final VideoControllerConfiguration c = MediaKitEngineOptions.videoController(SettingsHandler.instance);
      expect(c.hwdec, 'vulkan');
      expect(c.vo, 'gpu');
      expect(c.enableAndroidSurfaceProducer, isTrue);
      expect(c.androidAttachSurfaceAfterVideoParameters, isTrue);
    });
  });

  group('decoder chain', () {
    test('on: the phone decoder first, then the copying one', () {
      SettingsHandler.instance.mediaKitHwdecChain = true;
      final VideoControllerConfiguration c = MediaKitEngineOptions.videoController(SettingsHandler.instance);
      expect(c.hwdec, 'mediacodec,mediacodec-copy');
      expect(MediaKitEngineOptions.hwdecChain, 'mediacodec,mediacodec-copy');
      expect(c.enableAndroidSurfaceProducer, isTrue, reason: 'one switch never flips the other');
    });

    test('hardware acceleration off still means software decoding', () {
      SettingsHandler.instance.mediaKitHwdecChain = true;
      SettingsHandler.instance.altVideoPlayerHwAccel = false;
      SettingsHandler.instance.altVideoPlayerHWDEC = MpvHardwareDecoding.autoSafe;
      final VideoControllerConfiguration c = MediaKitEngineOptions.videoController(SettingsHandler.instance);
      expect(c.hwdec, 'auto-safe', reason: 'the chain only replaces the dropdown while hardware decoding is allowed');
    });
  });

  test('SurfaceTexture switch asks media_kit_video for the SurfaceTexture path', () {
    SettingsHandler.instance.mediaKitSurfaceTexture = true;
    final VideoControllerConfiguration c = MediaKitEngineOptions.videoController(SettingsHandler.instance);
    expect(c.enableAndroidSurfaceProducer, isFalse);
    expect(c.hwdec, 'vulkan');
  });

  test('the pool signature changes with either switch, so idle players are rebuilt', () {
    final SettingsHandler s = SettingsHandler.instance;
    final String base = MediaKitEngineOptions.signature(s);
    expect(base, 'gpu|vulkan|true', reason: '153 slots keep matching while both switches are off');
    s.mediaKitHwdecChain = true;
    final String chain = MediaKitEngineOptions.signature(s);
    s.mediaKitHwdecChain = false;
    s.mediaKitSurfaceTexture = true;
    final String texture = MediaKitEngineOptions.signature(s);
    expect({base, chain, texture}.length, 3);
    expect(MediaKitEngineOptions.surfaceLabel(s), 'texture');
    expect(MediaKitEngineOptions.surfaceOfSignature(texture), 'texture');
    s.mediaKitHwdecChain = true;
    expect(MediaKitEngineOptions.surfaceOfSignature(MediaKitEngineOptions.signature(s)), 'texture');
    s.mediaKitSurfaceTexture = false;
    expect(MediaKitEngineOptions.surfaceLabel(s), 'producer');
    expect(MediaKitEngineOptions.surfaceOfSignature(chain), 'producer');
    expect(MediaKitEngineOptions.surfaceOfSignature(base), 'producer');
  });

  test('the pool uses the shared signature', () {
    final String pool = File('lib/features/video/ui/media_kit_player_view/player_pool.dart').readAsStringSync();
    expect(pool, contains('MediaKitEngineOptions.signature(settings)'));
    expect(pool, contains('MediaKitEngineOptions.surfaceOfSignature(entry.options)'));
    expect(pool, contains(r'surface $surface'));
  });

  test('both settings are in the schema, device-specific, and survive a reload (backup)', () async {
    final String schema = File('lib/core/settings/settings_handler/schema.dart').readAsStringSync();
    expect(schema, contains("'mediaKitHwdecChain'"));
    expect(schema, contains("'mediaKitSurfaceTexture'"));
    final SettingsHandler s = SettingsHandler.instance;
    expect(s.deviceSpecificSettings, containsAll(['mediaKitHwdecChain', 'mediaKitSurfaceTexture']));
    final Directory tempDir = Directory.systemTemp.createTempSync('engine_step2');
    s.path = '${tempDir.path}${Platform.pathSeparator}';
    try {
      await s.loadFromJSON('{"mediaKitHwdecChain": true, "mediaKitSurfaceTexture": true}', false);
      expect(s.mediaKitHwdecChain, isTrue);
      expect(s.mediaKitSurfaceTexture, isTrue);
      expect(s.toJson()['mediaKitHwdecChain'], isTrue);
      expect(s.toJson()['mediaKitSurfaceTexture'], isTrue);
      await s.loadFromJSON('{"mediaKitHwdecChain": "nope"}', false);
      expect(s.mediaKitHwdecChain, isFalse);
    } finally {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('our media_kit_video', () {
    test('the flag defaults to SurfaceProducer and copyWith carries it', () {
      const VideoControllerConfiguration c = VideoControllerConfiguration();
      expect(c.enableAndroidSurfaceProducer, isTrue);
      expect(c.copyWith(enableAndroidSurfaceProducer: false).enableAndroidSurfaceProducer, isFalse);
      expect(c.copyWith(vo: 'gpu').enableAndroidSurfaceProducer, isTrue);
    });

    test('the Android controller hands the flag to the plugin', () {
      final String real = File(
        'third_party/media_kit_video/lib/src/video_controller/android_video_controller/real.dart',
      ).readAsStringSync();
      expect(real, contains("'enableSurfaceProducer': configuration.enableAndroidSurfaceProducer"));
    });

    /// Thor, 154 first build: with SurfaceTexture on, a pool player re-pointed
    /// at a video of another size showed it squashed (post 13 of the rule34
    /// feed: a 16:9 video drawn as a ~5:1 strip). The SurfaceTexture keeps one
    /// surface, so `wid` never changes on a resize and mpv kept the previous
    /// video's android-surface-size. A resize of an attached SurfaceTexture
    /// must re-run the same vo re-init a new wid triggers.
    test('a resized SurfaceTexture re-applies the surface size to mpv', () {
      final String real = File(
        'third_party/media_kit_video/lib/src/video_controller/android_video_controller/real.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      expect(real, contains('final int? widBefore = wid.value;'));
      expect(
        real,
        contains(
          'if (!configuration.enableAndroidSurfaceProducer && widBefore != null && widBefore != 0) {\n'
          '          unawaited(widListener());',
        ),
      );
    });

    test('the plugin builds a SurfaceTexture when asked, and frees its wid late', () {
      const String dir = 'third_party/media_kit_video/android/src/main/java/com/alexmercerind/media_kit_video';
      final String plugin = File('$dir/MediaKitVideoPlugin.java').readAsStringSync();
      final String output = File('$dir/VideoOutput.java').readAsStringSync();
      final String manager = File('$dir/VideoOutputManager.java').readAsStringSync();
      expect(plugin, contains('call.argument("enableSurfaceProducer")'));
      expect(manager, contains('boolean enableSurfaceProducer'));
      expect(output, contains('createSurfaceTexture()'));
      expect(output, contains('setDefaultBufferSize(width, height)'));
      expect(output, contains('postDelayed(() -> deleteGlobalObjectRef(widReference), 5000)'));
      expect(File('third_party/media_kit_video/LOLISNATCHER_PATCH.md').readAsStringSync(), contains('token 154'));
    });
  });

  group('measured times', () {
    test('each build names the device and the first-frame times', () {
      final String classic = EngineMeasurements.build(MpvBuild.classic);
      final String mpv041 = EngineMeasurements.build(MpvBuild.mpv041);
      for (final String t in [classic, mpv041]) {
        expect(t, contains('AYN Thor'));
        expect(t, contains('Snapdragon 8 Gen 2'));
      }
      expect(classic, contains('713 / 1288 / 1471 / 684 ms'));
      expect(mpv041, contains('1156 / 1538 / 801 / 762 ms'));
      expect(mpv041, contains('gpu-next'));
    });

    test('the libmpv (i) window shows them', () {
      final String page = File('lib/features/settings/ui/video_page.dart').readAsStringSync();
      expect(page, contains('EngineMeasurements.build(MpvBuild.classic)'));
      expect(page, contains('EngineMeasurements.build(MpvBuild.mpv041)'));
      expect(page, contains("ValueKey('media-kit-hwdec-chain-explain')"));
      expect(page, contains("ValueKey('media-kit-surface-texture-explain')"));
    });
  });
}
