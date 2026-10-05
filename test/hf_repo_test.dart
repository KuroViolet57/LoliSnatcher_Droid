import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/features/recommender/logic/ml/hf_repo.dart';

/// File lists captured 2026-10-05 from `https://huggingface.co/api/models/<repo>`
/// (siblings[].rfilename). HEAD of resolve/main confirmed which names exist.
void main() {
  test('a repo id, a trailing slash, and a Hugging Face link are the same repo', () {
    expect(HfRepo.parse('SmilingWolf/wd-vit-tagger-v3').repo!.id, 'SmilingWolf/wd-vit-tagger-v3');
    expect(HfRepo.parse('SmilingWolf/wd-vit-tagger-v3/').repo!.id, 'SmilingWolf/wd-vit-tagger-v3');
    expect(HfRepo.parse('  SmilingWolf/wd-vit-tagger-v3  ').repo!.id, 'SmilingWolf/wd-vit-tagger-v3');
    expect(HfRepo.parse('https://huggingface.co/SmilingWolf/wd-vit-tagger-v3').repo!.id, 'SmilingWolf/wd-vit-tagger-v3');
    expect(HfRepo.parse('https://huggingface.co/SmilingWolf/wd-vit-tagger-v3/').repo!.id, 'SmilingWolf/wd-vit-tagger-v3');
    expect(HfRepo.parse('https://huggingface.co/SmilingWolf/wd-vit-tagger-v3/tree/main').repo!.revision, 'main');
    expect(HfRepo.parse('https://www.huggingface.co/SmilingWolf/wd-vit-tagger-v3/blob/main/model.onnx').repo!.id, 'SmilingWolf/wd-vit-tagger-v3');
    expect(HfRepo.parse('https://hf.co/SmilingWolf/wd-vit-tagger-v3').repo!.id, 'SmilingWolf/wd-vit-tagger-v3');
    expect(HfRepo.parse('see https://huggingface.co/Xenova/clip-vit-base-patch32 thanks').repo!.id, 'Xenova/clip-vit-base-patch32');
    expect(HfRepo.parse('owner/model@7f6b584d0bd3f55c').repo!.revision, '7f6b584d0bd3f55c');
    expect(HfRepo.parse('SmilingWolf/wd-vit-tagger-v3\u00a0').repo!.id, 'SmilingWolf/wd-vit-tagger-v3');
  });

  test('a near-miss is not a repo, and the error still says owner/model', () {
    for (final String bad in [
      'not-a-repo',
      '',
      '   ',
      'https://github.com/SmilingWolf/wd-vit-tagger-v3',
      'https://huggingface.co.evil.com/SmilingWolf/wd-vit-tagger-v3',
      'https://nothuggingface.co/SmilingWolf/wd-vit-tagger-v3',
      'SmilingWolf/wd-vit-tagger-v3/model.onnx',
      'https://huggingface.co/SmilingWolf/wd-vit-tagger-v3 and https://hf.co/other/model',
    ]) {
      final HfParseResult parsed = HfRepo.parse(bad);
      expect(parsed.repo, isNull, reason: bad);
      expect(parsed.error, contains('owner/model'), reason: bad);
    }
  });

  test('a named revision is listed at /revision/, and the default branch is not', () {
    const String sha = 'e7da7f221d5bf496a48136c0cd264e630fe9fcc8';
    expect(HfRepo.listingUrl('openai-community/gpt2', null), 'https://huggingface.co/api/models/openai-community/gpt2');
    expect(HfRepo.listingUrl('openai-community/gpt2', 'main'), 'https://huggingface.co/api/models/openai-community/gpt2/revision/main');
    expect(HfRepo.listingUrl('openai-community/gpt2', sha), 'https://huggingface.co/api/models/openai-community/gpt2/revision/$sha');
    expect(HfRepo.listingUrl('openai-community/gpt2', '../secrets'), isNull);
    expect(HfRepo.missingOnDiskMessage('files:gone'), startsWith('This model was imported from a folder.'));
    expect(HfRepo.missingOnDiskMessage('"files:gone"'), startsWith('This model was imported from a folder.'));
    expect(HfRepo.missingOnDiskMessage('owner/model'), 'The model files are missing; download again.');
  });

  test('resolve uses the commit the API named, not a hard-coded main', () {
    expect(
      HfRepo.resolveUrl('sentence-transformers/all-MiniLM-L6-v2', '1110a243fdf4706b3f48f1d95db1a4f5529b4d41', 'onnx/model.onnx'),
      'https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/1110a243fdf4706b3f48f1d95db1a4f5529b4d41/onnx/model.onnx',
    );
  });

  // sentence-transformers/all-MiniLM-L6-v2 on 2026-10-05: onnx/model.onnx
  // (90,405,214 bytes) and onnx/model_qint8_arm64.onnx exist; HEAD of
  // onnx/model_quantized.onnx was 404. vocab.txt is present.
  test('an Optimum sentence model is the plain onnx/model.onnx, not the missing quantized name', () {
    const List<String> files = [
      'config.json',
      'onnx/model.onnx',
      'onnx/model_O1.onnx',
      'onnx/model_O4.onnx',
      'onnx/model_qint8_arm64.onnx',
      'onnx/model_qint8_avx512.onnx',
      'tokenizer.json',
      'tokenizer_config.json',
      'vocab.txt',
    ];
    final HfPlan plan = HfRepo.choose(HfKind.encoder, files);
    expect(plan.error, isNull);
    expect(plan.remote('model.onnx'), 'onnx/model.onnx');
    expect(plan.remote('vocab.txt'), 'vocab.txt');
    expect(plan.remote('tokenizer_config.json'), 'tokenizer_config.json');
    expect(plan.remote('config.json'), 'config.json');
    expect(plan.files.map((HfPlannedFile f) => f.local).last, 'model.onnx', reason: 'the large file is last');
  });

  test('a Xenova sentence model still prefers onnx/model_quantized.onnx', () {
    final HfPlan plan = HfRepo.choose(HfKind.encoder, const [
      'onnx/model.onnx',
      'onnx/model_quantized.onnx',
      'onnx/model_fp16.onnx',
      'vocab.txt',
      'tokenizer_config.json',
      'config.json',
    ]);
    expect(plan.remote('model.onnx'), 'onnx/model_quantized.onnx');
  });

  // Xenova/paraphrase-multilingual-MiniLM-L12-v2 on 2026-10-05: quantized
  // ONNX and tokenizer.json, no vocab.txt. tokenizer_config uses <s>, not
  // WordPiece [CLS].
  test('a sentence model without vocab.txt says so, and does not pretend tokenizer.json is enough', () {
    final HfPlan plan = HfRepo.choose(HfKind.encoder, const [
      'config.json',
      'onnx/model_quantized.onnx',
      'tokenizer.json',
      'tokenizer_config.json',
    ]);
    expect(plan.error, contains('vocab.txt'));
    expect(plan.error, contains('tokenizer.json'));
  });

  test('the image tagger takes model.onnx and selected_tags.csv, including one folder down', () {
    final HfPlan nested = HfRepo.choose(HfKind.tagger, const [
      'wd-vit/model.onnx',
      'wd-vit/model.onnx.data',
      'wd-vit/selected_tags.csv',
      'README.md',
    ]);
    expect(nested.error, isNull);
    expect(nested.remote('model.onnx'), 'wd-vit/model.onnx');
    expect(nested.remote('selected_tags.csv'), 'wd-vit/selected_tags.csv');
    expect(nested.remote('model.onnx.data'), 'wd-vit/model.onnx.data');

    final HfPlan root = HfRepo.choose(HfKind.tagger, const [
      'model.onnx',
      'nested/model.onnx',
      'selected_tags.csv',
    ]);
    expect(root.remote('model.onnx'), 'model.onnx');

    final HfPlan tags = HfRepo.choose(HfKind.tagger, const ['only/model.onnx', 'only/tags.csv']);
    expect(tags.remote('selected_tags.csv'), 'only/tags.csv');
  });

  test('two tagger models in one folder are refused by name', () {
    final HfPlan plan = HfRepo.choose(HfKind.tagger, const [
      'a/model.onnx',
      'b/model.onnx',
      'a/selected_tags.csv',
      'b/selected_tags.csv',
    ]);
    expect(plan.error, contains('Several'));
    expect(plan.error, contains('a/model.onnx'));
  });

  test('a tagger repo with no tag list names the onnx files it does have', () {
    final HfPlan plan = HfRepo.choose(HfKind.tagger, const ['model.onnx', 'config.json']);
    expect(plan.error, contains('selected_tags.csv'));
    expect(plan.error, contains('model.onnx'));
  });

  // Xenova/clip-vit-base-patch32 on 2026-10-05 has both the quantized halves
  // and the full-precision vision file. openai/clip-vit-base-patch32 has no ONNX.
  test('a CLIP repo uses the quantized halves and remembers the full-precision picture file', () {
    final HfPlan plan = HfRepo.choose(HfKind.look, const [
      'onnx/vision_model.onnx',
      'onnx/vision_model_quantized.onnx',
      'onnx/vision_model_fp16.onnx',
      'onnx/text_model.onnx',
      'onnx/text_model_quantized.onnx',
      'onnx/model.onnx',
      'tokenizer.json',
      'preprocessor_config.json',
      'config.json',
    ]);
    expect(plan.error, isNull);
    expect(plan.remote('vision_model.onnx'), 'onnx/vision_model_quantized.onnx');
    expect(plan.remote('text_model.onnx'), 'onnx/text_model_quantized.onnx');
    expect(plan.remote('tokenizer.json'), 'tokenizer.json');
    expect(plan.npuRemote, 'onnx/vision_model.onnx');
  });

  test('a CLIP repo with only the full-precision halves still imports', () {
    final HfPlan plan = HfRepo.choose(HfKind.look, const [
      'onnx/vision_model.onnx',
      'onnx/text_model.onnx',
      'tokenizer.json',
    ]);
    expect(plan.remote('vision_model.onnx'), 'onnx/vision_model.onnx');
    expect(plan.npuRemote, isNull);
  });

  test('the official CLIP repo, which has no ONNX, says which files are missing', () {
    final HfPlan plan = HfRepo.choose(HfKind.look, const [
      'config.json',
      'preprocessor_config.json',
      'tokenizer.json',
      'tokenizer_config.json',
      'vocab.json',
    ]);
    expect(plan.error, contains('vision_model'));
    expect(plan.error, contains('tokenizer.json'));
  });

  test('a folder index keeps root files and one level of directories', () {
    final Map<String, String> indexed = HfRepo.indexFolder(
      const [
        HfFolderFile('model.onnx', false, 'u-model'),
        HfFolderFile('onnx', true, 'u-onnx'),
        HfFolderFile('notes', true, 'u-notes'),
      ],
      const {
        'onnx': [HfFolderFile('model_quantized.onnx', false, 'u-quant')],
        'notes': [HfFolderFile('readme.md', false, 'u-readme')],
      },
    );
    expect(indexed, {
      'model.onnx': 'u-model',
      'onnx/model_quantized.onnx': 'u-quant',
      'notes/readme.md': 'u-readme',
    });
  });

  test('paths that would escape the model directory are ignored', () {
    final HfPlan plan = HfRepo.choose(HfKind.tagger, const [
      '../model.onnx',
      'model.onnx',
      r'selected_tags.csv\..\x',
      'selected_tags.csv',
    ]);
    expect(plan.remote('model.onnx'), 'model.onnx');
    expect(plan.remote('selected_tags.csv'), 'selected_tags.csv');
  });
}
