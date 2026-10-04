/// A BERT WordPiece tokenizer (r34), the reader of the downloaded encoder's
/// `vocab.txt`. It follows HuggingFace's `BertTokenizer`: clean the text,
/// put every CJK ideograph in a token of its own, lowercase and strip
/// accents (uncased models), split punctuation off, then cut each word into
/// the longest known pieces, continuation pieces prefixed `##`.
class TokenizedText {
  const TokenizedText(this.ids, this.mask);

  final List<int> ids;
  final List<int> mask;
}

class WordPieceTokenizer {
  WordPieceTokenizer({
    required this.vocab,
    this.lowerCase = true,
    String unk = '[UNK]',
    String cls = '[CLS]',
    String sep = '[SEP]',
    String pad = '[PAD]',
    this.maxWordChars = 100,
  }) : unkId = vocab[unk] ?? 1,
       clsId = vocab[cls] ?? 2,
       sepId = vocab[sep] ?? 3,
       padId = vocab[pad] ?? 0,
       _unk = unk;

  /// One piece per line, the line number its id — as HuggingFace reads it.
  factory WordPieceTokenizer.fromVocabText(String text, {bool lowerCase = true}) {
    final List<String> lines = text.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    final Map<String, int> vocab = {};
    for (int i = 0; i < lines.length; i++) {
      final String piece = lines[i].endsWith('\r') ? lines[i].substring(0, lines[i].length - 1) : lines[i];
      vocab.putIfAbsent(piece, () => i);
    }
    return WordPieceTokenizer(vocab: vocab, lowerCase: lowerCase);
  }

  final Map<String, int> vocab;
  final bool lowerCase;
  final int maxWordChars;
  final int unkId;
  final int clsId;
  final int sepId;
  final int padId;
  final String _unk;

  /// The word pieces of [text], no special tokens.
  List<String> tokenize(String text) {
    String s = _clean(text);
    if (lowerCase) s = stripAccents(s.toLowerCase());
    final List<String> out = [];
    for (final String word in s.split(' ')) {
      if (word.isEmpty) continue;
      for (final String piece in _splitPunctuation(word)) {
        out.addAll(_wordPieces(piece));
      }
    }
    return out;
  }

  /// `[CLS] pieces [SEP]`, at most [maxLength] ids, with an all-ones mask.
  TokenizedText encode(String text, {int maxLength = 128}) {
    final List<String> pieces = tokenize(text);
    final int room = (maxLength - 2).clamp(0, 1 << 20);
    final List<int> ids = [
      clsId,
      for (final String p in pieces.length > room ? pieces.sublist(0, room) : pieces) vocab[p] ?? unkId,
      sepId,
    ];
    return TokenizedText(ids, List<int>.filled(ids.length, 1));
  }

  List<String> _wordPieces(String word) {
    final List<int> chars = word.runes.toList();
    if (chars.length > maxWordChars) return [_unk];
    final List<String> out = [];
    int start = 0;
    while (start < chars.length) {
      int end = chars.length;
      String? found;
      while (start < end) {
        final String candidate = (start > 0 ? '##' : '') + String.fromCharCodes(chars.sublist(start, end));
        if (vocab.containsKey(candidate)) {
          found = candidate;
          break;
        }
        end--;
      }
      if (found == null) return [_unk];
      out.add(found);
      start = end;
    }
    return out;
  }

  static List<String> _splitPunctuation(String word) {
    final List<String> out = [];
    final StringBuffer current = StringBuffer();
    for (final int rune in word.runes) {
      if (isPunctuation(rune)) {
        if (current.isNotEmpty) {
          out.add(current.toString());
          current.clear();
        }
        out.add(String.fromCharCode(rune));
      } else {
        current.writeCharCode(rune);
      }
    }
    if (current.isNotEmpty) out.add(current.toString());
    return out;
  }

  /// Control characters dropped, every whitespace a space, ideographs
  /// spaced apart.
  static String _clean(String text) {
    final StringBuffer out = StringBuffer();
    for (final int rune in text.runes) {
      if (rune == 0 || rune == 0xFFFD || _isControl(rune)) continue;
      if (_isWhitespace(rune)) {
        out.write(' ');
      } else if (isCjk(rune)) {
        out
          ..write(' ')
          ..writeCharCode(rune)
          ..write(' ');
      } else {
        out.writeCharCode(rune);
      }
    }
    return out.toString();
  }

