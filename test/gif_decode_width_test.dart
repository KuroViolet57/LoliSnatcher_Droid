import 'package:flutter_test/flutter_test.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/gif_decode_width.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  int? width({
    bool disableImageScaling = false,
    bool noScale = false,
    bool zoomed = false,
    double screenWidthCss = 400,
    double devicePixelRatio = 3,
    double? fileWidth = 4000,
  }) {
    return gifDecodeWidth(
      disableImageScaling: disableImageScaling,
      noScale: noScale,
      zoomed: zoomed,
      screenWidthCss: screenWidthCss,
      devicePixelRatio: devicePixelRatio,
      fileWidth: fileWidth,
    );
  }

  test('a resting GIF decodes at the screen, and a zoom decodes at twice that', () {
    expect(width(), 1200);
    expect(width(zoomed: true), 2400);
    expect(width(zoomed: true, fileWidth: 1500), 1500);
    expect(width(fileWidth: 100), 100);
    expect(width(fileWidth: 40), 64);
    expect(width(zoomed: true, fileWidth: null), 2400);
    expect(width(zoomed: true, fileWidth: 0), 2400);
    expect(width(screenWidthCss: 10, devicePixelRatio: 1, fileWidth: null), 64);
  });

  test('full-file decode stays behind the existing scaling switches', () {
    expect(width(disableImageScaling: true, zoomed: true), isNull);
    expect(width(noScale: true, zoomed: true), isNull);
    expect(width(disableImageScaling: true), isNull);
  });

  test('a settings file that omits fast GIF playback starts on, and a saved false stays off', () {
    final SettingsHandler fresh = SettingsHandler();
    expect(fresh.fastGifPlayback, isTrue);
    expect(fresh.map['fastGifPlayback']!['default'], isTrue);
    fresh.setByString('fastGifPlayback', false);
    expect(fresh.fastGifPlayback, isFalse);
  });
}
