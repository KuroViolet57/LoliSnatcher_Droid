import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/nhentai_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/doujin_list_card.dart';

/// r66: the list card's height is the user's to set, per source, and the card
/// has a shadow so it reads as a raised card rather than a flat block.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  Booru nhentaiBooru() => Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', '');

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    SnatchHandler.register();
    tempDir = Directory.systemTemp.createTempSync('doujin_list_card_size');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
  });

  tearDown(() {
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpCard(WidgetTester tester, {required double height}) async {
    final NHentaiHandler handler = NHentaiHandler(nhentaiBooru(), 20);
    final BooruItem item = BooruItem(
      fileURL: 'https://images.invalid/1.png',
      sampleURL: 'https://images.invalid/1.png',
      thumbnailURL: 'https://thumbs.invalid/1.png',
      tagsList: [Tag('english'), Tag('vanilla')],
      postURL: 'https://nhentai.net/g/1001/',
      serverId: '1001',
    )..description = 'A title';
    handler.fetched.add(item);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: DoujinListCard(
              index: 0,
              item: item,
              handler: handler,
              scrollController: AutoScrollController(),
              height: height,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('the card is as tall as it is told', (tester) async {
    await pumpCard(tester, height: 140);
    expect(tester.getSize(find.byKey(const ValueKey('doujin-list-card-row'))).height, 140);

    await pumpCard(tester, height: 260);
    expect(tester.getSize(find.byKey(const ValueKey('doujin-list-card-row'))).height, 260);
  });

  testWidgets('the card is raised: it casts a shadow', (tester) async {
    await pumpCard(tester, height: 176);
    final Material material = tester.widget<Material>(find.byKey(const ValueKey('doujin-list-card-surface')));
    expect(material.elevation, greaterThan(0));
  });

  test('the height is a per-source setting with a sane range', () {
    final Booru booru = nhentaiBooru();
    expect(SourceSettingsHandler.instance.listCardHeight(booru), 176, reason: 'the default');

    SourceSettingsHandler.instance.settingsFor(booru).listCardHeight = 240;
    expect(SourceSettingsHandler.instance.listCardHeight(booru), 240);

    SourceSettingsHandler.instance.settingsFor(booru).listCardHeight = 10;
    expect(SourceSettingsHandler.instance.listCardHeight(booru), 120, reason: 'never smaller than the cover needs');

    SourceSettingsHandler.instance.settingsFor(booru).listCardHeight = 9999;
    expect(SourceSettingsHandler.instance.listCardHeight(booru), 320, reason: 'capped');
  });

  test('the cover column width is a per-source setting with a sane range (r69)', () {
    final Booru booru = nhentaiBooru();
    expect(SourceSettingsHandler.instance.listCoverWidth(booru), 116, reason: 'the default');

    SourceSettingsHandler.instance.settingsFor(booru).listCoverWidth = 200;
    expect(SourceSettingsHandler.instance.listCoverWidth(booru), 200);

    SourceSettingsHandler.instance.settingsFor(booru).listCoverWidth = 10;
    expect(SourceSettingsHandler.instance.listCoverWidth(booru), 72, reason: 'never narrower than a readable cover');

    SourceSettingsHandler.instance.settingsFor(booru).listCoverWidth = 9999;
    expect(SourceSettingsHandler.instance.listCoverWidth(booru), 240, reason: 'capped: the text needs the rest of the row');
  });
}
