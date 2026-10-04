import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/settings/source_settings_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/core/ui/navigation_handler.dart';
import 'package:lolisnatcher/features/downloads/logic/snatch_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/features/viewer/ui/info/tag_view.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/models/tag.dart';
import 'package:lolisnatcher/sources/framework/booru_handler.dart';

/// A source that loads the post in the info panel (like rule34.xxx and
/// danbooru) and answers when the test says so.
class _SlowItemSource extends BooruHandler {
  _SlowItemSource(super.booru, super.limit);

  final Completer<void> answer = Completer<void>();
  int asked = 0;

  @override
  bool get hasLoadItemSupport => true;

  @override
  bool get shouldUpdateIteminTagView => true;

  @override
  Future<({BooruItem? item, bool failed, String? error})> loadItem({
    required BooruItem item,
    CancelToken? cancelToken,
    bool withCapcthaCheck = false,
  }) async {
    asked++;
    await answer.future;
    return (item: item, failed: false, error: null);
  }
}

/// 1.0 M2 (viewer): the info panel of a post swiped past before its post
/// data answered (HANDOVER 4.23: the r54 guard was reverted with r54 in r55).
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
    tempDir = Directory.systemTemp.createTempSync('viewer_tag_view_dispose_test');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    SearchHandler.instance.tabs.clear();
    SearchHandler.instance.tabs.add(SearchTab(booru, null, 'origin'));
    SearchHandler.instance.changeTabIndex(0);
  });

  tearDown(() {
    SearchHandler.instance.tabs.clear();
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('an answer arriving after the panel is gone does not touch the gone panel', (tester) async {
    final _SlowItemSource source = _SlowItemSource(booru, 20);
    final BooruItem item = BooruItem(
      fileURL: 'https://images.invalid/1.png',
      sampleURL: 'https://images.invalid/1.png',
      thumbnailURL: 'https://thumbs.invalid/1.png',
      tagsList: [Tag('glasses'), Tag('smile')],
      postURL: 'https://gelbooru.invalid/index.php?page=post&s=view&id=1',
      serverId: '1',
    );

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          navigatorKey: NavigationHandler.instance.navigatorKey,
          // The app's theme always names a divider colour; the panel relies on it.
          theme: ThemeData(dividerTheme: const DividerThemeData(color: Colors.grey)),
          home: Scaffold(body: TagView(item: item, handler: source)),
        ),
      ),
    );
    await tester.pump();
    expect(source.asked, 1, reason: 'the panel asked for the post data');

    // Swiped on: the panel (keyed by the file URL in the sheet) is disposed.
    await tester.pumpWidget(const SizedBox());
    source.answer.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));

    expect(tester.takeException(), isNull);
  });
}
