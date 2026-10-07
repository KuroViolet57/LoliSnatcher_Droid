import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The resolved better_player_plus pin. Playback itself is a phone check.
/// This fails while the lock is still 1.2.1.
void main() {
  test('better_player_plus resolves to 1.4.1 and the other players stay pinned', () {
    final String lock = File('pubspec.lock').readAsStringSync();
    final Map<String, String> player = _lockFields(lock, 'better_player_plus');
    expect(player['version'], '1.4.1');
    expect(
      player['sha256'],
      '49c02ec4d975cf0da3f55c3bf07a4eb3eeab2b417790d8fa3e29a77947cb02f1',
    );

    // 1.4.1 needs wakelock_plus ^1.7.0, which needs win32 6. device_info_plus
    // 12.4.0 is stuck on win32 5, so the resolver needs 13.x in the same bump.
    final Map<String, String> device = _lockFields(lock, 'device_info_plus');
    expect(device['version'], '13.3.0');
    expect(
      device['sha256'],
      'ade1c36f8355d6284c98e4a47992ea263887ed3d1acb281e37635dd45f04c4aa',
    );
    // share_plus 12 is the other win32 5 pin. Alice already calls SharePlus.
    final Map<String, String> share = _lockFields(lock, 'share_plus');
    expect(share['version'], '13.3.1');
    expect(
      share['sha256'],
      'db40767f130189d53f3ae8a6393c217ff4a492da1baff718a9873679c0c00224',
    );

    final String spec = File('pubspec.yaml').readAsStringSync();
    expect(spec, contains('better_player_plus: ^1.4.1'));
    expect(spec, contains('device_info_plus: ^13.3.0'));
    expect(spec, contains('share_plus: ^13.3.1'));
    expect(spec, contains('chewie: ^1.13.0'));
    expect(spec, contains('video_player: ^2.11.1'));
    expect(spec, contains('fvp: ^0.35.2'));
    expect(spec, contains('google_fonts: ^8.0.2'));

    final String view = File('lib/features/video/ui/better_player_view.dart').readAsStringSync();
    expect(view, contains('BetterPlayerController('));
    expect(view, contains('BetterPlayerDataSourceType.network'));
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
