import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_tag_store.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';

/// A tag's type for display, the one answer the tag list, the tag sheet, the
/// hubs and "More from" share (r50).
class TagTypeLookup {
  const TagTypeLookup._();

  /// Your correction for [booru] first; then the type [handler] parsed for
  /// its own items (kept even where the app-wide store is not written: a
  /// strip's preview tab, the floating preview); then the app-wide store
  /// (a booru store, so never on a doujin source); then the type the tag
  /// itself carries.
  static TagType resolve(Tag tag, {required Booru booru, BooruHandler? handler}) {
    final TagType? mine = BooruTagStore.manualType(tag.fullString, booru);
    if (mine != null) return mine;
    final TagType? own = handler?.ownTagType(tag.fullString);
    if (own != null && own != TagType.none) return own;
    if (!DoujinDataHandler.isDoujinBooru(booru) && TagHandler.instance.hasTag(tag.fullString)) {
      final TagType stored = TagHandler.instance.getTag(tag.fullString).tagType;
      if (stored != TagType.none) return stored;
    }
    return tag.tagType;
  }
}
