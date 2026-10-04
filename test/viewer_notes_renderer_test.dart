import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/ui/navigation_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/features/viewer/ui/notes_renderer.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/models/note_item.dart';
import 'package:lolisnatcher/sources/framework/booru_handler.dart';

/// A source whose note requests answer when the test says so. A cancelled
/// request answers with no notes, the way [BooruHandler.getNotes] does when
/// dio reports the cancel.
class _NotesSource extends BooruHandler {
  _NotesSource(super.booru, super.limit);

  final Map<String, List<Completer<List<NoteItem>>>> asked = {};

  @override
  bool get hasNotesSupport => true;

  @override
  Future<List<NoteItem>> getNotes(String postID, {CancelToken? cancelToken}) {
    final Completer<List<NoteItem>> answer = Completer<List<NoteItem>>();
    (asked[postID] ??= []).add(answer);
    cancelToken?.whenCancel.then((_) {
      if (!answer.isCompleted) answer.complete(<NoteItem>[]);
    });
    return answer.future;
  }
}

/// 1.0 M2 (viewer): the notes overlay when a post's notes change outside
/// the overlay's own load, and when the post changes during a load.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final Booru booru = Booru('danbooru', BooruType.Danbooru, '', 'https://danbooru.invalid', '');

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    NavigationHandler.register();
    tempDir = Directory.systemTemp.createTempSync('viewer_notes_renderer_test');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    ViewerHandler.instance.isLoaded.value = true;
    ViewerHandler.instance.showNotes.value = true;
  });

  tearDown(() {
    ViewerHandler.instance.isLoaded.value = false;
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  BooruItem post(String id) => BooruItem(
    fileURL: 'https://images.invalid/$id.png',
    sampleURL: 'https://images.invalid/$id.png',
    thumbnailURL: 'https://thumbs.invalid/$id.png',
    tagsList: const [],
    postURL: 'https://danbooru.invalid/posts/$id',
    serverId: id,
    fileWidth: 800,
    fileHeight: 600,
    hasNotes: true,
  );

  NoteItem note(String postId) => NoteItem(postID: postId, content: 'note on $postId', posX: 10, posY: 10, width: 100, height: 50);

  Future<void> pumpRenderer(WidgetTester tester, BooruItem item, BooruHandler handler) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          navigatorKey: NavigationHandler.instance.navigatorKey,
          home: Scaffold(
            body: NotesRenderer(item: item, handler: handler, pageController: null),
          ),
        ),
      ),
    );
  }

  testWidgets("notes loaded from the info panel after the overlay's own load came back empty are drawn", (tester) async {
    final _NotesSource source = _NotesSource(booru, 20);
    final BooruItem a = post('a');
    await pumpRenderer(tester, a, source);
    source.asked['a']!.single.complete(<NoteItem>[]); // a network hiccup: nothing
    await tester.pump();
    await tester.pump();
    expect(find.byType(NoteBuild), findsNothing);

    // The info panel's "Load notes" writes the post's notes directly.
    a.notes.value = [note('a')];
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull, reason: 'notesMap was still empty: RangeError in build');
    expect(find.byType(NoteBuild), findsOneWidget);
  });

  testWidgets("a post swiped to while the previous post's notes load gets its own notes", (tester) async {
    final _NotesSource source = _NotesSource(booru, 20);
    final BooruItem a = post('a');
    final BooruItem b = post('b');
    a.notes.value = [note('a')]; // loaded on an earlier visit

    await pumpRenderer(tester, a, source);
    expect(source.asked.keys, ['a']);

    await pumpRenderer(tester, b, source); // swiped on before a's notes answered
    await tester.pump();
    await tester.pump();

    expect(source.asked.keys, contains('b'), reason: "b's notes were never asked for");
    expect(a.notes.length, 1, reason: "a's cancelled request is not a's notes");

    source.asked['b']!.last.complete([note('b')]);
    await tester.pump();
    await tester.pump();

    expect(b.notes.length, 1);
    expect(find.byType(NoteBuild), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
