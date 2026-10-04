// The Android side of image_picker is reached through its platform packages,
// which image_picker itself depends on (no new package).
// ignore_for_file: depend_on_referenced_packages
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

/// r77: which picker "Try it on a picture" and a board's picture use.
///
/// Why Try it did nothing on 19 Sep is not proven. Android's own photo
/// picker opens inside the app's task (seen on the emulator) instead of
/// whichever app answers "pick an image", which removes one variable; the
/// log now says how each pick ended. (image_picker's README says a picker
/// started from a "single instance" screen always comes back cancelled, but
/// folder choosers have returned results to this very screen, so that note
/// is likely about older Android.)
class PhotoPicker {
  const PhotoPicker._();

  /// Whether [useSystemPicker] switched the photo picker on (for the log).
  static bool systemPickerOn = false;

  /// Switches image_picker to Android's photo picker; false off Android.
  static bool useSystemPicker([ImagePickerPlatform? platform]) {
    final ImagePickerPlatform p = platform ?? ImagePickerPlatform.instance;
    if (p is! ImagePickerAndroid) return false;
    p.useAndroidPhotoPicker = true;
    systemPickerOn = true;
    return true;
  }
}
