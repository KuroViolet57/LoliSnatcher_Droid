import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/nhentai_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/doujin_card_meta.dart';

/// r63: what a doujin feed card knows about a gallery - the title, the
/// language, what kind of book it is, how many pages, and which tags to show
/// first. Kept out of the widgets so both card layouts read the same values.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(SettingsHandler.register);

  NHentaiHandler handler() => NHentaiHandler(Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', ''), 20);

  BooruItem item({List<String> tags = const [], String? description, int? pages}) {
    final BooruItem i = BooruItem(
      fileURL: 'https://images.invalid/1.png',
      sampleURL: 'https://images.invalid/1.png',
      thumbnailURL: 'https://thumbs.invalid/1.png',
      tagsList: [for (final t in tags) Tag(t)],
      postURL: 'https://nhentai.net/g/1001/',
      serverId: '1001',
    );
    if (description != null) i.description = description;
    if (pages != null) i.fileCountHint.value = pages;
    return i;
  }

  test('the title is the first real line of the description', () {
    expect(
      DoujinCardMeta.title(item(description: '[Artist] A Great Title\nOriginal line')),
      '[Artist] A Great Title',
    );
    expect(DoujinCardMeta.title(item(description: '\n\n  Second line wins  ')), 'Second line wins');
    expect(DoujinCardMeta.title(item()), '');
  });

  test('the language comes from the tags, namespaced or plain', () {
    expect(DoujinCardMeta.language(item(tags: ['english']), handler()), 'EN');
    expect(DoujinCardMeta.language(item(tags: ['language:japanese']), handler()), 'JP');
    expect(DoujinCardMeta.language(item(tags: ['korean', 'vanilla']), handler()), 'KR');
    expect(DoujinCardMeta.language(item(tags: ['vanilla']), handler()), isNull);
  });

  test('the kind of book comes from the category, spelled for people', () {
    expect(DoujinCardMeta.category(item(tags: ['doujinshi']), handler()), 'Doujinshi');
    expect(DoujinCardMeta.category(item(tags: ['category:western']), handler()), 'Western');
    expect(DoujinCardMeta.category(item(tags: ['artist_cg']), handler()), 'Artist CG');
    expect(DoujinCardMeta.category(item(tags: ['vanilla']), handler()), isNull);
  });

  test('pages only when the source said so', () {
    expect(DoujinCardMeta.pages(item(pages: 56)), 56);
    expect(DoujinCardMeta.pages(item(pages: 0)), isNull);
    expect(DoujinCardMeta.pages(item()), isNull);
  });

  test('card tags: favourites first, language and category left out', () {
    final BooruItem i = item(tags: ['english', 'doujinshi', 'vanilla', 'glasses', 'ahegao']);
    final List<Tag> shown = DoujinCardMeta.cardTags(
      i,
      handler(),
      isStarred: (t) => t == 'glasses',
    );

    expect(shown.map((t) => t.fullString), ['glasses', 'vanilla', 'ahegao']);
  });
}
