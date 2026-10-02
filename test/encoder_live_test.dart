@Tags(['live'])
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/handlers/recommender/encoder_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/wordpiece_tokenizer.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

/// r34, live: the English preset's vocabulary and tokenizer config come
/// down from Hugging Face through the real fetcher, the Dart tokenizer reads
/// them, and the model file is where the preset says, at the size it says.
/// Inference itself needs the ONNX runtime's native side and is verified on
/// the device, not here.
///
///   flutter test test/encoder_live_test.dart --run-skipped --tags live
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late Directory tempDir;

  setUp(() {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('encoder_live');
    SettingsHandler.instance
      ..path = '${tempDir.path}${Platform.pathSeparator}'
      ..dbEnabled = false;
    EncoderHandler.unregister();
    EncoderHandler.register();
  });

  tearDown(() {
    EncoderHandler.unregister();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('the English preset tokenizes what this app will feed it', () async {
    final EncoderHandler e = EncoderHandler.instance;
    final Directory dir = Directory(e.dirFor('english'))..createSync(recursive: true);
    final File vocab = File('${dir.path}vocab.txt');
    final File config = File('${dir.path}tokenizer_config.json');
    await e.fetcher(EncoderHandler.fileUrl(EncoderPreset.english.repo, 'vocab.txt'), vocab);
    await e.fetcher(EncoderHandler.fileUrl(EncoderPreset.english.repo, 'tokenizer_config.json'), config);
    expect(vocab.lengthSync(), 231508);
    final WordPieceTokenizer t = WordPieceTokenizer.fromVocabText(vocab.readAsStringSync());
    expect(t.vocab.length, 30522);
    final List<String> pieces = t.tokenize('Hu Tao, genshin impact, big breasts, nakadashi');
    // ignore: avoid_print
    print('pieces: $pieces');
    expect(pieces, isNot(contains('[UNK]')));
    expect(pieces.first, 'hu');
    expect(pieces, contains('impact'));
    expect(t.tokenize('日本語のタイトル'), isNot(contains('[UNK]')), reason: 'BERT uncased knows the ideographs and the kana');
    final TokenizedText enc = t.encode(EncoderHandler.textOfDoujinParts(title: 'Tales of Hu Tao', namespacedTags: ['parody:genshin_impact', 'female:big_breasts']), maxLength: 64);
    expect(enc.ids.first, t.clsId);
    expect(enc.ids.last, t.sepId);
    expect(enc.ids.length, enc.mask.length);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the model file is where the preset says, at the size it says', () async {
    for (final EncoderPreset preset in EncoderPreset.values) {
      final Response<void> head = await Dio().head<void>(
        EncoderHandler.fileUrl(preset.repo, EncoderHandler.modelFileName),
        options: Options(followRedirects: true, maxRedirects: 5, validateStatus: (s) => s != null && s < 400),
      );
      final String? length = head.headers.value('content-length') ?? head.headers.value('x-linked-size');
      // ignore: avoid_print
      print('${preset.repo}: status ${head.statusCode}, size $length (preset says ${preset.bytes})');
      expect(head.statusCode, lessThan(400));
      if (length != null) expect(int.parse(length), preset.bytes);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
