import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:lolisnatcher/src/data/settings/mpv_hardware_decoding.dart';
import 'package:lolisnatcher/src/data/settings/mpv_video_output.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/video/media_kit_engine_options.dart';

/// The experimental media_kit gallery pool used to ignore Settings → Video
/// hwdec/vo (those only hit the Chewie plugin path). These options are what
/// the pool now applies, including a disk cache dir when one is given.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(SettingsHandler.register);

  test('video controller follows the mpv hwdec/vo settings', () {
    final SettingsHandler s = SettingsHandler.instance;
    s.altVideoPlayerHwAccel = true;
    s.altVideoPlayerVO = MpvVideoOutput.gpu;
    s.altVideoPlayerHWDEC = MpvHardwareDecoding.autoSafe;

    final VideoControllerConfiguration c = MediaKitEngineOptions.videoController(s);
    expect(c.enableHardwareAcceleration, isTrue);
    expect(c.vo, 'gpu');
    expect(c.hwdec, 'auto-safe');
    expect(c.androidAttachSurfaceAfterVideoParameters, isTrue);
  });

  test('libmpv vo does not force attach-after-params', () {
    final SettingsHandler s = SettingsHandler.instance;
    s.altVideoPlayerVO = MpvVideoOutput.libmpv;
    s.altVideoPlayerHWDEC = MpvHardwareDecoding.mediacodec;
    s.altVideoPlayerHwAccel = false;

    final VideoControllerConfiguration c = MediaKitEngineOptions.videoController(s);
    expect(c.vo, 'libmpv');
    expect(c.hwdec, 'mediacodec');
    expect(c.enableHardwareAcceleration, isFalse);
    expect(c.androidAttachSurfaceAfterVideoParameters, isNull);
  });

  test('native properties keep the in-memory cache and can add a disk dir', () {
    final Map<String, String> ram = MediaKitEngineOptions.nativeProperties();
    expect(ram['cache'], 'yes');
    expect(ram['cache-secs'], '30');
    expect(ram['demuxer-max-bytes'], '67108864');
    expect(ram['loop-file'], 'inf');
    expect(ram.containsKey('cache-dir'), isFalse);

    final Map<String, String> disk = MediaKitEngineOptions.nativeProperties(cacheDir: r'C:\tmp\mpv_cache');
    expect(disk['cache-on-disk'], 'yes');
    expect(disk['cache-dir'], r'C:\tmp\mpv_cache');
  });
}
