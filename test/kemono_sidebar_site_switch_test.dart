import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/core/ui/navigation_handler.dart';
import 'package:lolisnatcher/features/doujin/logic/doujin_data_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/settings/source_settings_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/features/kemono/ui/kemono_sidebar.dart';
import 'package:lolisnatcher/sources/kemono/kemono_creator_store.dart';
import 'package:lolisnatcher/sources/kemono/kemono_file_hosts.dart';
import 'package:lolisnatcher/sources/kemono/kemono_session_handler.dart';
import 'package:lolisnatcher/sources/kemono/kemono_site.dart';
import 'package:lolisnatcher/gen/strings.g.dart';

/// 1.0 M2 (tabs): the kemono sidebar follows the site of the tab it is opened on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    TagHandler.register();
    NavigationHandler.register();
    tempDir = Directory.systemTemp.createTempSync('kemono_sidebar_switch');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    DoujinDataHandler.instance.resetForTests();
    SearchHandler.instance.tabs.clear();
  });

  tearDown(() {
    SearchHandler.instance.tabs.clear();
    SettingsHandler.instance.booruList.clear();
    DoujinDataHandler.instance.resetForTests();
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('kemono sidebar: a tab on the other kemono-style site gets that site\'s rows and index', (tester) async {
    final Booru kemono = Booru('kemono', BooruType.Kemono, '', 'https://kemono.cr', '');
    final Booru pawchive = Booru('pawchive', BooruType.Pawchive, '', 'https://pawchive.pw', '');
    KemonoSessionHandler.instance.resetForTests();
    final int now = DateTime.now().millisecondsSinceEpoch;
    // Fresh indexes, so nothing goes to the network.
    KemonoCreatorStore.forSite(KemonoSite.kemono)
      ..resetForTests()
      ..state.value = KemonoIndexState(count: 5, refreshedAt: now);
    KemonoCreatorStore.forSite(KemonoSite.pawchive)
      ..resetForTests()
      ..state.value = KemonoIndexState(count: 7, refreshedAt: now);
    KemonoFileHosts.forSite(KemonoSite.kemono).resetForTests();
    KemonoFileHosts.forSite(KemonoSite.pawchive).resetForTests();

    tester.view.physicalSize = const Size(600, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // The home page builds the sidebar with no key, so the State is reused.
    Widget app(Booru booru) => TranslationProvider(
      child: MaterialApp(home: Scaffold(body: KemonoSidebar(booru: booru, toggleDrawer: () {}))),
    );

    await tester.pumpWidget(app(kemono));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Popular'), findsOneWidget);
    expect(find.textContaining('5 creators'), findsOneWidget);

    await tester.pumpWidget(app(pawchive));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('pawchive'), findsOneWidget);
    expect(find.text('pawchive.pw'), findsOneWidget, reason: 'the site line is the new site');
    expect(find.text('Popular'), findsNothing, reason: 'pawchive has no popular feed');
    expect(find.text('DMs'), findsNothing, reason: 'pawchive has no DMs');
    expect(find.textContaining('7 creators'), findsOneWidget, reason: "pawchive's own creator index");
  });
}
