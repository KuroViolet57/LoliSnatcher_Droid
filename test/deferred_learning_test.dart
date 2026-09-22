import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/handlers/recommender/deferred_learning.dart';

/// r78: a learning step still waiting when the app leaves the screen is kept
/// on disk and learned in full next time, instead of being learned at once
/// without the models - which could not be undone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final DeferredLearning kept = DeferredLearning.instance;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('deferred_learning');
    kept.resetForTests();
    kept.fileFor = () => '${tempDir.path}${Platform.pathSeparator}sub${Platform.pathSeparator}deferred.json';
  });

  tearDown(() {
    kept.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('what is kept is on disk at once, and comes back in order', () async {
    kept.keep({'kind': 'favourite', 'key': 'a'});
    kept.keep({'kind': 'snatch', 'key': 'b'});
    expect(kept.waiting, 2);
    expect(File(kept.fileFor()).existsSync(), isTrue, reason: 'written before the app can be ended');
    // A new run of the app reads the file.
    kept.resetForTests();
    kept.fileFor = () => '${tempDir.path}${Platform.pathSeparator}sub${Platform.pathSeparator}deferred.json';
    final List<Map<String, dynamic>> back = await kept.takeAll();
    expect(back.map((e) => e['key']), ['a', 'b']);
    expect(kept.waiting, 0);
    expect(File(kept.fileFor()).existsSync(), isFalse, reason: 'handed over once');
    expect(await kept.takeAll(), isEmpty);
  });

  test('only the last few hundred are kept', () {
    for (int i = 0; i < DeferredLearning.cap + 25; i++) {
      kept.keep({'key': 'k$i'});
    }
    expect(kept.waiting, DeferredLearning.cap);
    final List<dynamic> onDisk = jsonDecode(File(kept.fileFor()).readAsStringSync()) as List<dynamic>;
    expect((onDisk.first as Map<String, dynamic>)['key'], 'k25', reason: 'the oldest go first');
    expect((onDisk.last as Map<String, dynamic>)['key'], 'k${DeferredLearning.cap + 24}');
  });

  test('a broken file costs nothing', () async {
    final File f = File(kept.fileFor());
    f.parent.createSync(recursive: true);
    f.writeAsStringSync('{not json at all');
    expect(await kept.takeAll(), isEmpty);
    kept.keep({'key': 'after'});
    expect(kept.waiting, 1);
  });

  test('nowhere to write is not a crash', () {
    kept.fileFor = () => '${tempDir.path}${Platform.pathSeparator}sub${Platform.pathSeparator}';
    kept.keep({'key': 'a'});
    expect(kept.waiting, 1, reason: 'kept in memory for this run at least');
  });
}
