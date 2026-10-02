import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/furaffinity_session_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/pages/furaffinity_post_page.dart';
import 'package:lolisnatcher/src/widgets/drawers/furaffinity_sidebar.dart';

/// r42: FurAffinity's own sidebar (with the switch back to the app's) and its
/// post page (description, folders, keywords, comments, the gallery around it).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final Booru fa = Booru('FurAffinity', BooruType.FurAffinity, '', 'https://www.furaffinity.net', '');
  String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    TagHandler.register();
    tempDir = Directory.systemTemp.createTempSync('furaffinity_pages');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SettingsHandler.instance.furAffinitySidebar.value = true;
    FurAffinitySessionHandler.instance.resetForTests();
    SearchHandler.instance.tabs.clear();
  });

  tearDown(() {
    FurAffinitySessionHandler.instance.resetForTests();
    SearchHandler.instance.tabs.clear();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpSidebar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: Scaffold(body: FurAffinitySidebar(booru: fa, toggleDrawer: () {})),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the sidebar, logged out: browse and search, a way to log in, and the switch to the app sidebar', (tester) async {
    await pumpSidebar(tester);
    expect(find.text('Browse'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Animated only'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Submissions inbox'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('fa-sidebar-app')));
    await tester.pump();
    expect(SettingsHandler.instance.furAffinitySidebar.value, isFalse);
  });

  testWidgets('the sidebar, logged in: the inbox, watched artists, your favorites and gallery, the blocklist', (tester) async {
    FurAffinitySessionHandler.instance.store(a: 'AAA', b: 'BBB');
    FurAffinitySessionHandler.instance.noteUsername('kuroviolet');
    await pumpSidebar(tester);
    expect(find.text('Submissions inbox'), findsOneWidget);
    expect(find.text('Watched artists'), findsOneWidget);
    expect(find.text('My favorites'), findsOneWidget);
    expect(find.text('My gallery'), findsOneWidget);
    expect(find.text('Blocklist'), findsOneWidget);
    expect(find.text('~kuroviolet'), findsOneWidget);
  });

  testWidgets('the post page: title, description, folders, keywords, comments, and the older submission', (tester) async {
    tester.view.physicalSize = const Size(420, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final BooruItem item = BooruItem(
      fileURL: '',
      sampleURL: '',
      thumbnailURL: 'https://t.invalid/65972733@600-1.jpg',
      tagsList: [Tag('artist:ryan-the-fox')],
      postURL: 'https://www.furaffinity.net/view/65972733/',
      serverId: '65972733',
    );
    final List<String> fetched = [];
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: FurAffinityPostPage(
            booru: fa,
            item: item,
            fetchPage: (String url) async {
              fetched.add(url);
              return fixture('furaffinity_view_folders.html');
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(fetched, ['https://www.furaffinity.net/view/65972733/']);
    expect(find.text('Happy 8/8!'), findsWidgets);
    expect(find.text('Folders'), findsOneWidget);
    expect(find.byKey(const ValueKey('fa-folder-464222')), findsOneWidget);
    expect(find.text('Keywords'), findsOneWidget);
    expect(find.text('Comments (5)'), findsOneWidget);
    expect(find.textContaining('Happy late vore day fluffer'), findsOneWidget);
    expect(find.byKey(const ValueKey('fa-post-older')), findsOneWidget);
    expect(find.byKey(const ValueKey('fa-post-newer')), findsNothing);
  });
}
