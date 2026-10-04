import 'dart:io';

import 'package:flutter/material.dart';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/app/shells/desktop/desktop_image_listener.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/doujin/logic/doujin_data_handler.dart';
import 'package:lolisnatcher/features/downloads/logic/snatch_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/features/viewer/ui/media/guess_extension_viewer.dart';
import 'package:lolisnatcher/features/viewer/ui/media/load_item_viewer.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/sources/booru/gelbooru_handler.dart';

/// A source that loads post details, without the network.
class _LoadingHandler extends GelbooruHandler {
  _LoadingHandler(super.booru, super.limit);

  int loads = 0;

  @override
  Future<({BooruItem? item, bool failed, String? error})> loadItem({
    required BooruItem item,
    CancelToken? cancelToken,
    bool withCapcthaCheck = false,
  }) async {
    loads++;
    return (item: null, failed: true, error: 'test');
  }
}

/// 1.0 M2: on the desktop layout, a post whose details must be loaded first
/// (needToLoadItem) was handed to the extension guesser, because the branch
/// meant for it tested needToGuess a second time. The phone viewer loads the
/// post (gallery_view_page: isNeedToLoadItem && hasLoadItemSupport).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final Booru gelbooru = Booru('gelbooru', BooruType.Gelbooru, '', 'https://gelbooru.com', '');

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    SnatchHandler.register();
    tempDir = Directory.systemTemp.createTempSync('desktop_image_listener');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    DoujinDataHandler.instance.resetForTests();
    SearchHandler.instance.tabs.clear();
  });

  tearDown(() {
    ViewerHandler.instance.current.value = null;
    SearchHandler.instance.tabs.clear();
    DoujinDataHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('a post that needs its details loaded gets the loader, not the extension guesser', (tester) async {
    final _LoadingHandler handler = _LoadingHandler(gelbooru, 20);
    final SearchTab tab = SearchTab(gelbooru, null, 'q', customHandler: handler);
    final BooruItem item = BooruItem(
      fileURL: '',
      sampleURL: '',
      thumbnailURL: '',
      tagsList: const [],
      postURL: 'https://gelbooru.com/index.php?page=post&s=view&id=1',
      serverId: '1',
    );
    item.mediaType.value = MediaType.needToLoadItem;
    handler.fetched.add(item);
    handler.filterFetched();
    SearchHandler.instance.tabs.add(tab);
    SearchHandler.instance.index.value = 0;
    SearchHandler.instance.tabId.value = tab.id;
    ViewerHandler.instance.current.value = item;

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(home: Scaffold(body: DesktopImageListener(tab))),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(LoadItemViewer), findsOneWidget);
    expect(find.byType(GuessExtensionViewer), findsNothing);
    expect(handler.loads, 1, reason: 'the loader asked the source for the post');

    await tester.pumpWidget(const SizedBox());
  });
}
