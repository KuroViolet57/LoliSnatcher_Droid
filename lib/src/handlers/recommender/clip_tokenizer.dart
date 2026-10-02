import 'dart:convert';

/// The CLIP byte-pair tokenizer (r75), as a Hugging Face `tokenizer.json`
/// describes it: whitespace collapsed and lowercased, words split from
/// punctuation (one digit at a time), each word's bytes mapped to the
/// byte-level alphabet, merged by rank with `</w>` on a word's last piece,
/// then `<|startoftext|>` … `<|endoftext|>`, padded to the model length
/// with a mask. Checked against the encoding every CLIP example prints:
/// "a photo of a cat" = 320 1125 539 320 2368.
class ClipTokens {
  const ClipTokens(this.ids, this.mask);

  final List<int> ids;
  final List<int> mask;

  /// How many positions are real tokens (start and end marks included).
  int get length => mask.where((int m) => m == 1).length;
}

class ClipTokenizer {
  ClipTokenizer({
    required Map<String, int> vocab,
    required List<String> merges,
    this.eow = '</w>',
    required this.bos,
    required this.eos,
    required this.unk,
    this.maxLength = 77,
  }) : _vocab = vocab,
       _ranks = {for (int i = 0; i < merges.length; i++) merges[i]: i};

  factory ClipTokenizer.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> model = json['model'] as Map<String, dynamic>;
    final Map<String, int> vocab = {for (final MapEntry<String, dynamic> e in (model['vocab'] as Map).cast<String, dynamic>().entries) e.key: (e.value as num).toInt()};
    final List<String> merges = [for (final dynamic m in (model['merges'] as List? ?? const [])) m is String ? m : (m as List).join(' ')];
    int bos = 49406;
    int eos = 49407;
    for (final dynamic t in json['added_tokens'] as List? ?? const []) {
      if (t is! Map) continue;
      if (t['content'] == '<|startoftext|>' && t['id'] is num) bos = (t['id'] as num).toInt();
      if (t['content'] == '<|endoftext|>' && t['id'] is num) eos = (t['id'] as num).toInt();
    }
    bos = vocab['<|startoftext|>'] ?? bos;
    eos = vocab['<|endoftext|>'] ?? eos;
    final String unkToken = model['unk_token']?.toString() ?? '<|endoftext|>';
    return ClipTokenizer(
      vocab: vocab,
      merges: merges,
      eow: model['end_of_word_suffix']?.toString() ?? '</w>',
      bos: bos,
      eos: eos,
      unk: vocab[unkToken] ?? eos,
      maxLength: 77,
    );
  }

  static ClipTokenizer fromJsonText(String text) => ClipTokenizer.fromJson(jsonDecode(text) as Map<String, dynamic>);

  final Map<String, int> _vocab;
  final Map<String, int> _ranks;
  final String eow;
  final int bos;
  final int eos;
  final int unk;
  final int maxLength;
  final Map<String, List<String>> _cache = {};

  int get vocabSize => _vocab.length;

  /// The pre-tokenizer's pattern: contractions, runs of letters, one digit,
  /// runs of anything else that is not whitespace.
  static final RegExp _split = RegExp(r"'s|'t|'re|'ve|'m|'ll|'d|\p{L}+|\p{N}|[^\s\p{L}\p{N}]+", unicode: true);

  static final Map<int, String> _byteToChar = _bytesToUnicode();

  /// GPT-2's byte-to-unicode table: printable bytes stay themselves, the
  /// rest are moved above 255 so every byte is a printable character.
  static Map<int, String> _bytesToUnicode() {
    final List<int> bs = [
      for (int b = 33; b <= 126; b++) b,
      for (int b = 161; b <= 172; b++) b,
      for (int b = 174; b <= 255; b++) b,
    ];
    final List<int> cs = List<int>.of(bs);
    int n = 0;
    for (int b = 0; b < 256; b++) {
      if (!bs.contains(b)) {
        bs.add(b);
        cs.add(256 + n);
        n++;
      }
    }
    return {for (int i = 0; i < bs.length; i++) bs[i]: String.fromCharCode(cs[i])};
  }

  /// The words of [text] in the byte-level alphabet, lowercase.
  List<String> words(String text) {
    final String t = text.replaceAll(RegExp(r'\s+'), ' ').toLowerCase().trim();
    if (t.isEmpty) return const [];
    return [
      for (final RegExpMatch m in _split.allMatches(t)) [for (final int b in utf8.encode(m.group(0)!)) _byteToChar[b]!].join(),
    ];
  }

  /// The byte-pair pieces of [text], each word's last piece ending in [eow].
  List<String> pieces(String text) => [for (final String w in words(text)) ..._bpe(w)];

  List<String> _bpe(String word) {
    final List<String>? hit = _cache[word];
    if (hit != null) return hit;
    List<String> symbols = [for (final int r in word.runes) String.fromCharCode(r)];
    if (symbols.isEmpty) return const [];
    symbols[symbols.length - 1] = symbols.last + eow;
    while (symbols.length > 1) {
      int? bestRank;
      int bestAt = -1;
      for (int i = 0; i + 1 < symbols.length; i++) {
        final int? r = _ranks['${symbols[i]} ${symbols[i + 1]}'];
        if (r != null && (bestRank == null || r < bestRank)) {
          bestRank = r;
          bestAt = i;
        }
      }
      if (bestRank == null) break;
      final String a = symbols[bestAt];
      final String b = symbols[bestAt + 1];
      final List<String> merged = [];
      int i = 0;
      while (i < symbols.length) {
        if (i + 1 < symbols.length && symbols[i] == a && symbols[i + 1] == b) {
          merged.add(a + b);
          i += 2;
        } else {
          merged.add(symbols[i]);
          i++;
        }
      }
      symbols = merged;
    }
    if (_cache.length > 4096) _cache.clear();
    _cache[word] = symbols;
    return symbols;
  }

  /// The ids with the start and end marks, unpadded.
  List<int> encodeIds(String text) => [bos, for (final String p in pieces(text)) _vocab[p] ?? unk, eos];

  /// The ids padded (with 0) to [maxLength] and their mask; a long text is
  /// cut so the end mark stays last.
  ClipTokens encode(String text, {int? maxLength}) {
    final int n = maxLength ?? this.maxLength;
    List<int> ids = encodeIds(text);
    if (ids.length > n) ids = [...ids.sublist(0, n - 1), eos];
    final List<int> mask = [for (int i = 0; i < n; i++) i < ids.length ? 1 : 0];
    return ClipTokens([...ids, for (int i = ids.length; i < n; i++) 0], mask);
  }
}
