import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/linked_media.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/widgets/linked_media_sheet.dart';

/// r52: "Opens in the app · e621" answered "Not found on e621" for a post
/// that exists. The id lookup carried the source's default filters, and a post
/// the source hides was dropped before the viewer opened.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final Booru e621 = Booru('e621', BooruType.e621, '', 'https://e621.net', '');
  late Directory tempDir;

  setUp(() {
    SettingsHandler.register();
    SearchHandler.register();
    TagHandler.register();
    NavigationHandler.register();
    tempDir = Directory.systemTemp.createTempSync('linked_media_opener');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
  });

  tearDown(() {
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  const LinkedMedia post = LinkedMedia(url: 'https://e621.net/posts/2197695', kind: LinkedMediaKind.sourcePost, postId: '2197695');

  test('an in-app link searches page 1, as a new tab does, without the default filters of the source', () {
    SourceSettingsHandler.instance.update(e621, (s) => s.alwaysAdd = 'rating:s');
    final SearchTab tab = LinkedMediaOpener.prepareTab(
      LinkedMedia(url: post.url, kind: post.kind, booru: e621, postId: post.postId),
    );
    expect(tab.booruHandler.pageNum, 1, reason: 'the first page, as a new e621 tab searches it');
    expect(tab.booruHandler.sourceQuery('id:2197695'), 'id:2197695');
    final SearchTab normal = SearchTab(e621, null, 'fox');
    expect(normal.booruHandler.sourceQuery('fox'), contains('rating:s'), reason: 'searches of the source keep its defaults');
  });

  test('a post the source hides still opens from its link (it stays blurred where the source blurs it)', () {
    final SearchTab tab = LinkedMediaOpener.prepareTab(
      LinkedMedia(url: post.url, kind: post.kind, booru: e621, postId: post.postId),
    );
    final BooruItem item = BooruItem(fileURL: 'https://f.invalid/a.webm', sampleURL: '', thumbnailURL: '', tagsList: [], postURL: post.url);
    tab.booruHandler.fetched.add(item);
    tab.booruHandler.filteredFetched.clear();
    LinkedMediaOpener.showFetched(tab.booruHandler);
    expect(tab.booruHandler.filteredFetched, [item]);
  });
}
