@Tags(['live'])
library;

import 'dart:io';

import 'package:alice_lightweight/alice.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/linked_media.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/widgets/linked_media_sheet.dart';

/// r52, against the live site: the e621 post the user's recording could not
/// open in the app ("Not found on e621") is found by the one-off tab.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late Directory tempDir;
  final Booru e621 = Booru('e621', BooruType.e621, '', 'https://e621.net', '');

  setUp(() {
    SettingsHandler.register();
    TagHandler.register();
    SearchHandler.register();
    NavigationHandler.register();
    tempDir = Directory.systemTemp.createTempSync('linked_media_live');
    SettingsHandler.instance
      ..path = '${tempDir.path}${Platform.pathSeparator}'
      ..alice = Alice();
    SourceSettingsHandler.instance.resetForTests();
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('e621 post 2197695 opens in the app', () async {
    final LinkedMedia media = LinkedMedia(url: 'https://e621.net/posts/2197695', kind: LinkedMediaKind.sourcePost, booru: e621, postId: '2197695');
    final SearchTab tab = LinkedMediaOpener.prepareTab(media);
    await tab.booruHandler.search(media.searchTerm, null);
    LinkedMediaOpener.showFetched(tab.booruHandler);
    expect(tab.booruHandler.filteredFetched.map((i) => i.serverId), contains('2197695'));
  }, timeout: const Timeout(Duration(minutes: 1)));
}
