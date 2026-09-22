import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_capture_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/services/capture_files.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// r80: a stopped capture is kept whole: the trace report in the log (in
/// numbered parts, the log cuts an entry at 10,000 characters) and as a file
/// in a "captures" folder inside the download folder, or in a folder picked
/// for captures. The source capture is saved there too.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late List<({String root, String name})> made;
  late List<({String uri, String name, String text, String mime})> copied;
  late List<({String uri, String name})> deleted;
  late Set<String> existing;
  bool copyWorks = true;

  String p(String rel) => '${tempDir.path}${Platform.pathSeparator}$rel';

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('capture_files');
    SettingsHandler.instance
      ..path = p('config${Platform.pathSeparator}')
      ..extPathOverride = ''
      ..capturesPath = '';
    made = [];
    copied = [];
    deleted = [];
    existing = {};
    copyWorks = true;
    CaptureFiles.isAndroid = () => true;
    CaptureFiles.scratchDir = () async => p('scratch${Platform.pathSeparator}');
    CaptureFiles.appFolder = () async => p('app${Platform.pathSeparator}captures${Platform.pathSeparator}');
    CaptureFiles.makeSafDir = (String root, String name) async {
      made.add((root: root, name: name));
      return '$root/$name';
    };
    CaptureFiles.copyToSaf = (String dir, String name, String uri, String mime) async {
      if (!copyWorks) return false;
      copied.add((uri: uri, name: name, text: File('$dir$name').readAsStringSync(), mime: mime));
      return true;
    };
    CaptureFiles.existsInSaf = (String uri, String name) async => existing.contains('$uri|$name');
    CaptureFiles.deleteInSaf = (String uri, String name) async {
      deleted.add((uri: uri, name: name));
      return true;
    };
    SourceCaptureHandler.instance.clear();
  });

  tearDown(() {
    CaptureFiles.resetForTests();
    SourceCaptureHandler.instance.clear();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('where a capture goes', () {
    test('with a download folder: into a "captures" folder inside it', () async {
      SettingsHandler.instance.extPathOverride = 'content://downloads';
      final SavedCapture? saved = await CaptureFiles.save('trace-1.txt', 'the report');

      expect(made, [(root: 'content://downloads', name: 'captures')]);
      expect(copied.single.uri, 'content://downloads/captures');
      expect(copied.single.name, 'trace-1.txt');
      expect(copied.single.text, 'the report');
      expect(copied.single.mime, 'text/plain');
      expect(saved, isNotNull);
      expect(saved!.fellBack, isFalse);
      expect(saved.where, contains('captures'));
      expect(Directory(p('scratch')).existsSync() ? Directory(p('scratch')).listSync() : const [], isEmpty, reason: 'the staging copy is removed');
    });

    test('a folder picked for captures comes first, and nothing is made inside it', () async {
      SettingsHandler.instance
        ..extPathOverride = 'content://downloads'
        ..capturesPath = 'content://mine';
      await CaptureFiles.save('trace-2.txt', 'x');

      expect(made, isEmpty);
      expect(copied.single.uri, 'content://mine');
    });

    test('saving the same name again replaces the file instead of adding "(1)"', () async {
      SettingsHandler.instance.extPathOverride = 'content://downloads';
      existing.add('content://downloads/captures|capture.txt');
      await CaptureFiles.save('capture.txt', 'newer');

      expect(deleted, [(uri: 'content://downloads/captures', name: 'capture.txt')]);
      expect(copied.single.text, 'newer');
    });

    test("no folder chosen: the app's own folder", () async {
      final SavedCapture? saved = await CaptureFiles.save('trace-3.txt', 'kept');

      expect(copied, isEmpty);
      expect(File(p('app${Platform.pathSeparator}captures${Platform.pathSeparator}trace-3.txt')).readAsStringSync(), 'kept');
      expect(saved!.fellBack, isTrue);
    });

    test("a folder that refuses the file: the app's own folder all the same", () async {
      SettingsHandler.instance.extPathOverride = 'content://downloads';
      copyWorks = false;
      final SavedCapture? saved = await CaptureFiles.save('trace-4.txt', 'kept anyway');

      expect(File(p('app${Platform.pathSeparator}captures${Platform.pathSeparator}trace-4.txt')).readAsStringSync(), 'kept anyway');
      expect(saved!.fellBack, isTrue);
    });

    test('off Android the download folder is a plain folder', () async {
      CaptureFiles.isAndroid = () => false;
      SettingsHandler.instance.extPathOverride = p('downloads${Platform.pathSeparator}');
      await CaptureFiles.save('trace-5.txt', 'desktop');

      expect(File(p('downloads${Platform.pathSeparator}captures${Platform.pathSeparator}trace-5.txt')).readAsStringSync(), 'desktop');
    });
  });

  test('a long report goes into the log whole, in numbered parts under 10,000 characters', () {
    Logger.Inst();
    final int before = Logger.talker.history.length;
    final String report = [for (int i = 0; i < 3000; i++) 'frame $i took ${i % 17} ms on the raster thread'].join('\n');
    expect(report.length, greaterThan(100000));
    Logger.Inst().logParts(report, 'PerfTrace', 'report', LogTypes.settingsLoad, title: 'Trace report');

    final List<String> messages = [for (final e in Logger.talker.history.skip(before)) e.message ?? ''];
    expect(messages.length, greaterThan(10));
    final StringBuffer joined = StringBuffer();
    for (int i = 0; i < messages.length; i++) {
      final String head = 'Trace report (part ${i + 1}/${messages.length})\n';
      expect(messages[i], startsWith(head));
      expect(messages[i].length, lessThanOrEqualTo(10000));
      joined.write(messages[i].substring(head.length));
    }
    expect(joined.toString(), report, reason: 'nothing lost between the parts');
  });

  test('a stopped trace: its report in the log and in the captures folder', () async {
    SettingsHandler.instance.extPathOverride = 'content://downloads';
    Logger.Inst();
    final int before = Logger.talker.history.length;
    final SavedCapture? saved = await CaptureFiles.keepTraceReport('3 frames\nnothing slow', now: DateTime(2026, 9, 22, 14, 5, 9));

    expect(copied.single.name, 'trace-2026-09-22-14-05-09.txt');
    expect(copied.single.text, '3 frames\nnothing slow');
    expect(saved, isNotNull);
    final List<String> messages = [for (final e in Logger.talker.history.skip(before)) e.message ?? ''];
    expect(messages.where((m) => m.contains('3 frames\nnothing slow')), hasLength(1));
  });

  test('the source capture is saved under one name per capture: saving again replaces it', () async {
    SettingsHandler.instance.extPathOverride = 'content://downloads';
    final SourceCaptureHandler capture = SourceCaptureHandler.instance;
    capture.start('https://example.com/gallery');
    capture.recordPage('https://example.com/gallery', '<html>first</html>');

    final SavedCapture? first = await capture.saveToCaptures();
    expect(first, isNotNull);
    final String name = copied.single.name;
    expect(name, startsWith('source-capture-example-com-'));
    expect(copied.single.text, contains('first'));

    existing.add('content://downloads/captures|$name');
    capture.recordPage('https://example.com/reader', '<html>second</html>');
    capture.stop();
    await capture.saveToCaptures();
    expect(copied.last.name, name, reason: 'the same capture, the same file');
    expect(copied.last.text, contains('second'));
    expect(deleted.single.name, name);
  });

  test('an empty source capture is not saved', () async {
    SettingsHandler.instance.extPathOverride = 'content://downloads';
    expect(await SourceCaptureHandler.instance.saveToCaptures(), isNull);
    expect(copied, isEmpty);
  });
}
