part of '../hitomi_handler.dart';

/// Raised whenever hitomi's own data formats stop looking like what this
/// handler knows how to read.
///
/// hitomi derives its image hosts from a rotating script (`gg.js`) and does
/// its searching against packed binary indexes. Both are unversioned and both
/// have changed shape before. Every parser in this file therefore validates
/// what it got and throws this rather than quietly producing a URL that 404s
/// or an id list that is really misaligned garbage - a visible "hitomi changed"
/// message is recoverable by updating the app, silently broken images are not.
class HitomiFormatException implements Exception {
  const HitomiFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The parsed contents of `https://ltn.gold-usergeneratedcontent.net/gg.js`.
///
/// The live script is ~22KB of generated JavaScript in a fixed shape:
///
/// ```js
/// gg = { m: function(g) {
///   var o = 1;
///   switch (g) { case 3344: case 3993: ... o = 0; break; }
///   return o;
/// },
/// s: function(h) { var m = /(..)(.)$/.exec(h); return parseInt(m[2]+m[1], 16).toString(10); },
/// b: '1788094801/' };
/// ```
///
/// It is a lookup table wearing a switch statement, so it is read with a
/// tokeniser rather than by running JavaScript. `b` rotates roughly daily and
/// the case list is reshuffled with it, so the script is re-fetched rather
/// than baked in.
@immutable
class HitomiGg {
  const HitomiGg({required this.b, required this.defaultM, required this.overrides});

  /// The rotating path prefix, e.g. `1788094801/`. Always carries its slash.
  final String b;

  /// `var o = <n>` - the value returned for any key not in the switch.
  final int defaultM;

  /// The `case <key>: ... o = <n>` table.
  final Map<int, int> overrides;

  /// `gg.m(g)` - picks which mirror serves a given key.
  int m(int g) => overrides[g] ?? defaultM;

  /// `gg.s(h)` - the JS is `/(..)(.)$/.exec(h)` then `parseInt(m[2]+m[1], 16)`,
  /// i.e. the last character of the hash is read as the HIGH nibble-pair and
  /// the two before it as the low ones. Getting this order backwards yields a
  /// plausible-looking number and a dead URL, so it is spelled out here.
  static int subdomainKey(String hash) {
    if (hash.length < 3 || !_hexOnly.hasMatch(hash)) {
      throw HitomiFormatException(
        'hitomi.la gave a page hash this app cannot read ("$hash"). '
        'Image URLs cannot be derived until the app is updated.',
      );
    }
    final String reordered = hash[hash.length - 1] + hash.substring(hash.length - 3, hash.length - 1);
    final int? value = int.tryParse(reordered, radix: 16);
    if (value == null) {
      throw HitomiFormatException('hitomi.la page hash "$hash" is not hexadecimal.');
    }
    return value;
  }

  static final RegExp _hexOnly = RegExp(r'^[0-9a-f]+$');

  /// `gg.b + gg.s(hash) + '/' + hash`
  String pathFor(String hash) => '$b${subdomainKey(hash)}/$hash';

  static final RegExp _bPattern = RegExp(r'''b:\s*['"]([^'"]*)['"]''');
  static final RegExp _defaultPattern = RegExp(r'var\s+o\s*=\s*(\d+)\s*;');
  static final RegExp _tokenPattern = RegExp(r'case\s+(\d+)\s*:|o\s*=\s*(\d+)\s*;\s*break\s*;');

  /// Reads a gg.js body. Throws [HitomiFormatException] the moment anything
  /// required is missing, rather than falling back to a guess.
  static HitomiGg parse(String source) {
    const String prefix = 'hitomi.la changed how it derives image URLs';

    final String? rawB = _bPattern.firstMatch(source)?.group(1);
    if (rawB == null || rawB.trim().isEmpty) {
      throw const HitomiFormatException(
        '$prefix (gg.js no longer declares a "b" path prefix). '
        'Images cannot be loaded until the app is updated.',
      );
    }
    final String b = rawB.endsWith('/') ? rawB : '$rawB/';

    final String? rawDefault = _defaultPattern.firstMatch(source)?.group(1);
    if (rawDefault == null) {
      throw const HitomiFormatException(
        '$prefix (gg.js no longer declares a default mirror). '
        'Images cannot be loaded until the app is updated.',
      );
    }
    final int defaultM = int.parse(rawDefault);

    // The switch is flat - runs of `case N:` share the assignment that follows
    // them - so accumulate keys and flush them when an assignment appears.
    final Map<int, int> overrides = {};
    final List<int> pending = [];
    for (final match in _tokenPattern.allMatches(source)) {
      final String? caseKey = match.group(1);
      if (caseKey != null) {
        pending.add(int.parse(caseKey));
        continue;
      }
      final int value = int.parse(match.group(2)!);
      for (final key in pending) {
        overrides[key] = value;
      }
      pending.clear();
    }

    if (overrides.isEmpty) {
      throw const HitomiFormatException(
        '$prefix (gg.js no longer contains a mirror table). '
        'Images cannot be loaded until the app is updated.',
      );
    }

    return HitomiGg(b: b, defaultM: defaultM, overrides: overrides);
  }
}
