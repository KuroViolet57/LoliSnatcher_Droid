import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';

/// e621-style blacklist line.
///
/// A blacklist is a list of lines; a post is hidden if ANY line matches.
/// Each line is a space-separated list of tokens. Tokens are:
///   - `tag`      — must be present (AND)
///   - `-tag`     — must be absent (NOT)
///   - `~tag`     — at least one ~-token in the line must be present (OR)
///   - `key:val`  — metatag with optional operator (>, <, >=, <=, =, range `..`)
///
/// Lines starting with `#` are treated as comments and ignored.
///
/// Match semantics, mirroring e621:
///   - all `required` predicates must be true
///   - all `excluded` predicates must be false
///   - if any `oneOf` predicates exist, at least one must be true
///   - an empty line never matches
///
/// Examples (from the e621 docs):
///   `male solo`              → male AND solo
///   `-female`                → posts without female
///   `fox -wolf -lion`        → fox AND NOT wolf AND NOT lion
///   `~wolf ~lion`            → wolf OR lion
///   `-fox ~wolf ~lion`       → NOT fox AND (wolf OR lion)
///   `male ~wolf ~lion -fox`  → male AND (wolf OR lion) AND NOT fox
///   `rating:e female`        → explicit AND female
///   `score:<0`               → posts with score below zero
class BlacklistLine {
  BlacklistLine({
    required this.source,
    required this.required,
    required this.excluded,
    required this.oneOf,
  });

  /// The original raw string the user typed.
  final String source;
  final List<BlacklistPredicate> required;
  final List<BlacklistPredicate> excluded;
  final List<BlacklistPredicate> oneOf;

  bool get isEmpty => required.isEmpty && excluded.isEmpty && oneOf.isEmpty;

  bool matches(BlacklistContext ctx) {
    if (isEmpty) return false;
    for (final p in required) {
      if (!p.test(ctx)) return false;
    }
    for (final p in excluded) {
      if (p.test(ctx)) return false;
    }
    if (oneOf.isNotEmpty) {
      var anyMatch = false;
      for (final p in oneOf) {
        if (p.test(ctx)) {
          anyMatch = true;
          break;
        }
      }
      if (!anyMatch) return false;
    }
    return true;
  }

  /// Plain tag tokens referenced by this line — used by the UI to put a red
  /// eye-slash on tag chips that appear in the user's blacklist.
  Iterable<String> get plainTagTokens sync* {
    for (final p in [...required, ...oneOf]) {
      if (p is _TagPred) yield p.tag;
    }
  }
}

/// Context fed into [BlacklistLine.matches]. Built once per item.
class BlacklistContext {
  BlacklistContext({
    required this.tags,
    this.rating,
    this.id,
    this.score,
    this.uploaderName,
    this.uploaderId,
    this.width,
    this.height,
    this.fileSize,
  });

  factory BlacklistContext.fromItem(BooruItem item) {
    int? safeInt(String? s) => s == null ? null : int.tryParse(s);
    return BlacklistContext(
      tags: item.tagsList.map((Tag t) => t.fullString.toLowerCase()).toSet(),
      rating: item.rating?.toLowerCase(),
      id: item.serverId,
      score: item.score,
      uploaderName: item.uploaderName?.toLowerCase(),
      uploaderId: item.uploaderId,
      width: item.fileWidth?.toInt(),
      height: item.fileHeight?.toInt(),
      fileSize: safeInt(item.fileSize?.toString()),
    );
  }

  final Set<String> tags;
  final String? rating;
  final String? id;
  final String? score;
  final String? uploaderName;
  final String? uploaderId;
  final int? width;
  final int? height;
  final int? fileSize;
}

/// Parses a single blacklist entry into a [BlacklistLine].
/// Returns null for comments and empty inputs.
BlacklistLine? parseBlacklistLine(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed.startsWith('#')) return null;

  final tokens = trimmed.split(RegExp(r'\s+'));
  final required = <BlacklistPredicate>[];
  final excluded = <BlacklistPredicate>[];
  final oneOf = <BlacklistPredicate>[];

  for (final tok in tokens) {
    if (tok.isEmpty) continue;
    if (tok.length > 1 && tok.startsWith('-')) {
      excluded.add(_parseToken(tok.substring(1)));
    } else if (tok.length > 1 && tok.startsWith('~')) {
      oneOf.add(_parseToken(tok.substring(1)));
    } else {
      required.add(_parseToken(tok));
    }
  }

  final line = BlacklistLine(
    source: trimmed,
    required: required,
    excluded: excluded,
    oneOf: oneOf,
  );
  return line.isEmpty ? null : line;
}

List<BlacklistLine> parseBlacklist(Iterable<String> rawEntries) {
  final out = <BlacklistLine>[];
  for (final raw in rawEntries) {
    // A single stored entry may contain newlines (user can paste e621
    // blacklist verbatim); split and parse each.
    for (final line in raw.split('\n')) {
      final parsed = parseBlacklistLine(line);
      if (parsed != null) out.add(parsed);
    }
  }
  return out;
}

BlacklistPredicate _parseToken(String token) {
  final colon = token.indexOf(':');
  if (colon <= 0) {
    return _TagPred(token.toLowerCase());
  }
  final key = token.substring(0, colon).toLowerCase();
  final value = token.substring(colon + 1);
  // Only treat as a metatag if the key is one we recognize. Otherwise
  // (e.g. `foo:bar`) fall back to a literal tag match.
  if (!_knownMetaKeys.contains(key)) {
    return _TagPred(token.toLowerCase());
  }
  return _MetaPred(key, value);
}

