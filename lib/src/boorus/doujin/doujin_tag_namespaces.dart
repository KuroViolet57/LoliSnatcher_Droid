import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';

/// How a doujin source's own tag namespaces map onto the app's tag types.
///
/// The app models a tag as a bare name plus a [TagType]; the namespace is
/// metadata the handler keeps on the side. Storing `artist:wakahi-chan` as the
/// tag's own name instead breaks a surprising amount at once: chips render the
/// raw prefix, the language badge looks for a tag literally called `english`
/// and never finds `language:english`, blacklists and favourite tags compare
/// against a namespace-stripped form and so never match, and the chip labels
/// get long enough to overflow the card. nhentai has always stored bare names
/// with a side table, and this is the same arrangement for every other source.
///
/// The mapping choices, where a namespace has no exact app equivalent:
///
///   * `circle` / `group` -> artist. A circle is who published the book; the
///     closest thing the booru model has is an artist, and nhentai already
///     maps its own `group` this way.
///   * `parody` / `series` -> copyright. Same concept under two names.
///   * `magazine` / `publisher` -> meta. They describe the edition rather than
///     its content, which is what meta is for, and it keeps them out of the
///     general tag soup on a card.
///   * `type` / `category` / `language` -> meta, matching nhentai.
///   * `female` / `male` / `mixed` -> none. These are ordinary content tags
///     that a few sources happen to file by whom they apply to. There is no
///     booru type for that, and inventing one would colour them differently
///     from the identical tag on another source.
///   * `other` / `misc` / `tag` -> none, the general case.
/// The [TagType]s the catalogs name in their const namespace lists.
const TagType doujinArtistType = TagType.artist;
const TagType doujinCopyrightType = TagType.copyright;
const TagType doujinCharacterType = TagType.character;
const TagType doujinMetaType = TagType.meta;
const TagType doujinNoneType = TagType.none;

TagType doujinTagTypeFor(String? namespace) => switch (namespace) {
  'artist' || 'circle' || 'group' => TagType.artist,
  'parody' || 'series' => TagType.copyright,
  'character' => TagType.character,
  'language' || 'type' || 'category' || 'magazine' || 'publisher' => TagType.meta,
  _ => TagType.none,
};

/// Keeps a source's tag namespaces beside its tags rather than inside them.
///
/// Handlers build tags through [namespacedTag], which stores the bare name on
/// the [Tag] and remembers the namespace here. [tagNamespace] then answers for
/// the grouped sections on the detail page, the language badge and the tag hub.
mixin DoujinNamespacedTags on BooruHandler {
  /// Bare tag name -> the namespace the source filed it under.
  ///
  /// One shared map per handler instance. A name claimed by two namespaces on
  /// the same source (rare, and nhentai has the same limitation) keeps the
  /// first one seen, so a tag does not flip sections as pages load.
  final Map<String, String> namespacesByTag = {};

  /// Builds a tag the way the rest of the app expects one: bare name, real
  /// [TagType], namespace remembered on the side.
  Tag namespacedTag(String rawName, String? namespace, {int count = -1}) {
    final String name = normalizeDoujinTagName(rawName);
    final String? ns = (namespace == null || namespace.isEmpty) ? null : namespace.toLowerCase();
    if (ns != null && ns != 'tag') {
      namespacesByTag.putIfAbsent(name, () => ns);
    }
    return Tag(name, tagType: doujinTagTypeFor(ns), count: count);
  }

  @override
  String? tagNamespace(String tag) {
    // A tag stored by an older build still carries its prefix inline, and
    // favourites and blacklists saved back then are still on disk. Reading the
    // prefix keeps those grouping correctly instead of silently falling into
    // the general section.
    final int colon = tag.indexOf(':');
    if (colon > 0) return tag.substring(0, colon);
    return namespacesByTag[tag];
  }

  /// The namespaced form of a bare tag, for sources whose SEARCH syntax needs
  /// the namespace back — hitomi resolves `ahegao` and `female:ahegao` to
  /// different indexes, so a chip has to round-trip to the qualified form even
  /// though it displays bare.
  String qualifyTag(String tag) {
    if (tag.contains(':')) return tag;
    final String? ns = namespacesByTag[tag];
    return ns == null ? tag : '$ns:$tag';
  }
}

/// Lowercase, underscored — the spelling the app compares tags in.
String normalizeDoujinTagName(String raw) =>
    raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
