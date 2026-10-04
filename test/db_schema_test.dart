import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/storage/database_handler.dart';

/// 1.0 M4: the schema statements run at every start went into batches (one
/// platform call instead of ~35). The schema they leave must be byte for byte
/// the one r89 left: test/fixtures/db_schema_r89.txt was recorded from the
/// r89 statements (every table, column, index and its SQL in sqlite_master).
///
/// Re-record (only when the schema is changed ON PURPOSE):
///   RECORD_DB_SCHEMA=1 bash tool/flutterw.sh test test/db_schema_test.dart
void main() {
  late DBHandler handler;
  const String golden = 'test/fixtures/db_schema_r89.txt';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SettingsHandler.register();
    handler = DBHandler();
    handler.db = await databaseFactory.openDatabase(inMemoryDatabasePath);
  });

  tearDown(() async {
    await handler.db?.close();
    handler.db = null;
  });

  Future<String> dump() async {
    final List<Map<String, Object?>> rows = await handler.db!.rawQuery(
      "SELECT type, name, tbl_name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name",
    );
    return rows.map((r) => '${r['type']}|${r['name']}|${r['tbl_name']}|${r['sql']}').join('\n');
  }

  test('a new database gets exactly the r89 schema', () async {
    await handler.updateTable();
    await handler.createCriticalIndexes();
    final String schema = await dump();
    if (Platform.environment['RECORD_DB_SCHEMA'] == '1') {
      File(golden).writeAsStringSync('$schema\n');
    }
    // Git may check the golden out with CRLF line endings on Windows.
    expect(schema, File(golden).readAsStringSync().replaceAll('
', '
').trimRight());
  });

  test('running the statements again on an existing database changes nothing', () async {
    await handler.updateTable();
    await handler.createCriticalIndexes();
    final String first = await dump();
    await handler.updateTable();
    await handler.createCriticalIndexes();
    expect(await dump(), first);
  });
}
