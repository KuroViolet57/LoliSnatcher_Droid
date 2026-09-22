// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import 'package:lolisnatcher/src/utils/photo_picker.dart';

/// r77: "Try it on a picture" did nothing on the phone (19 Sep); why is not
/// proven. Android's own photo picker opened inside the app's task on the
/// emulator and worked, so the app now always asks for that one - one
/// variable less.
void main() {
  test('on Android the system photo picker is switched on', () {
    final ImagePickerAndroid android = ImagePickerAndroid();
    expect(android.useAndroidPhotoPicker, isFalse, reason: "image_picker's default");
    expect(PhotoPicker.useSystemPicker(android), isTrue);
    expect(android.useAndroidPhotoPicker, isTrue);
  });

  test('as main() calls it: the registered Android picker is switched on, and the log can say so', () {
    final ImagePickerPlatform before = ImagePickerPlatform.instance;
    final ImagePickerAndroid android = ImagePickerAndroid();
    ImagePickerPlatform.instance = android;
    addTearDown(() {
      ImagePickerPlatform.instance = before;
      PhotoPicker.systemPickerOn = false;
    });
    PhotoPicker.systemPickerOn = false;
    expect(PhotoPicker.useSystemPicker(), isTrue);
    expect(android.useAndroidPhotoPicker, isTrue);
    expect(PhotoPicker.systemPickerOn, isTrue);
  });

  test('elsewhere nothing changes', () {
    expect(PhotoPicker.useSystemPicker(_OtherPicker()), isFalse);
  });
}

class _OtherPicker extends ImagePickerPlatform {}
