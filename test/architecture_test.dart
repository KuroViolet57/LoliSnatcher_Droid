import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The 1.0 layer rule (docs/ARCHITECTURE.md):
///
///   models  <  core  <  sources  <  features/*/logic  <  features/*/ui  <  app
///
/// A file may import its own layer and the layers to its left, never one to
/// its right. `lib/gen` (translations) may be imported from anywhere.
///
/// The imports that broke the rule when the app was restructured are listed
/// in test/architecture_allowlist.txt, one `from -> to` per line. The list
/// may only shrink: a new violation fails this test, and so does a listed
/// line that is no longer a violation (delete it).
void main() {
  test('no import points from a lower layer to a higher one', () {
    final Map<String, List<String>> imports = _libImports();
    final Set<String> found = {};
    imports.forEach((String from, List<String> targets) {
      final int fromLayer = _layer(from);
      for (final String to in targets) {
        if (_layer(to) > fromLayer) {
          found.add('$from -> $to');
        }
      }
    });

    final Set<String> allowed = _allowlist();
    final List<String> fresh = (found.difference(allowed).toList()..sort());
    final List<String> stale = (allowed.difference(found).toList()..sort());
    expect(
      fresh,
      isEmpty,
      reason:
          'New imports break the layer rule (move the code down a layer, or pass it in from above):\n${fresh.join('\n')}',
    );
    expect(
      stale,
      isEmpty,
      reason: 'These allowlist lines are no longer violations; delete them:\n${stale.join('\n')}',
    );
  });

  test('every file under lib/ sits in a known layer', () {
    final List<String> unknown = [
      for (final String f in _libImports().keys)
        if (_layer(f) < 0) f,
    ];
    expect(unknown, isEmpty, reason: 'files outside models/core/sources/features/app: $unknown');
  });
}

const List<String> _layers = ['models', 'core', 'sources', 'logic', 'ui', 'app'];

/// lib-relative path -> layer index; -1 for files outside the layer folders.
int _layer(String path) {
  if (path.startsWith('gen/')) return -2; // importable from anywhere, imports nothing of ours
  if (path == 'main.dart' || path.startsWith('app/')) return _layers.indexOf('app');
  if (path.startsWith('models/')) return _layers.indexOf('models');
  if (path.startsWith('core/')) return _layers.indexOf('core');
  if (path.startsWith('sources/')) return _layers.indexOf('sources');
  if (path.startsWith('features/')) {
    final List<String> parts = path.split('/');
    if (parts.length > 2 && parts[2] == 'logic') return _layers.indexOf('logic');
    if (parts.length > 2 && parts[2] == 'ui') return _layers.indexOf('ui');
  }
  return -1;
}

final RegExp _directive = RegExp(r'''^\s*(?:import|export)\s+['"]package:lolisnatcher/([^'"]+)['"]''', multiLine: true);

Map<String, List<String>> _libImports() {
  final Map<String, List<String>> out = {};
  for (final FileSystemEntity e in Directory('lib').listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    final String rel = e.path.replaceAll(r'\', '/').substring('lib/'.length);
    if (rel.startsWith('gen/')) continue;
    out[rel] = [for (final RegExpMatch m in _directive.allMatches(e.readAsStringSync())) m.group(1)!];
  }
  return out;
}

Set<String> _allowlist() {
  final File f = File('test/architecture_allowlist.txt');
  if (!f.existsSync()) return {};
  return {
    for (final String line in f.readAsLinesSync())
      if (line.trim().isNotEmpty && !line.trimLeft().startsWith('#')) line.trim(),
  };
}
