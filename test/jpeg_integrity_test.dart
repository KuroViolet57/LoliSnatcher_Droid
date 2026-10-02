import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'dart:ui' as ui;

import 'package:lolisnatcher/src/widgets/image/custom_network_image.dart';

/// Round 6 item 1.
///
/// Every erocdn image ends `FF D9 53 4E` — the JPEG EOI marker followed by a
/// two-byte "SN" signature. The integrity check read the FINAL two bytes and
/// demanded they be `FF D9`, so it rejected every one of them as truncated.
/// That single assumption produced all 2,141 thumbnail errors in the device log
/// and killed the reader's first page.
///
/// The fixture below is a real, unmodified response from hikari.erocdn.net.
/// Testing against a hand-made byte array would have missed this, because the
/// bug is in what the server actually sends.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Uint8List real = File('test/fixtures/erocdn_thumbnail.jpg').readAsBytesSync();

  group('the fixture is the real thing', () {
    test('it is a genuine erocdn response, EOI not last', () {
      // If this ever fails the fixture was re-saved wrong and every assertion
      // below becomes meaningless.
      expect(real.length, greaterThan(20000));
      expect(real.sublist(0, 2), [0xFF, 0xD8], reason: 'not a JPEG');
      expect(
        real.sublist(real.length - 4),
        [0xFF, 0xD9, 0x53, 0x4E],
        reason: 'fixture no longer ends EOI + "SN"',
      );
      // The precise property the old check got wrong.
      expect(
        real.sublist(real.length - 2),
        isNot([0xFF, 0xD9]),
        reason: 'this file DOES end at EOI, so it cannot demonstrate the bug',
      );
    });

    test('and it genuinely decodes — it was never actually truncated', () async {
      // The strongest available falsifier: if these bytes really were damaged,
      // rejecting them would have been correct and this fix would be wrong.
      final codec = await ui.instantiateImageCodec(real);
      final frame = await codec.getNextFrame();

      expect(frame.image.width, greaterThan(0));
      expect(frame.image.height, greaterThan(0));
      // The size niyaniya declares for a 320 thumbnail.
      expect(frame.image.width, 320);
    });
  });

  group('the validator', () {
    test('accepts the real erocdn bytes', () {
      expect(hasJpegEndMarker(real), isTrue);
    });

    test('accepts a JPEG that does end exactly at EOI', () {
      expect(hasJpegEndMarker([0x00, 0x11, 0xFF, 0xD9]), isTrue);
    });

    test('still rejects a genuinely truncated file', () {
      // The check has to keep earning its place: a JPEG cut off mid-scan has no
      // EOI anywhere, and accepting it would show a half-painted image.
      final Uint8List cut = Uint8List.sublistView(real, 0, 5000);
      expect(hasJpegEndMarker(cut), isFalse);
    });

    test('rejects a file whose EOI was cut off but keeps its trailer', () {
      // The nastiest case: bytes that LOOK like they have a trailer but lost
      // the marker itself.
      expect(hasJpegEndMarker([0x00, 0x11, 0x22, 0x53, 0x4E]), isFalse);
    });

    test('is not fooled by the two halves of EOI landing apart', () {
      expect(hasJpegEndMarker([0xD9, 0xFF]), isFalse);
      expect(hasJpegEndMarker([0xFF, 0x00, 0xD9]), isFalse);
    });

    test('handles inputs too short to hold a marker', () {
      expect(hasJpegEndMarker(const []), isFalse);
      expect(hasJpegEndMarker(const [0xFF]), isFalse);
    });

    test('the tail window is big enough for a real trailer, small enough to be cheap', () {
      expect(jpegTailWindow, greaterThanOrEqualTo(1024));
      expect(jpegTailWindow, lessThanOrEqualTo(64 * 1024));
      // And the real file's EOI sits inside it.
      expect(real.length - real.lastIndexOf(0xD9), lessThan(jpegTailWindow));
    });
  });
}
