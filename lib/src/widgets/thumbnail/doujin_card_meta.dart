import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';

/// What a doujin feed card knows about a gallery (r63).
///
/// Both card layouts read these, so the grid card and the list card never
/// disagree about the title, the language or what kind of book it is. Sources
/// that namespace their tags (`language:english`) and sources that do not
/// (`english`) both work.
class DoujinCardMeta {
  const DoujinCardMeta._();

  static const Map<String, String> languageCodes = {
    'english': 'EN',
    'japanese': 'JP',
    'chinese': 'CH',
    'korean': 'KR',
  };

  /// The categories the sites use, spelled the way people read them.
  static const Map<String, String> categoryLabels = {
    'doujinshi': 'Doujinshi',
    'manga': 'Manga',
    'western': 'Western',
    'artist_cg': 'Artist CG',
    'artistcg': 'Artist CG',
    'game_cg': 'Game CG',
    'gamecg': 'Game CG',
    'image_set': 'Image Set',
    'imageset': 'Image Set',
    'non-h': 'Non-H',
    'cosplay': 'Cosplay',
    'asian_porn': 'Asian Porn',
    'misc': 'Misc',
  };

  /// The gallery's title: the first real line of its description.
  static String title(BooruItem item) =>
      (item.description ?? '').split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '').trim();

  /// 'EN', 'JP', ... or null when the tags do not say.
  static String? language(BooruItem item, BooruHandler handler) {
    for (final Tag tag in item.tagsList) {
      final String? ns = handler.tagNamespace(tag.fullString);
      final String name = _bare(tag.fullString);
      if (ns == 'language' || (ns == null && languageCodes.containsKey(name))) {
        final String? code = languageCodes[name];
        if (code != null) return code;
      }
    }
    return null;
  }

  /// 'Doujinshi', 'Western', 'Artist CG', ... or null.
  static String? category(BooruItem item, BooruHandler handler) {
    for (final Tag tag in item.tagsList) {
      final String? ns = handler.tagNamespace(tag.fullString);
      final String name = _bare(tag.fullString);
      if (ns == 'category' || (ns == null && categoryLabels.containsKey(name))) {
        return categoryLabels[name] ?? _spell(name);
      }
    }
    return null;
  }

  /// How many pages, when the source told us in the listing.
  static int? pages(BooruItem item) {
    final int? count = item.fileCountHint.value;
    return (count != null && count > 0) ? count : null;
  }

  /// The tags a card shows: favourites first, then the site's own order, with
  /// the language and the category left out - they have their own place on
  /// the card.
  static List<Tag> cardTags(
    BooruItem item,
    BooruHandler handler, {
    required bool Function(String tag) isStarred,
  }) {
    final List<Tag> marked = [];
    final List<Tag> rest = [];
    for (final Tag tag in item.tagsList) {
      final String? ns = handler.tagNamespace(tag.fullString);
      final String name = _bare(tag.fullString);
      if (ns == 'language' || ns == 'category') continue;
      if (ns == null && (languageCodes.containsKey(name) || categoryLabels.containsKey(name))) continue;
      (isStarred(tag.fullString) ? marked : rest).add(tag);
    }
    return [...marked, ...rest];
  }

  static String _bare(String tag) {
    final int i = tag.indexOf(':');
    return (i == -1 ? tag : tag.substring(i + 1)).toLowerCase();
  }

  static String _spell(String name) => name
      .replaceAll('_', ' ')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}
