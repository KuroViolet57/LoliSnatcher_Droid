import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/data/settings/gallery_button.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

/// r61: the linked media button used to be the share button wearing a
/// different hat, so turning the share button off in Settings → Viewer →
/// interface took the link button with it. It is now a button of its own:
/// orderable, switchable, and independent of share.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('gallery_buttons');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('the toolbar has a linked media button of its own', () {
    expect(GalleryButton.values, contains(GalleryButton.linkedMedia));
    expect(GalleryButton.linkedMedia.isLinkedMedia, isTrue);
    expect(GalleryButton.share.isLinkedMedia, isFalse);
    expect(GalleryButton.linkedMedia.locName, isNotEmpty);
    expect(GalleryButton.linkedMedia.canBeDisabled, isTrue);
    expect(GalleryButton.disableable, contains(GalleryButton.linkedMedia));
  });

  test('it is stored and read back under its own name', () {
    expect(GalleryButton.linkedMedia.toJson(), 'linked_media');
    expect(GalleryButton.fromString('linked_media'), GalleryButton.linkedMedia);
    expect(GalleryButton.fromString('share'), GalleryButton.share);
  });

  test('a saved toolbar from before this build gains the button', () async {
    await SettingsHandler.instance.loadFromJSON(
      '{"buttonOrder": "snatch,favourite,info,share,select,open"}',
      false,
    );
    expect(SettingsHandler.instance.buttonOrder, contains(GalleryButton.linkedMedia));
    expect(SettingsHandler.instance.buttonOrder, contains(GalleryButton.share));
  });

  test('turning the share button off leaves the link button alone', () {
    final List<GalleryButton> order = [...SettingsHandler.instance.buttonOrder];
    final List<GalleryButton> disabled = [GalleryButton.share];
    final List<GalleryButton> shown = order.where((b) => !disabled.contains(b)).toList();

    expect(shown, contains(GalleryButton.linkedMedia));
    expect(shown, isNot(contains(GalleryButton.share)));
  });
}
