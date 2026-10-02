import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// Round 2, item 7: the detail-page layout setting (compact | big cover),
/// global + per-source with the usual override semantics.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  final booru = Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');
  final other = Booru('other-doujin', BooruType.NHentai, '', 'https://other.example', '');

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('doujin_detail_layout_test');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
  });

  tearDown(() {
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('defaults to compact', () {
    expect(SourceSettingsHandler.instance.detailLayout(booru), 'compact');
  });

  test('global layer switches every source; per-source overrides win', () {
    final source = SourceSettingsHandler.instance;
    source.updateGlobal((s) => s.detailLayout = 'cover');
    expect(source.detailLayout(booru), 'cover');
    expect(source.detailLayout(other), 'cover');

    source.update(booru, (s) => s.detailLayout = 'compact');
    expect(source.detailLayout(booru), 'compact');
    expect(source.detailLayout(other), 'cover');

    // reset the override -> back to the global value
    source.update(booru, (s) => s.detailLayout = null);
    expect(source.detailLayout(booru), 'cover');
  });

  test('round-trips through sourceSettings.json', () {
    final source = SourceSettingsHandler.instance;
    source.updateGlobal((s) => s.detailLayout = 'cover');
    source.resetForTests();
    expect(source.detailLayout(booru), 'cover');
  });
}
