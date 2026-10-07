import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lolisnatcher/features/viewer/logic/info_sheet_body.dart';

void main() {
  test('a shut info sheet does not build the tag view', () {
    expect(infoSheetShowsTags(0), isFalse);
    expect(infoSheetShowsTags(0.33), isTrue);

    final String sheet = File(
      'lib/features/viewer/ui/info/item_info_bottom_sheet.dart',
    ).readAsStringSync();
    expect(sheet, contains('infoSheetShowsTags'));
    final int gate = sheet.indexOf('if (!infoSheetShowsTags(extent))');
    final int tags = sheet.indexOf('return TagView(');
    expect(gate, greaterThan(0));
    expect(tags, greaterThan(gate));
  });
}
