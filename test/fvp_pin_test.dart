import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The resolved fvp pin. MDK playback itself is a phone check.
/// This fails while the lock is still 0.35.2.
void main() {
  test('fvp resolves to 0.39.0 and video_player stays on this SDK', () {
    final String lock = File('pubspec.lock').readAsStringSync();
    final Map<String, String> fvp = _lockFields(lock, 'fvp');
    expect(fvp['version'], '0.39.0');
    expect(
      fvp['sha256'],
      '2addef2e6faf46a589c529de8a81b74cef927c3343eb75aeab5e6a4715c97e8d',
    );

    // 2.12+ needs Flutter 3.44 and stable Dart 3.12. This tree is 3.42 beta.
    final Map<String, String> player = _lockFields(lock, 'video_player');
    expect(player['version'], '2.11.1');
    final Map<String, String> better = _lockFields(lock, 'better_player_plus');
    expect(better['version'], '1.4.1');

    final String spec = File('pubspec.yaml').readAsStringSync();
    expect(spec, contains('fvp: ^0.39.0'));
    expect(spec, contains('video_player: ^2.11.1'));
    expect(spec, contains('chewie: ^1.13.0'));
    expect(spec, contains('better_player_plus: ^1.4.1'));

    final String page = File('lib/features/settings/ui/video_page.dart').readAsStringSync();
    expect(page, contains('fvp.registerWith()'));
  });
}

Map<String, String> _lockFields(String lock, String package) {
  final Map<String, String> fields = {};
  var inside = false;
  for (final String line in lock.split('\n')) {
    final String row = line.endsWith('\r') ? line.substring(0, line.length - 1) : line;
    if (row == '  $package:') {
      inside = true;
      continue;
    }
    if (inside && row.startsWith('  ') && !row.startsWith('    ')) break;
    if (!inside) continue;
    final String trimmed = row.trim();
    for (final String key in ['version', 'sha256']) {
      final String prefix = '$key: ';
      if (trimmed.startsWith(prefix)) {
        fields[key] = trimmed.substring(prefix.length).replaceAll('"', '');
      }
    }
  }
  return fields;
}
