import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/data/modular_ui.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/video/video_surface_cap.dart';

/// r57: the app asks media_kit's own platform channel to resize the video
/// surface after the plugin has set it to the video's native size, and tells
/// mpv to render at that size. media_kit_video has no API for this on Android
/// (`setSize` throws, its width/height config is desktop-only), so the app
/// makes the same call the plugin makes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const Size screen = Size(1440, 3120);
  late List<MethodCall> calls;
  late List<String> properties;

  setUp(() {
    SettingsHandler.register();
    SettingsHandler.instance.modularUi.clear();
    calls = [];
    properties = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      VideoSurfaceCap.channel,
      (call) async {
        calls.add(call);
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      VideoSurfaceCap.channel,
      null,
    );
    SettingsHandler.instance.modularUi.clear();
  });

  Future<void> setProperty(String key, String value) async => properties.add('$key=$value');

  test('an 8K video resizes the surface and tells mpv the new size', () async {
    final Size? applied = await VideoSurfaceCap.applyTo(
      handle: 1234,
      source: const Size(4320, 7680),
      screen: screen,
      enabled: true,
      setProperty: setProperty,
    );

    expect(applied, const Size(1440, 2560));
    expect(calls, hasLength(1));
    expect(calls.single.method, 'VideoOutputManager.SetSurfaceSize');
    expect(calls.single.arguments, {'handle': '1234', 'width': '1440', 'height': '2560'});
    expect(properties, ['android-surface-size=1440x2560']);
  });

  test('a video the screen can show is left to the plugin', () async {
    final Size? applied = await VideoSurfaceCap.applyTo(
      handle: 1234,
      source: const Size(1920, 1080),
      screen: screen,
      enabled: true,
      setProperty: setProperty,
    );

    expect(applied, isNull);
    expect(calls, isEmpty);
    expect(properties, isEmpty);
  });

  test('with the switch off nothing is touched', () async {
    final Size? applied = await VideoSurfaceCap.applyTo(
      handle: 1234,
      source: const Size(4320, 7680),
      screen: screen,
      enabled: false,
      setProperty: setProperty,
    );

    expect(applied, isNull);
    expect(calls, isEmpty);
    expect(properties, isEmpty);
  });

  test('a video size that is not known yet is left alone', () async {
    final Size? applied = await VideoSurfaceCap.applyTo(
      handle: 1234,
      source: Size.zero,
      screen: screen,
      enabled: true,
      setProperty: setProperty,
    );

    expect(applied, isNull);
    expect(calls, isEmpty);
  });

  test('both switches are on by default', () {
    expect(ModularUi.all, contains(ModularUi.videoCapToScreen));
    expect(ModularUi.all, contains(ModularUi.imageCap4k));
    expect(ModularUi.isOn(ModularUi.videoCapToScreen), isTrue);
    expect(ModularUi.isOn(ModularUi.imageCap4k), isTrue);
  });
}
