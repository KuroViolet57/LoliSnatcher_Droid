import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/features/feed/logic/tab_backup_gate.dart';

TabBackupFields tab(
  String tags, {
  String booru = 'e621',
  String? id = 'a',
  String? group,
  String? poolId,
  String? poolName,
  String? doujinPostURL,
  String? doujinTitle,
  String? doujinThumb,
  List<String> secondary = const [],
  Map<String, String> overrides = const {},
  Map<String, bool> inherit = const {},
}) => TabBackupFields(
  tags: tags,
  booru: booru,
  id: id,
  group: group,
  poolId: poolId,
  poolName: poolName,
  doujinPostURL: doujinPostURL,
  doujinTitle: doujinTitle,
  doujinThumb: doujinThumb,
  secondaryBoorus: secondary,
  tagOverrides: overrides,
  inheritMainTags: inherit,
);

void main() {
  late DateTime now;
  late TabBackupGate gate;

  setUp(() {
    now = DateTime(2026, 10, 4, 12);
    gate = TabBackupGate(now: () => now);
  });

  int sig(List<TabBackupFields> tabs, [int selected = 0]) => TabBackupGate.signatureOf(tabs, selected);

  test('the first backup always writes', () {
    expect(gate.shouldWrite(sig([tab('a')])), isTrue);
  });

  test('an unchanged tab list is not written again within five minutes', () {
    final int s = sig([tab('a'), tab('b', id: 'b')]);
    gate.written(s);
    now = now.add(const Duration(minutes: 4, seconds: 59));
    expect(gate.shouldWrite(sig([tab('a'), tab('b', id: 'b')])), isFalse);
  });

  test('an unchanged tab list is written again after five minutes', () {
    final int s = sig([tab('a')]);
    gate.written(s);
    now = now.add(const Duration(minutes: 5));
    expect(gate.shouldWrite(s), isTrue);
  });

  test('every field TabBackup writes changes the signature', () {
    final TabBackupFields base = tab('a b');
    final int s = sig([base]);
    final List<TabBackupFields> variants = [
      tab('a c'),
      tab('a b', booru: 'gelbooru'),
      tab('a b', id: 'z'),
      tab('a b', group: 'g'),
      tab('a b', poolId: '1'),
      tab('a b', poolName: 'p'),
      tab('a b', doujinPostURL: 'u'),
      tab('a b', doujinTitle: 't'),
      tab('a b', doujinThumb: 'th'),
      tab('a b', secondary: ['x']),
      tab('a b', overrides: {'x': 'y'}),
      tab('a b', inherit: {'x': false}),
    ];
    for (final TabBackupFields v in variants) {
      expect(sig([v]), isNot(s), reason: 'a change must be noticed: ${v.debugLabel}');
    }
  });

  test('the selected tab, the order and the count change the signature', () {
    final List<TabBackupFields> two = [tab('a'), tab('b', id: 'b')];
    expect(sig(two, 0), isNot(sig(two, 1)));
    expect(sig(two), isNot(sig(two.reversed.toList())));
    expect(sig(two), isNot(sig([...two, tab('c', id: 'c')])));
  });

  test('map order does not matter, map content does', () {
    expect(
      sig([tab('a', overrides: {'x': '1', 'y': '2'})]),
      sig([tab('a', overrides: {'y': '2', 'x': '1'})]),
    );
    expect(sig([tab('a', overrides: {'x': '1'})]), isNot(sig([tab('a', overrides: {'x': '2'})])));
  });

  test('a changed list is written even right after a write', () {
    gate.written(sig([tab('a')]));
    expect(gate.shouldWrite(sig([tab('b')])), isTrue);
  });

  test('reset forgets the last write', () {
    final int s = sig([tab('a')]);
    gate.written(s);
    gate.reset();
    expect(gate.shouldWrite(s), isTrue);
  });
}
