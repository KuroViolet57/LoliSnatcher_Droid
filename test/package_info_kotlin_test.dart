import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// package_info_plus 10.2.2 no longer adds src/main/kotlin to the Android
/// source set. A release assemble then compiles that module with no Kotlin
/// files, and the app cannot see PackageInfoPlugin.
void main() {
  test('package_info_plus release Kotlin compile includes its sources', () {
    final String gradle = File('android/build.gradle.kts').readAsStringSync();
    expect(gradle, contains("name != \"package_info_plus\""));
    expect(gradle, contains('src/main/kotlin'));
    expect(gradle, contains('setSource'));
  });
}
