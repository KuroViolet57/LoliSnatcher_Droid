import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/features/backup/logic/backup_app.dart';
import 'package:lolisnatcher/features/backup/logic/drive_backup.dart';

/// Settings → Backup & restore → Google Drive: store.db and vectors.db are
/// copied in pieces. A whole-file read is what runs the phone out of memory.
void main() {
  test('a database is read and written in pieces, and Drive is handed the file', () async {
    final Directory dir = await Directory.systemTemp.createTemp('drive-chunks');
    final File source = File('${dir.path}${Platform.pathSeparator}store.db');
    final List<int> bytes = [for (int i = 0; i < 20; i++) i];
    await source.writeAsBytes(bytes);

    final List<List<int>> pieces = await DriveBackup.fileChunks(source, chunk: 8).toList();
    expect(pieces.map((List<int> piece) => piece.length).toList(), [8, 8, 4]);
    expect(pieces.expand((List<int> piece) => piece).toList(), bytes);

    final File empty = File('${dir.path}${Platform.pathSeparator}empty.db');
    await empty.writeAsBytes(<int>[]);
    expect(await DriveBackup.fileChunks(empty, chunk: 8).toList(), isEmpty);

    final List<int> sent = [];
    final List<int> progress = [];
    final int total = await DriveBackup.sendChunks(
      DriveBackup.fileChunks(source, chunk: 8),
      sent.addAll,
      total: bytes.length,
      onProgress: (int done, int all) {
        expect(all, bytes.length);
        progress.add(done);
      },
    );
    expect(total, 20);
    expect(sent, bytes);
    expect(progress, [8, 16, 20]);

    final File restored = File('${dir.path}${Platform.pathSeparator}restored.db');
    await DriveBackup.writeByteStream(
      Stream<List<int>>.fromIterable(const <List<int>>[
        [1, 2],
        [3],
      ]),
      restored,
    );
    expect(await restored.readAsBytes(), [1, 2, 3]);

    File? handed;
    final DriveBackupTarget target = DriveBackupTarget(
      const DriveSnapshot(id: 'snap', name: 'today'),
      uploadFile: (String name, File file, String mime, {void Function(int sent, int total)? onProgress, String? folderId}) async {
        handed = file;
        expect(name, 'store.db');
        expect(mime, 'application/x-sqlite3');
        expect(folderId, 'snap');
        return null;
      },
      downloadTo: (String name, File to, {String? folderId}) async {
        expect(name, 'vectors.db');
        expect(folderId, 'snap');
        await DriveBackup.writeByteStream(
          Stream<List<int>>.fromIterable(const <List<int>>[
            [4],
            [5, 6],
          ]),
          to,
        );
        return true;
      },
    );
    await target.writeFile('store.db', source);
    expect(handed?.path, source.path);

    final File vectors = File('${dir.path}${Platform.pathSeparator}vectors.db');
    expect(await target.readToFile('vectors.db', vectors), isTrue);
    expect(await vectors.readAsBytes(), [4, 5, 6]);

    await dir.delete(recursive: true);
  });
}
