import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/features/viewer/ui/gallery_view_page.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/tag.dart';
import 'package:lolisnatcher/models/tag_type.dart';

/// 1.0 M2 (viewer): the peek bar's artist chip. The app-wide tag store is a
/// BOORU store; a doujin item's tags carry their own site's type and the
/// store is never consulted for them (HANDOVER 6.2).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SettingsHandler.register();
    TagHandler.register();
    tempDir = Directory.systemTemp.createTempSync('viewer_peek_bar_artist_test');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  BooruItem post(String postURL) => BooruItem(
    fileURL: 'https://images.invalid/1.png',
    sampleURL: 'https://images.invalid/1.png',
    thumbnailURL: 'https://thumbs.invalid/1.png',
    tagsList: [Tag('vanilla'), Tag('kantoku', tagType: TagType.artist)],
    postURL: postURL,
    serverId: '1',
  );

  test("a doujin item's artist comes from its own tags, never from a booru's classification", () async {
    // Some booru the user browsed calls "vanilla" an artist.
    await TagHandler.instance.putTag(Tag('vanilla', tagType: TagType.artist), dbEnabled: false);

    expect(infoPeekBarArtistOf(post('https://nhentai.net/g/1001/')), 'kantoku');
  });

  test('a booru item still reads the app-wide store, as before', () async {
    await TagHandler.instance.putTag(Tag('vanilla', tagType: TagType.artist), dbEnabled: false);

    expect(infoPeekBarArtistOf(post('https://gelbooru.com/index.php?page=post&s=view&id=1')), 'vanilla');
  });
}