  static bool _isWhitespace(int r) => r == 0x20 || r == 0x09 || r == 0x0A || r == 0x0D || r == 0xA0 || r == 0x3000 || (r >= 0x2000 && r <= 0x200A);

  static bool _isControl(int r) => (r < 0x20 && r != 0x09 && r != 0x0A && r != 0x0D) || (r >= 0x7F && r < 0xA0) || (r >= 0x200B && r <= 0x200F) || r == 0xFEFF;

  /// A CJK ideograph (BERT's `_is_chinese_char`): kana and hangul are not.
  static bool isCjk(int r) =>
      (r >= 0x4E00 && r <= 0x9FFF) ||
      (r >= 0x3400 && r <= 0x4DBF) ||
      (r >= 0x20000 && r <= 0x2A6DF) ||
      (r >= 0x2A700 && r <= 0x2B73F) ||
      (r >= 0x2B740 && r <= 0x2B81F) ||
      (r >= 0x2B820 && r <= 0x2CEAF) ||
      (r >= 0xF900 && r <= 0xFAFF) ||
      (r >= 0x2F800 && r <= 0x2FA1F);

  /// ASCII non-alphanumerics (as BERT: symbols included) and Unicode
  /// punctuation blocks.
  static bool isPunctuation(int r) =>
      (r >= 33 && r <= 47) ||
      (r >= 58 && r <= 64) ||
      (r >= 91 && r <= 96) ||
      (r >= 123 && r <= 126) ||
      r == 0xA1 ||
      r == 0xA7 ||
      r == 0xAB ||
      r == 0xB6 ||
      r == 0xB7 ||
      r == 0xBB ||
      r == 0xBF ||
      (r >= 0x2010 && r <= 0x2027) ||
      (r >= 0x2030 && r <= 0x205E) ||
      (r >= 0x3001 && r <= 0x3003) ||
      (r >= 0x3008 && r <= 0x3011) ||
      (r >= 0x3014 && r <= 0x301F) ||
      r == 0x30FB ||
      (r >= 0xFF01 && r <= 0xFF0F) ||
      (r >= 0xFF1A && r <= 0xFF20) ||
      (r >= 0xFF3B && r <= 0xFF40) ||
      (r >= 0xFF5B && r <= 0xFF65);

  /// Accents removed the way BERT's NFD-then-drop-marks does it: letters
  /// that decompose into a base and a mark lose the mark; letters with no
  /// decomposition (ø, ð, æ, ł) stay. Loose combining marks are dropped too.
  static String stripAccents(String s) {
    final StringBuffer out = StringBuffer();
    for (final int rune in s.runes) {
      if (rune >= 0x300 && rune <= 0x36F) continue;
      final String? base = _decomposable[rune];
      if (base != null) {
        out.write(base);
      } else {
        out.writeCharCode(rune);
      }
    }
    return out.toString();
  }

  static final Map<int, String> _decomposable = _buildDecomposable();

  static Map<int, String> _buildDecomposable() {
    // Pairs "accented, base" over Latin-1 Supplement and Latin Extended-A.
    const String pairs = 'ÀAÁAÂAÃAÄAÅAÇCÈEÉEÊEËEÌIÍIÎIÏIÑNÒOÓOÔOÕOÖOÙUÚUÛUÜUÝY'
        'àaáaâaãaäaåaçcèeéeêeëeìiíiîiïiñnòoóoôoõoöoùuúuûuüuýyÿy'
        'ĀAāaĂAăaĄAąaĆCćcĈCĉcĊCċcČCčcĎDďdĒEēeĔEĕeĖEėeĘEęeĚEěe'
        'ĜGĝgĞGğgĠGġgĢGģgĤHĥhĨIĩiĪIīiĬIĭiĮIįiİIĴJĵjĶKķkĹLĺlĻLļlĽLľl'
        'ŃNńnŅNņnŇNňnŌOōoŎOŏoŐOőoŔRŕrŖRŗrŘRřrŚSśsŜSŝsŞSşsŠSšs'
        'ŢTţtŤTťtŨUũuŪUūuŬUŭuŮUůuŰUűuŲUųuŴWŵwŶYŷyŸYŹZźzŻZżzŽZžz';
    final List<int> runes = pairs.runes.toList();
    final Map<int, String> out = {};
    for (int i = 0; i + 1 < runes.length; i += 2) {
      out[runes[i]] = String.fromCharCode(runes[i + 1]);
    }
    return out;
  }
}
