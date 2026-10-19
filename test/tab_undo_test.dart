import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/settings/source_settings_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/core/ui/navigation_handler.dart';
import 'package:lolisnatcher/features/downloads/logic/snatch_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/booru_type.dart';

/// Closing a tab while another remains can be undone. Closing the only tab
/// still resets it to the default tags, and that reset is not an undo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    SearchHandler.register();
    SnatchHandler.register();
    TagHandler.register();
    NavigationHandler.register();
    tempDir = Directory.systemTemp.createTempSync('tab_undo');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
    SearchHandler.instance.tabs.clear();
  });

  tearDown(() {
    SearchHandler.instance.tabs.clear();
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  SearchTab makeTab(String tags, {String? group}) {
    final SearchTab tab = SearchTab(
      Booru('gelbooru', BooruType.Gelbooru, '', 'https://gelbooru.com', ''),
      null,
      tags,
    );
    tab.groupName = group;
    // A loaded tab must not start a search when the test switches to it.
    tab.booruHandler.filteredFetched.add(
      BooruItem(
        fileURL: 'https://img.gelbooru.com/$tags.jpg',
        sampleURL: 'https://img.gelbooru.com/$tags.jpg',
        thumbnailURL: 'https://img.gelbooru.com/$tags.jpg',
        tagsList: const [],
        postURL: 'https://gelbooru.com/index.php?page=post&s=view&id=1',
      ),
    );
    return tab;
  }

  test('undo puts the closed tab back, including its group', () {
    final SearchHandler handler = SearchHandler.instance;
    final SearchTab first = makeTab('cats');
    final SearchTab second = makeTab('dogs', group: 'night');
    handler.tabs.addAll([first, second]);
    handler.changeTabIndex(0);
    handler.removeTabAt(tabIndex: 1);

    expect(handler.tabs.map((t) => t.tags), ['cats']);
    handler.undoClosedTab();

    expect(handler.tabs.map((t) => t.tags), ['cats', 'dogs']);
    expect(identical(handler.tabs[1], second), isTrue);
    expect(handler.tabs[1].groupName, 'night');
    expect(handler.currentIndex, 1);
  });

  test('undo of the open tab selects that tab again', () {
    final SearchHandler handler = SearchHandler.instance;
    handler.tabs.addAll([makeTab('cats'), makeTab('dogs')]);
    handler.changeTabIndex(0);
    handler.removeTabAt(tabIndex: 0);

    expect(handler.tabs.map((t) => t.tags), ['dogs']);
    handler.undoClosedTab();

    expect(handler.tabs.map((t) => t.tags), ['cats', 'dogs']);
    expect(handler.currentIndex, 0);
  });

  test('a second undo does not insert the tab again', () {
    final SearchHandler handler = SearchHandler.instance;
    handler.tabs.addAll([makeTab('cats'), makeTab('dogs')]);
    handler.changeTabIndex(0);
    handler.removeTabAt(tabIndex: 1);
    handler.undoClosedTab();
    handler.undoClosedTab();

    expect(handler.tabs.length, 2);
  });

  test('closing the only tab resets it, and undo does not bring the old search back', () async {
    final SearchHandler handler = SearchHandler.instance;
    handler.tabs.add(makeTab('cats'));
    handler.changeTabIndex(0);
    handler.removeTabAt();
    // Let the reset's scheduled search see the tab before tearDown clears it.
    await Future<void>.delayed(Duration.zero);

    expect(handler.tabs.single.tags, 'rating:safe');
    handler.undoClosedTab();
    expect(handler.tabs.single.tags, 'rating:safe');
    expect(handler.tabs.length, 1);
  });
}
