import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/handlers/recommender/wordpiece_tokenizer.dart';

/// r34: the BERT WordPiece tokenizer in Dart — what the downloaded encoder
/// reads. Mirrors HuggingFace's BertTokenizer: clean, split CJK ideographs
/// one per token, lowercase and strip accents (uncased models), split
/// punctuation, then greedy longest-match word pieces with `##`.
void main() {
  const String vocabText = '[PAD]\n[UNK]\n[CLS]\n[SEP]\nhu\ntao\ngen\n##shin\nimpact\nbig\n##s\nbreast\n!\n,\n日\n本\nHu\nTao\n##tao\n';

  test('the vocabulary is read in file order, one id per line, with the specials found by name', () {
    final WordPieceTokenizer t = WordPieceTokenizer.fromVocabText(vocabText);
    expect(t.padId, 0);
    expect(t.unkId, 1);
    expect(t.clsId, 2);
    expect(t.sepId, 3);
    expect(t.vocab['##shin'], 7);
    expect(t.vocab.length, 19);
  });

  test('uncased: lowercase, accents stripped, punctuation split, greedy pieces with ##, unknown words become [UNK]', () {
    final WordPieceTokenizer t = WordPieceTokenizer.fromVocabText(vocabText);
    expect(t.tokenize('Hù Tao'), ['hu', 'tao']);
    expect(t.tokenize('Genshin Impact!'), ['gen', '##shin', 'impact', '!']);
    expect(t.tokenize('big breasts, big'), ['big', 'breast', '##s', ',', 'big']);
    expect(t.tokenize('zzz'), ['[UNK]']);
    expect(t.tokenize('  \t\n '), isEmpty);
  });

  test('CJK ideographs are one token each, whatever surrounds them', () {
    final WordPieceTokenizer t = WordPieceTokenizer.fromVocabText(vocabText);
    expect(t.tokenize('日本tao'), ['日', '本', 'tao']);
    expect(WordPieceTokenizer.isCjk('日'.runes.first), isTrue);
    expect(WordPieceTokenizer.isCjk('た'.runes.first), isFalse, reason: 'kana are words, not ideographs — as in BERT');
    expect(WordPieceTokenizer.isCjk('a'.runes.first), isFalse);
  });

  test('cased: case and accents are kept', () {
    final WordPieceTokenizer t = WordPieceTokenizer.fromVocabText(vocabText, lowerCase: false);
    expect(t.tokenize('Hu Tao'), ['Hu', 'Tao']);
    expect(t.tokenize('hu tao'), ['hu', 'tao']);
    expect(t.tokenize('Hù'), ['[UNK]'], reason: 'no accent stripping in a cased model');
  });

  test('encode wraps in [CLS] … [SEP], truncates to maxLength keeping [SEP], and the mask is all ones', () {
    final WordPieceTokenizer t = WordPieceTokenizer.fromVocabText(vocabText);
    final TokenizedText e = t.encode('hu tao genshin impact', maxLength: 5);
    expect(e.ids, [2, 4, 5, 6, 3], reason: '[CLS] hu tao gen [SEP]');
    expect(e.mask, [1, 1, 1, 1, 1]);
    final TokenizedText full = t.encode('hu tao');
    expect(full.ids, [2, 4, 5, 3]);
    expect(t.encode('').ids, [2, 3]);
  });

  test('a long word beyond the piece limit is [UNK] as a whole, not a hundred pieces', () {
    final WordPieceTokenizer t = WordPieceTokenizer.fromVocabText('[PAD]\n[UNK]\n[CLS]\n[SEP]\na\n##a\n');
    expect(t.tokenize('aaaa'), ['a', '##a', '##a', '##a']);
    expect(t.tokenize('a' * 101), ['[UNK]']);
  });

  test('stripAccents drops marks the way NFD does: letters without a decomposition (Ð, ø, Æ) stay', () {
    expect(WordPieceTokenizer.stripAccents('Émilie Ðurić naïve señor Ærø Łódź'), 'Emilie Ðuric naive senor Ærø Łodz');
    expect(WordPieceTokenizer.stripAccents('café'), 'cafe', reason: 'a loose combining mark goes too');
  });
}