const Set<String> _knownMetaKeys = {
  'rating',
  'id',
  'score',
  'user',
  'username',
  'uploader',
  'userid',
  'width',
  'height',
  'filesize',
};

// Two concrete subclasses (tag membership, metatag) share this contract; the
// abstract class is the right shape even though it only declares one method.
// ignore: one_member_abstracts
abstract class BlacklistPredicate {
  bool test(BlacklistContext ctx);
}

class _TagPred extends BlacklistPredicate {
  _TagPred(this.tag);
  final String tag;
  @override
  bool test(BlacklistContext ctx) => ctx.tags.contains(tag);
}

enum _Op { eq, lt, gt, le, ge, range }

class _MetaPred extends BlacklistPredicate {
  _MetaPred(this.key, String rawValue) {
    final parsed = _parseNumericValue(rawValue);
    op = parsed.op;
    numValues = parsed.values;
    stringValue = rawValue.toLowerCase();
  }

  final String key;
  late final _Op op;
  late final List<int> numValues;
  late final String stringValue;

  @override
  bool test(BlacklistContext ctx) {
    switch (key) {
      case 'rating':
        return _ratingMatches(ctx.rating, stringValue);
      case 'id':
        return _intCmp(int.tryParse(ctx.id ?? ''), op, numValues);
      case 'score':
        return _intCmp(int.tryParse(ctx.score ?? ''), op, numValues);
      case 'user':
      case 'username':
      case 'uploader':
        // e621 supports `uploader:!1234` to mean userid; we accept both forms.
        if (stringValue.startsWith('!')) {
          return ctx.uploaderId == stringValue.substring(1);
        }
        return ctx.uploaderName == stringValue;
      case 'userid':
        return ctx.uploaderId == stringValue;
      case 'width':
        return _intCmp(ctx.width, op, numValues);
      case 'height':
        return _intCmp(ctx.height, op, numValues);
      case 'filesize':
        return _intCmp(ctx.fileSize, op, _resolveFileSizeValues(numValues, stringValue));
    }
    return false;
  }

  List<int> _resolveFileSizeValues(List<int> base, String raw) {
    // Allow trailing `kb` / `mb` suffix on the original string.
    final m = RegExp(r'^([<>=!.\d]+)(kb|mb)?$').firstMatch(raw);
    if (m == null) return base;
    final multiplier = switch (m.group(2)) {
      'kb' => 1024,
      'mb' => 1024 * 1024,
      _ => 1,
    };
    if (multiplier == 1) return base;
    return base.map((v) => v * multiplier).toList();
  }
}

class _NumericParse {
  _NumericParse(this.op, this.values);
  final _Op op;
  final List<int> values;
}

_NumericParse _parseNumericValue(String raw) {
  // Range `a..b`
  final rangeIdx = raw.indexOf('..');
  if (rangeIdx > 0) {
    final lo = int.tryParse(raw.substring(0, rangeIdx)) ?? 0;
    final hi = int.tryParse(raw.substring(rangeIdx + 2)) ?? 0;
    return _NumericParse(_Op.range, [lo, hi]);
  }
  // Operator prefixes
  if (raw.startsWith('>=')) {
    return _NumericParse(_Op.ge, [int.tryParse(raw.substring(2)) ?? 0]);
  }
  if (raw.startsWith('<=')) {
    return _NumericParse(_Op.le, [int.tryParse(raw.substring(2)) ?? 0]);
  }
  if (raw.startsWith('=<')) {
    return _NumericParse(_Op.le, [int.tryParse(raw.substring(2)) ?? 0]);
  }
  if (raw.startsWith('=>')) {
    return _NumericParse(_Op.ge, [int.tryParse(raw.substring(2)) ?? 0]);
  }
  if (raw.startsWith('>')) {
    return _NumericParse(_Op.gt, [int.tryParse(raw.substring(1)) ?? 0]);
  }
  if (raw.startsWith('<')) {
    return _NumericParse(_Op.lt, [int.tryParse(raw.substring(1)) ?? 0]);
  }
  if (raw.startsWith('=')) {
    return _NumericParse(_Op.eq, [int.tryParse(raw.substring(1)) ?? 0]);
  }
  // Strip unit suffix (kb/mb) before parsing the bare integer.
  final stripped = raw.replaceAll(RegExp(r'(kb|mb)$', caseSensitive: false), '');
  return _NumericParse(_Op.eq, [int.tryParse(stripped) ?? 0]);
}

bool _intCmp(int? actual, _Op op, List<int> values) {
  if (actual == null || values.isEmpty) return false;
  switch (op) {
    case _Op.eq:
      return actual == values.first;
    case _Op.lt:
      return actual < values.first;
    case _Op.gt:
      return actual > values.first;
    case _Op.le:
      return actual <= values.first;
    case _Op.ge:
      return actual >= values.first;
    case _Op.range:
      if (values.length < 2) return false;
      return actual >= values[0] && actual <= values[1];
  }
}

bool _ratingMatches(String? actual, String value) {
  if (actual == null) return false;
  final a = actual.toLowerCase();
  final v = value.toLowerCase();
  // accept full word ("explicit") or first letter ("e")
  switch (v) {
    case 's':
    case 'safe':
    case 'general':
    case 'g':
      return a == 's' || a == 'safe' || a == 'g' || a == 'general';
    case 'q':
    case 'questionable':
      return a == 'q' || a == 'questionable';
    case 'e':
    case 'explicit':
      return a == 'e' || a == 'explicit';
  }
  return a == v;
}
