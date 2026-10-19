import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/recommender/logic/ml/encoder_handler.dart';
import 'package:lolisnatcher/features/recommender/logic/ml/image_tagger_handler.dart';
import 'package:lolisnatcher/features/recommender/logic/ml/look_model_handler.dart';

/// A folder import whose files are gone must not tell the user to press
/// Download. That button is off, and the only recovery is Import from a folder.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('missing-model');
    SettingsHandler.register();
    SettingsHandler.instance
      ..path = '${temp.path}${Platform.pathSeparator}'
      ..dbEnabled = false
      ..encoderModel = ''
      ..imageTaggerModel = ''
      ..lookModel = '';
    EncoderHandler.unregister();
    ImageTaggerHandler.unregister();
    LookModelHandler.unregister();
    EncoderHandler.register();
    ImageTaggerHandler.register();
    LookModelHandler.register();
  });

  tearDown(() {
    EncoderHandler.unregister();
    ImageTaggerHandler.unregister();
    LookModelHandler.unregister();
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  });

  const String folder = 'This model was imported from a folder.';
  const String downloadAgain = 'The model files are missing; download again.';

  test('a missing folder import explains itself on every model', () async {
    SettingsHandler.instance.encoderModel = 'files:gone';
    await EncoderHandler.instance.refresh();
    expect(EncoderHandler.instance.status.value.message, startsWith(folder));

    SettingsHandler.instance.imageTaggerModel = '"files:gone"';
    await ImageTaggerHandler.instance.refresh();
    expect(ImageTaggerHandler.instance.status.value.message, startsWith(folder));

    SettingsHandler.instance.lookModel = '\u200bfiles:gone';
    await LookModelHandler.instance.refresh();
    expect(LookModelHandler.instance.status.value.message, startsWith(folder));
  });

  test('a missing Hugging Face repo still says to download again', () async {
    SettingsHandler.instance.encoderModel = 'owner/model';
    await EncoderHandler.instance.refresh();
    expect(EncoderHandler.instance.status.value.message, downloadAgain);

    SettingsHandler.instance.imageTaggerModel = 'owner/model';
    await ImageTaggerHandler.instance.refresh();
    expect(ImageTaggerHandler.instance.status.value.message, downloadAgain);

    SettingsHandler.instance.lookModel = 'owner/model';
    await LookModelHandler.instance.refresh();
    expect(LookModelHandler.instance.status.value.message, downloadAgain);
  });
}
