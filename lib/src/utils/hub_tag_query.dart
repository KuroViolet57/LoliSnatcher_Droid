import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';

/// The search a tag or artist hub sends to each source (r50).
class HubTagQuery {
  const HubTagQuery._();

  /// Tag-type namespaces some sites write into their tags (FurAffinity's
  /// `artist:name`); elsewhere they are not part of the tag.
  static const Set<String> typeNamespaces = {
    'artist',
    'character',
    'copyright',
    'species',
    'contributor',
    'lore',
    'meta',
    'general',
  };

  /// Sites whose own searches or tag names carry those namespaces.
  static const Set<BooruType> namespacedSites = {
    BooruType.FurAffinity,
    BooruType.Philomena,
    BooruType.Civitai,
    BooruType.Hanime1,
    BooruType.InkBunny,
    BooruType.Rule34Video,
    BooruType.XXXTik,
  };

  /// [tag] as [target] searches it: unchanged on its own source and on sites
  /// that use the namespace; elsewhere each `type:name` term becomes `name`
  /// (a leading `-` or `~` kept) — e621 answered nothing for `artist:name`.
  static String forBooru(String tag, {required Booru target, Booru? origin}) {
    if (origin != null && origin.name == target.name && origin.type == target.type) return tag;
    if (namespacedSites.contains(target.type)) return tag;
    final RegExp term = RegExp(r'^([-~]?)([a-z_]+):(.+)$', caseSensitive: false);
    return tag
        .split(' ')
        .map((t) {
          final RegExpMatch? m = term.firstMatch(t);
          if (m == null || !typeNamespaces.contains(m.group(2)!.toLowerCase())) return t;
          return '${m.group(1)}${m.group(3)}';
        })
        .join(' ');
  }
}
