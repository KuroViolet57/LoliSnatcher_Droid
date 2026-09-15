import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/doujin_filters.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';

/// A booru source's Filters (r43), made from the metatags its handler already
/// declares: every sort/order metatag and the rating metatag with a fixed
/// list of values becomes one single choice, "Site default" first. The
/// handlers already encode each site's own words (danbooru's `order:rank`,
/// gelbooru's `sort:score`, and so on), so two sites on one engine keep their
/// differences. Ascending twins and technical orders are left out.
class BooruSiteFilters {
  const BooruSiteFilters._();

  static const Set<String> _technical = {'md5', 'custom', 'none', 'modqueue'};

  static bool _keep(MetaTagValue v) {
    final String value = v.value.toLowerCase();
    if (value.isEmpty || _technical.contains(value)) return false;
    if (value.endsWith('asc') || v.name.toLowerCase().contains('ascending')) return false;
    return true;
  }

  static DoujinFilterSpec? fromMetaTags(List<MetaTag> metaTags) {
    final List<DoujinFilterGroup> groups = [];
    for (final MetaTag tag in metaTags) {
      if (tag is! MetaTagWithValues || tag.divider != ':') continue;
      final bool isSort = tag is SortMetaTag || tag is OrderMetaTag || tag.type.isSort;
      final bool isRating = tag.keyName == 'rating';
      if (!isSort && !isRating) continue;
      if (groups.any((g) => g.key == tag.keyName)) continue;
      final List<DoujinFilterOption> options = [
        const DoujinFilterOption('', 'Site default'),
        for (final MetaTagValue v in tag.values)
          if (_keep(v)) DoujinFilterOption(v.value, v.name),
      ];
      if (options.length < 2) continue;
      groups.add(DoujinFilterGroup(key: tag.keyName, label: tag.name, options: options));
    }
    return groups.isEmpty ? null : DoujinFilterSpec(groups);
  }
}

/// What the app knows about a booru source (r43), for its settings page:
/// quirks checked against the live sites on 2026-09-15, then what the
/// handler supports.
class BooruSiteNotes {
  const BooruSiteNotes._();

  static List<String> notesFor(Booru booru, BooruHandler handler) {
    final String host = Uri.tryParse(booru.baseURL ?? '')?.host ?? '';
    final List<String> notes = [];
    switch (booru.type) {
      case BooruType.Gelbooru || BooruType.GelbooruAlike:
        if (host.contains('gelbooru.com')) {
          notes.add('gelbooru.com answers its API only with an API key and user ID (Account above); without them searches come back empty.');
        } else if (host.contains('rule34.xxx')) {
          notes.add("rule34.xxx's API needs an API key and user ID (Account above); without them it answers \"Missing authentication\".");
        } else if (host.contains('tbib') || host.contains('xbooru')) {
          notes.add('Accepts both rating vocabularies: general/sensitive and safe/questionable/explicit.');
          if (host.contains('xbooru')) notes.add('Some sorted searches meet a Cloudflare check; open the site once in the webview if one fails.');
        }
      case BooruType.Realbooru:
        notes.add('realbooru has switched its API off on its side ("API offline"): searches may fail until the site brings it back.');
      case BooruType.Danbooru:
        if (host.contains('danbooru.donmai.us')) {
          notes.add('Without Gold, a search takes at most 2 tags; rating: terms do not count. Default filters and always-add terms count toward it.');
        } else if (host.contains('allthefallen')) {
          notes.add("The site's API sits behind a Cloudflare check; if searches fail, open the site once in the webview.");
        }
      case BooruType.e621:
        notes.add('rating: and order: work as on the site; e6ai is the same engine.');
      case BooruType.Philomena:
        if (host.contains('derpibooru')) {
          notes.add('Site filter: Everything shows all; Default and Legacy default hide explicit content (0 explicit results under them).');
        }
      case BooruType.Shimmie:
        notes.add('rule34.paheal has no sort or rating options in its API.');
      case BooruType.FurAffinity:
        notes.add("FurAffinity's own sidebar has the account, the blocklist and the content filter.");
      case BooruType.Kemono || BooruType.Pawchive:
        notes.add("The site's own sidebar has the account, favourites and creator lists.");
      default:
        break;
    }
    if (handler.hasSignInSupport) notes.add('Supports signing in.');
    if (handler.hasSiteFavourites) notes.add('Favourites sync with the site while signed in.');
    if (handler.hasCommentsSupport) notes.add('Shows comments.');
    if (handler.hasNotesSupport) notes.add('Shows translation notes.');
    if (handler.hasTagSuggestions) notes.add('Suggests tags while you type.');
    if (handler.tagCatalog != null) notes.add('Has a tag builder in the search window.');
    return notes;
  }
}
