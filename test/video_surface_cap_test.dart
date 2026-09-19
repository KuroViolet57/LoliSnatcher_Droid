import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:lolisnatcher/src/data/modular_ui.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/video/video_surface_cap.dart';

/// r59: our own copy of media_kit_video (third_party/media_kit_video) asks the
/// app for the surface size before it sets it, in the one place it already
/// does that. r57 instead resized the surface afterwards, which made the
/// plugin hand out a new surface and rebuild its whole video output, so
/// anything that needed scaling never played (§4.27).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const Size screen = Size(1440, 3120);

  setUp(() {
    SettingsHandler.register();
    SettingsHandler.instance.modularUi.clear();
    PlatformVideoController.androidSurfaceSizeCap = null;
  });

  tearDown(() {
    SettingsHandler.instance.modularUi.clear();
    PlatformVideoController.androidSurfaceSizeCap = null;
  });

  test('installing gives media_kit a size to use before it sizes the surface', () {
    expect(PlatformVideoController.androidSurfaceSizeCap, isNull);
    VideoSurfaceCap.install(screen: screen);
    expect(PlatformVideoController.androidSurfaceSizeCap, isNotNull);

    final Size Function(int, int) cap = PlatformVideoController.androidSurfaceSizeCap!;
    expect(cap(4320, 7680), const Size(1440, 2560), reason: '8K');
    expect(cap(3840, 2086), const Size(2650, 1440), reason: '4K');
  });

  test('videos the screen can show are handed back unchanged', () {
    VideoSurfaceCap.install(screen: screen);
    final Size Function(int, int) cap = PlatformVideoController.androidSurfaceSizeCap!;
    expect(cap(1920, 1080), const Size(1920, 1080));
    expect(cap(1280, 720), const Size(1280, 720));
  });

  test('with the switch off every video keeps its own size', () {
    VideoSurfaceCap.install(screen: screen);
    SettingsHandler.instance.modularUi[ModularUi.videoCapToScreen.key] = false;
    final Size Function(int, int) cap = PlatformVideoController.androidSurfaceSizeCap!;
    expect(cap(4320, 7680), const Size(4320, 7680));
  });

  test('the switch is read per video, so turning it off takes effect at once', () {
    VideoSurfaceCap.install(screen: screen);
    final Size Function(int, int) cap = PlatformVideoController.androidSurfaceSizeCap!;
    expect(cap(4320, 7680), const Size(1440, 2560));
    SettingsHandler.instance.modularUi[ModularUi.videoCapToScreen.key] = false;
    expect(cap(4320, 7680), const Size(4320, 7680));
    SettingsHandler.instance.modularUi[ModularUi.videoCapToScreen.key] = true;
    expect(cap(4320, 7680), const Size(1440, 2560));
  });

  test('the switch is on by default', () {
    expect(ModularUi.all, contains(ModularUi.videoCapToScreen));
    expect(ModularUi.isOn(ModularUi.videoCapToScreen), isTrue);
  });
}
