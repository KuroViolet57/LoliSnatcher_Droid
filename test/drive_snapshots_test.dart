import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/services/drive_backup.dart';

/// r80: Google Drive keeps named snapshots - a folder per backup inside the
/// LoliSnatcher folder - instead of one set of files overwritten each time.
/// The backup made before snapshots existed is still offered, as "Earlier
/// backup".
void main() {
  test('each folder is a snapshot, newest first; files at the top are the earlier backup', () {
    final List<DriveSnapshot> s = DriveBackup.snapshotsFrom(
      [
        {'id': 'f1', 'name': 'before the update', 'mimeType': DriveBackup.folderMime, 'createdTime': '2026-09-20T10:00:00Z'},
        {'id': 'f2', 'name': '2026-09-22 09.30', 'mimeType': DriveBackup.folderMime, 'createdTime': '2026-09-22T09:30:00Z'},
        {'id': 'x1', 'name': 'store.db', 'mimeType': 'application/x-sqlite3', 'modifiedTime': '2026-09-01T08:00:00Z'},
        {'id': 'x2', 'name': 'settings.json', 'mimeType': 'application/json', 'modifiedTime': '2026-09-02T08:00:00Z'},
      ],
      rootId: 'root',
    );
    expect(s.map((e) => e.name).toList(), ['2026-09-22 09.30', 'before the update', DriveBackup.earlierBackupName]);
    expect(s.last.id, 'root', reason: 'the earlier backup is the folder itself');
    expect(s.last.earlier, isTrue);
    expect(s.last.created, DateTime.utc(2026, 9, 2, 8), reason: 'dated by its newest file');
    expect(s.first.created, DateTime.utc(2026, 9, 22, 9, 30));
  });

  test('no files at the top: no earlier backup entry', () {
    final List<DriveSnapshot> s = DriveBackup.snapshotsFrom(
      [
        {'id': 'f1', 'name': 'a', 'mimeType': DriveBackup.folderMime, 'createdTime': '2026-09-20T10:00:00Z'},
      ],
      rootId: 'root',
    );
    expect(s.single.earlier, isFalse);
  });

  test('a snapshot name you already used gets a number', () {
    expect(DriveBackup.uniqueName('weekly', ['daily']), 'weekly');
    expect(DriveBackup.uniqueName('weekly', ['weekly']), 'weekly (2)');
    expect(DriveBackup.uniqueName('weekly', ['weekly', 'weekly (2)']), 'weekly (3)');
    expect(DriveBackup.uniqueName('   ', []), isNotEmpty, reason: 'a blank name gets the default');
  });

  test("the default name is the date and time, and a quote in a name cannot break Drive's search", () {
    expect(DriveBackup.defaultSnapshotName(DateTime(2026, 9, 22, 9, 5)), '2026-09-22 09.05');
    expect(DriveBackup.quoted("it's"), r"it\'s");
    expect(DriveBackup.quoted(r'a\b'), r'a\\b');
  });
}
