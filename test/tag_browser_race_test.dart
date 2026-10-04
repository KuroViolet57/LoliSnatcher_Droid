import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_tag.dart';
import 'package:lolisnatcher/models/tag_type.dart';
import 'package:lolisnatcher/core/storage/database_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/ui/navigation_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/features/tags/ui/tag_browser_page.dart';
import 'package:lolisnatcher/features/tags/ui/tag_type_strip.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/sources/framework/tags/tag_catalog_source.dart';

/// The tag snapshot, held in memory; every page read waits until the test
/// lets it through, so a read can be kept "in flight" on purpose.
class _HeldDb extends DBHandler {
  _HeldDb(this.rows);

  final List<Map<String, Object?>> rows;
  final List<Completer<void>> gates = [];

  void releaseAll() {
    for (final Completer<void> g in gates) {
      if (!g.isCompleted) g.complete();
    }
  }

  @override
  Future<List<Map<String, Object?>>> queryBooruTags({
    required String booruKey,
    String? nameLike,
    String? tagType,
    String? namespace,
    int limit = 60,
    int offset = 0,
  }) async {
    final Completer<void> gate = Completer<void>();
    gates.add(gate);
    await gate.future;
    return [
      for (final Map<String, Object?> r in rows)
        if ((tagType == null || r['tagType'] == tagType) && (nameLike == null || r['name'].toString().contains(nameLike))) r,
    ].skip(offset).take(limit).toList();
  }

  @override
  Future<int> countBooruTags(String booruKey, {String? tagType, String? namespace}) async => rows.length;
}

class _Catalog extends TagCatalogSource {
  @override
  List<TagCatalogNamespace> get namespaces => const [
    TagCatalogNamespace(key: 'character', label: 'Characters', type: TagType.character, byType: true),
  ];

  @override
  Future<List<BooruTagEntry>?> shardAt(String namespace, int shard) async => null;
}

/// 1.0 (M2): changing the filter while a page of tags was still being read
/// left that read to finish into the new list (the old query's rows under
/// the new filter), and the new list was never read until a scroll.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DBHandler realDb;
  late _HeldDb db;
  final Booru gelbooru = Booru('gelbooru', BooruType.Gelbooru, '', 'https://gelbooru.com', '');

  Map<String, Object?> row(String name, TagType type) => {
    'booruKey': 'gelbooru.com',
    'name': name,
    'namespace': '',
    'tagType': type.name,
    'count': 10,
    'source': 'site',
    'updatedAt': 1,
  };

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    TagHandler.register();
    NavigationHandler.register();
    tempDir = Directory.systemTemp.createTempSync('tag_browser_race');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SettingsHandler.instance.booruList.value = [gelbooru];
    SearchHandler.instance.tabs.clear();
    realDb = SettingsHandler.instance.dbHandler;
    db = _HeldDb([
      row('alphaone', TagType.artist),
      row('betatwo', TagType.character),
      row('gammathree', TagType.none),
      row('alphachar', TagType.character),
    ]);
    SettingsHandler.instance.dbHandler = db;
  });

  tearDown(() {
    db.releaseAll();
    SettingsHandler.instance.dbHandler = realDb;
    SettingsHandler.instance.booruList.clear();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Widget app(Widget home) => TranslationProvider(
    child: MaterialApp(navigatorKey: NavigationHandler.instance.navigatorKey, home: home),
  );

  /// Lets every waiting read through, as many rounds as it takes.
  Future<void> settleReads(WidgetTester tester) async {
    for (int i = 0; i < 4; i++) {
      db.releaseAll();
      await tester.pump();
    }
  }

  testWidgets('tag browser: a type filter tapped while the first page loads shows only that type', (tester) async {
    await tester.pumpWidget(app(const TagBrowserPage()));
    await tester.pump();
    expect(db.gates, hasLength(1), reason: 'the first page is being read');
    final Finder chip = find.widgetWithText(FilterChip, TagType.character.locName);
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pump();
    await settleReads(tester);
    expect(find.textContaining('betatwo'), findsOneWidget, reason: 'the filtered list was read');
    expect(find.textContaining('alphaone'), findsNothing, reason: "the old read's rows are not shown under the new filter");
    expect(find.textContaining('gammathree'), findsNothing);
  });

  testWidgets('catalog picker: typing in the filter while a page loads shows only what matches', (tester) async {
    final _Catalog catalog = _Catalog();
    await tester.pumpWidget(
      app(Scaffold(body: TagCatalogPickerSheet(booru: gelbooru, catalog: catalog, namespace: catalog.namespaces.single))),
    );
    await tester.pump();
    await tester.pump();
    expect(db.gates, isNotEmpty, reason: 'the first page is being read');
    await tester.enterText(find.byType(TextField), 'beta');
    await tester.pump(const Duration(milliseconds: 300));
    await settleReads(tester);
    await tester.pump(const Duration(milliseconds: 300));
    await settleReads(tester);
    expect(find.textContaining('betatwo'), findsOneWidget, reason: 'the filtered list was read');
    expect(find.textContaining('alphachar'), findsNothing, reason: "the old read's rows are not shown under the new filter");
  });
}
