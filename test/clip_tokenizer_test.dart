import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/handlers/recommender/clip_tokenizer.dart';

/// r75: the CLIP byte-pair tokenizer in Dart, checked against a fixture cut
/// from the real MobileCLIP `tokenizer.json` (the vocab entries and merges
/// the sentences below touch, with the ids the reference implementation
/// produced; "a photo of a cat" = 320 1125 539 320 2368 is the encoding
/// every CLIP example prints).
void main() {
  late Map<String, dynamic> fixture;
  late ClipTokenizer tok;

  setUpAll(() {
    fixture = jsonDecode(File('test/fixtures/clip_tokenizer_small.json').readAsStringSync()) as Map<String, dynamic>;
    tok = ClipTokenizer.fromJson(fixture);
  });

  test('the known CLIP encoding: "a photo of a cat" is 320 1125 539 320 2368 between the start and end marks', () {
    expect(tok.encodeIds('a photo of a cat'), [49406, 320, 1125, 539, 320, 2368, 49407]);
    expect(tok.bos, 49406);
    expect(tok.eos, 49407);
    expect(tok.unk, 49407);
    expect(tok.maxLength, 77);
  });

  test('every fixture sentence encodes as the reference implementation says: case, punctuation, digits, underscores, accents, empty', () {
    final Map<String, dynamic> expected = fixture['expected'] as Map<String, dynamic>;
    expect(expected, isNotEmpty);
    expected.forEach((String sentence, dynamic ids) {
      expect(tok.encodeIds(sentence), List<int>.from(ids as List), reason: sentence);
    });
  });

  test('pieces: words apart from punctuation, one digit at a time, whitespace collapsed, lowercase, the end-of-word mark on the last piece', () {
    expect(tok.pieces('Two cats, one dog!'), ['two</w>', 'cats</w>', ',</w>', 'one</w>', 'dog</w>', '!</w>']);
    expect(tok.pieces('  a   photo\tof a\ncat '), ['a</w>', 'photo</w>', 'of</w>', 'a</w>', 'cat</w>']);
    expect(tok.pieces(''), isEmpty);
  });

  test('encode pads to the model length with a mask, keeps the end mark when truncating, maps unknown pieces to the unknown id', () {
    final ClipTokens t = tok.encode('a photo of a cat');
    expect(t.ids, hasLength(77));
    expect(t.mask, hasLength(77));
    expect(t.ids.sublist(0, 7), [49406, 320, 1125, 539, 320, 2368, 49407]);
    expect(t.ids.sublist(7), everyElement(0));
    expect(t.mask.sublist(0, 7), everyElement(1));
    expect(t.mask.sublist(7), everyElement(0));
    expect(t.length, 7);

    final ClipTokens long = tok.encode(List<String>.filled(60, 'cat').join(' '), maxLength: 10);
    expect(long.ids, hasLength(10));
    expect(long.ids.first, 49406);
    expect(long.ids.last, 49407);
    expect(long.ids.sublist(1, 9), everyElement(2368));
    expect(long.mask, everyElement(1));

    // An emoji: its bytes are pieces the small vocab does not hold.
    final List<int> unknown = tok.encodeIds('\u{1F600}');
    expect(unknown.first, 49406);
    expect(unknown.last, 49407);
    expect(unknown.sublist(1, unknown.length - 1), everyElement(tok.unk));
  });
}
