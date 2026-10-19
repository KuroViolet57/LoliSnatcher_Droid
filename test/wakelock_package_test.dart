import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// wakelock_plus 1.7.0 ships Pigeon classes in the default Kotlin package.
/// Kotlin 2.2.20 will not import them into the plugin package, so the
/// release build fails. The vendored copy puts them in the plugin package.
void main() {
  test('vendored wakelock pigeon classes share the plugin package', () {
    const String root =
        'third_party/wakelock_plus/android/src/main/kotlin/dev/fluttercommunity/plus/wakelock';
    final File messages = File('$root/WakelockPlusMessages.g.kt');
    expect(messages.existsSync(), isTrue, reason: 'vendored wakelock is missing');
    expect(messages.readAsStringSync(), contains('package dev.fluttercommunity.plus.wakelock'));

    final String wake = File('$root/Wakelock.kt').readAsStringSync();
    final String plugin = File('$root/WakelockPlusPlugin.kt').readAsStringSync();
    expect(wake, isNot(contains('import IsEnabledMessage')));
    expect(wake, isNot(contains('import ToggleMessage')));
    expect(plugin, isNot(contains('import IsEnabledMessage')));
    expect(plugin, isNot(contains('import ToggleMessage')));
    expect(plugin, isNot(contains('import WakelockPlusApi')));

    final String spec = File('pubspec.yaml').readAsStringSync();
    expect(spec, contains('path: third_party/wakelock_plus'));
  });
}
