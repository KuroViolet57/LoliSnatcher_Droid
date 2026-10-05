import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/constants.dart';

/// The in-app label and the package version are the same pair. versionCode
/// stays 5211 so this build can replace r89 and r89 can be put back over it.
void main() {
  test('1.0 keeps build 5211 and the label matches pubspec', () {
    expect(Constants.updateInfo.versionName, '1.0.0');
    expect(Constants.updateInfo.buildNumber, 5211);
    expect(Constants.buildCodename, 'v1.0-rebuild');
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('version: 1.0.0+5211'));
  });
}
