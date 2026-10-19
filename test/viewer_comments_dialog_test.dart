import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/core/ui/navigation_handler.dart';
import 'package:lolisnatcher/features/downloads/logic/snatch_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/features/viewer/ui/comments_dialog.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/models/comment_item.dart';
import 'package:lolisnatcher/sources/framework/booru_handler.dart';

/// A source whose comment pages answer when the test says so.
class _CommentsSource extends BooruHandler {
  _CommentsSource(super.booru, super.limit);

  final Map<int, Completer<List<CommentItem>>> _pages = {};

  Completer<List<CommentItem>> page(int pageNum) => _pages.putIfAbsent(pageNum, Completer<List<CommentItem>>.new);

  @override
  bool get hasCommentsSupport => true;

  @override
  Future<List<CommentItem>> getComments(String postID, int pageNum, {CancelToken? cancelToken}) => page(pageNum).future;
}

/// 1.0 M2 (viewer): the comments dialog with a short author name, and closed
/// before its comments arrive.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final Booru booru = Booru('gelbooru', BooruType.Gelbooru, '', 'https://gelbooru.invalid', '');

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    SnatchHandler.register();
    TagHandler.register();
    NavigationHandler.register();
    tempDir = Directory.systemTemp.createTempSync('viewer_comments_dialog_test');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  BooruItem post() => BooruItem(
    fileURL: 'https://images.invalid/1.png',
    sampleURL: 'https://images.invalid/1.png',
    thumbnailURL: 'https://thumbs.invalid/1.png',
    tagsList: const [],
    postURL: 'https://gelbooru.invalid/index.php?page=post&s=view&id=1',
    serverId: '1',
    fileWidth: 800,
    fileHeight: 600,
  );

  Future<void> pumpDialog(WidgetTester tester, BooruHandler handler) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          navigatorKey: NavigationHandler.instance.navigatorKey,
          theme: ThemeData(dividerTheme: const DividerThemeData(color: Colors.grey)),
          home: CommentsDialog(item: post(), handler: handler),
        ),
      ),
    );
  }

  testWidgets('an author whose name is shorter than two letters gets a comment row, not an error', (tester) async {
    final _CommentsSource source = _CommentsSource(booru, 20);
    source.page(0).complete(const [
      CommentItem(id: '1', authorName: 'A', content: 'one letter'),
      CommentItem(id: '2', authorName: '', content: 'no name'),
    ]);
    source.page(1).complete(const []);

    await pumpDialog(tester, source);
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull, reason: "'A'.substring(0, 2) threw a RangeError in the avatar slot");
    expect(find.text('A'), findsWidgets, reason: 'the one-letter name stands in for the avatar');
    expect(find.text('?'), findsOneWidget, reason: 'an empty name falls back like a missing one');
  });

  testWidgets('closing the dialog before the comments arrive does not touch the closed page', (tester) async {
    final _CommentsSource source = _CommentsSource(booru, 20);
    await pumpDialog(tester, source);
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
    source.page(0).complete(const [CommentItem(id: '1', authorName: 'Late', content: 'too late')]);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
