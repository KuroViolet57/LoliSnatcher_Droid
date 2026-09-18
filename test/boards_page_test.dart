import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/board.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/boards_handler.dart';
import 'package:lolisnatcher/src/handlers/reverse_image_search.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/pages/boards_page.dart';

/// r73: the Boards page (left drawer) lists the saved boards and opens one
/// as a tab; the editor takes a name, a description, must-have and excluded
/// tags, the sources and a reference image.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  final BoardsHandler store = BoardsHandler.instance;

  setUp(() async {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('boards_page');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SettingsHandler.instance.booruList.value = [
      Booru('Gelbooru', BooruType.Gelbooru, '', 'https://gelbooru.com', ''),
      Booru('yande.re', BooruType.Moebooru, '', 'https://yande.re', ''),
    ];
    await store.resetForTests();
    store.directoryOverride = SettingsHandler.instance.path;
    await store.load();
    BoardsPage.resetForTests();
    BoardEditPage.resetForTests();
  });
  tearDown(() async {
    BoardsPage.resetForTests();
    BoardEditPage.resetForTests();
    await store.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('the page lists the boards; tapping one opens it as a tab through the opener', (tester) async {
    await store.save(Board(id: 'b1', name: 'Beach girls', description: 'blonde on a beach', mustTags: const ['animated']));
    await store.save(Board(id: 'b2', name: 'Cats'));
    final List<String> opened = [];
    BoardsPage.opener = (Board board) => opened.add(board.id);
    await tester.pumpWidget(const MaterialApp(home: BoardsPage()));
    await tester.pumpAndSettle();
    expect(find.text('Beach girls'), findsOneWidget);
    expect(find.text('Cats'), findsOneWidget);
    expect(find.textContaining('animated'), findsOneWidget);
    await tester.tap(find.text('Beach girls'));
    await tester.pumpAndSettle();
    expect(opened, ['b1']);
  });

  testWidgets('a new board: name, description, tags and sources are saved; the name defaults from the description', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BoardsPage()));
    await tester.pumpAndSettle();
    expect(find.textContaining('No boards yet'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('boards-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('board-description')), 'a blonde girl on a beach at sunset');
    await tester.enterText(find.byKey(const ValueKey('board-must')), 'animated, blonde_hair');
    await tester.enterText(find.byKey(const ValueKey('board-exclude')), 'male');
    await tester.scrollUntilVisible(find.byKey(const ValueKey('board-source-yande.re')), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const ValueKey('board-source-yande.re')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('board-save')));
    await tester.pumpAndSettle();
    expect(store.boards, hasLength(1));
    final Board saved = store.boards.single;
    expect(saved.name, 'a blonde girl on a beach', reason: 'the first words of the description');
    expect(saved.description, 'a blonde girl on a beach at sunset');
    expect(saved.mustTags, ['animated', 'blonde_hair']);
    expect(saved.excludeTags, ['male']);
    expect(saved.sourceNames, ['yande.re']);
    expect(find.text('a blonde girl on a beach'), findsOneWidget, reason: 'back on the list');
  });

  testWidgets('the editor opens prefilled from a template (Find posts like this) and keeps its image url', (tester) async {
    final Board template = Board(id: '', name: 'From a post', description: 'sakamata chloe hololive beach', imageUrl: 'https://x/sample.jpg', sourceNames: const ['Gelbooru']);
    await tester.pumpWidget(MaterialApp(home: BoardEditPage(template: template)));
    await tester.pumpAndSettle();
    expect(find.text('From a post'), findsOneWidget);
    expect(find.text('sakamata chloe hololive beach'), findsOneWidget);
    expect(find.textContaining('sample.jpg'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('board-save')));
    await tester.pumpAndSettle();
    expect(store.boards.single.imageUrl, 'https://x/sample.jpg');
    expect(store.boards.single.sourceNames, ['Gelbooru']);
    expect(store.boards.single.id, isNotEmpty);
  });

  testWidgets('a board from a post copies the image through the source\'s headers at creation; a failed copy keeps the address', (tester) async {
    final List<String> asked = [];
    BoardEditPage.imageFetcher = (String url, String? booruName) async {
      asked.add('$url@$booruName');
      return [1, 2, 3, 4];
    };
    final Board template = Board(id: '', name: 'From a post', description: 'x', imageUrl: 'https://gelbooru.com/samples/a.jpg', imageBooru: 'Gelbooru');
    await tester.pumpWidget(MaterialApp(home: BoardEditPage(template: template)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('board-save')));
    await tester.pumpAndSettle();
    final Board saved = store.boards.single;
    expect(asked, ['https://gelbooru.com/samples/a.jpg@Gelbooru']);
    expect(saved.imagePath, isNotEmpty);
    expect(File(saved.imagePath).lengthSync(), 4);
    expect(saved.imageUrl, 'https://gelbooru.com/samples/a.jpg');
    expect(saved.imageBooru, 'Gelbooru');
    BoardEditPage.imageFetcher = (String url, String? booruName) async => throw Exception('403');
    // A fresh app: the first editor popped its only route.
    await tester.pumpWidget(MaterialApp(key: const ValueKey('second-editor'), home: BoardEditPage(template: Board(id: '', name: 'Again', imageUrl: 'https://x/b.jpg', imageBooru: 'Gelbooru'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('board-save')));
    await tester.pumpAndSettle();
    expect(store.boards.last.imagePath, isEmpty);
    expect(store.boards.last.imageUrl, 'https://x/b.jpg');
  });

  testWidgets('"Refresh image matches" in a board\'s menu drops the cached matches', (tester) async {
    await store.save(
      Board(id: 'b1', name: 'Pic', imageUrl: 'https://x/a.jpg', matches: const [ReverseMatch(site: 'gelbooru', postId: '1', similarity: 90)], matchedImage: 'url:https://x/a.jpg', matchedAt: DateTime.now()),
    );
    await tester.pumpWidget(const MaterialApp(home: BoardsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('board-menu-b1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh image matches'));
    await tester.pumpAndSettle();
    expect(store.byId('b1')!.matches, isNull);
    expect(store.byId('b1')!.matchedImage, isEmpty);
  });

  testWidgets('Remove image clears the address too, so Save does not copy it back', (tester) async {
    int fetches = 0;
    BoardEditPage.imageFetcher = (String url, String? booruName) async {
      fetches++;
      return [1, 2];
    };
    await tester.pumpWidget(MaterialApp(home: BoardEditPage(template: Board(id: '', name: 'Pic', imageUrl: 'https://x/a.jpg', imageBooru: 'Gelbooru'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('board-image-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('board-save')));
    await tester.pumpAndSettle();
    expect(fetches, 0);
    expect(store.boards.single.imageUrl, isEmpty);
    expect(store.boards.single.imagePath, isEmpty);
  });

  testWidgets('Duplicate copies a picked image under the new board\'s id', (tester) async {
    final String path = await store.importImageBytes([1, 2, 3], 'b1', ext: 'png');
    await store.save(Board(id: 'b1', name: 'Pic', imagePath: path));
    await tester.pumpWidget(const MaterialApp(home: BoardsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('board-menu-b1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();
    final Board copy = store.boards.firstWhere((b) => b.id != 'b1');
    expect(copy.imagePath, isNotEmpty);
    expect(copy.imagePath, isNot(path));
    expect(File(copy.imagePath).lengthSync(), 3);
    expect(File(path).existsSync(), isTrue, reason: 'the original keeps its copy');
  });

  testWidgets('deleting a board from its menu', (tester) async {
    await store.save(Board(id: 'b1', name: 'Gone'));
    await tester.pumpWidget(const MaterialApp(home: BoardsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('board-menu-b1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(store.boards, isEmpty);
    expect(find.text('Gone'), findsNothing);
  });
}
