import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/models/blacklist_line.dart';

/// 1.0 (M2): `filesize:` blacklist terms with a unit after an operator or in
/// a range (`filesize:>5mb`, `filesize:1mb..2mb`) were read as 0, so
/// `filesize:>5mb` hid every post whose size was known.
void main() {
  bool hides(String line, int bytes) => parseBlacklistLine(line)!.matches(BlacklistContext(tags: const {}, fileSize: bytes));

  const int mb = 1024 * 1024;
  const int kb = 1024;

  test('filesize:>5mb hides posts over 5 MB only', () {
    expect(hides('filesize:>5mb', 6 * mb), isTrue);
    expect(hides('filesize:>5mb', 1 * mb), isFalse, reason: 'a 1 MB post is not over 5 MB');
  });

  test('every operator takes a unit, in either case', () {
    expect(hides('filesize:>=5MB', 5 * mb), isTrue);
    expect(hides('filesize:>=5MB', 5 * mb - 1), isFalse);
    expect(hides('filesize:<200kb', 100 * kb), isTrue);
    expect(hides('filesize:<200kb', 300 * kb), isFalse);
    expect(hides('filesize:<=1mb', mb), isTrue);
    expect(hides('filesize:=<1mb', mb + 1), isFalse);
    expect(hides('filesize:=>1mb', mb), isTrue);
    expect(hides('filesize:=2mb', 2 * mb), isTrue);
  });

  test('a range takes units on both ends', () {
    expect(hides('filesize:1mb..2mb', 1536 * kb), isTrue);
    expect(hides('filesize:1mb..2mb', 3 * mb), isFalse);
    expect(hides('filesize:1mb..2mb', 512 * kb), isFalse);
    expect(hides('filesize:100kb..1mb', 500 * kb), isTrue);
  });

  test('plain byte counts and a bare number with a unit work as before', () {
    expect(hides('filesize:>1000', 2000), isTrue);
    expect(hides('filesize:>1000', 500), isFalse);
    expect(hides('filesize:5mb', 5 * mb), isTrue);
    expect(hides('filesize:500..1500', 1000), isTrue);
  });

  test('other numeric terms are unchanged', () {
    expect(parseBlacklistLine('score:<0')!.matches(BlacklistContext(tags: const {}, score: '-3')), isTrue);
    expect(parseBlacklistLine('score:<0')!.matches(BlacklistContext(tags: const {}, score: '3')), isFalse);
    expect(parseBlacklistLine('width:>=1000')!.matches(BlacklistContext(tags: const {}, width: 1200)), isTrue);
    expect(parseBlacklistLine('id:10..20')!.matches(BlacklistContext(tags: const {}, id: '15')), isTrue);
  });
}
