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
      // r46: every fixed list, not only sort/order and rating (Civitai's NSFW
      // level, Rule34.dev's source, Sankaku's parent:): the handler parses
      // them. Only sort and order lists drop ascending twins and technical
      // values; a list keeps a real `none`.
      if (tag.keyName.isEmpty || groups.any((g) => g.key == tag.keyName)) continue;
      final Set<String> seen = {''};
      final List<DoujinFilterOption> options = [
        const DoujinFilterOption('', 'Site default'),
        for (final MetaTagValue v in tag.values)
          if ((!isSort || _keep(v)) && seen.add(v.value)) DoujinFilterOption(v.value, v.name),
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

/// Whole engines' search options as Filters (r45), from their own help pages
/// and checked against the live sites on 2026-09-15. Every group is one
/// choice: these engines do not combine a repeated metatag.
class BooruEngineFilters {
  const BooruEngineFilters._();

  /// danbooru's help:cheatsheet (danbooru, AiBooru, AllTheFallen). Live:
  /// age:<1w, filetype:mp4, is:parent/has:children, score:>=100, rating:q,e,
  /// status:deleted, commentary:true.
  static const DoujinFilterSpec danbooru = DoujinFilterSpec([
    DoujinFilterGroup(
      key: 'order',
      label: 'Order',
      options: [
        DoujinFilterOption('', 'Newest (site default)'),
        DoujinFilterOption('rank', 'Hot'),
        DoujinFilterOption('score', 'Score'),
        DoujinFilterOption('favcount', 'Favorites'),
        DoujinFilterOption('upvotes', 'Upvotes'),
        DoujinFilterOption('comment_bumped', 'Recently commented'),
        DoujinFilterOption('change', 'Recently updated'),
        DoujinFilterOption('mpixels', 'Largest resolution'),
        DoujinFilterOption('filesize', 'Largest files'),
        DoujinFilterOption('landscape', 'Landscape'),
        DoujinFilterOption('portrait', 'Portrait'),
        DoujinFilterOption('random', 'Random'),
      ],
    ),
    DoujinFilterGroup(
      key: 'rating',
      label: 'Rating',
      options: [
        DoujinFilterOption('', 'All'),
        DoujinFilterOption('general', 'General'),
        DoujinFilterOption('sensitive', 'Sensitive'),
        DoujinFilterOption('questionable', 'Questionable'),
        DoujinFilterOption('explicit', 'Explicit'),
        DoujinFilterOption('g,s', 'Safe for work'),
        DoujinFilterOption('q,e', 'Not safe for work'),
      ],
    ),
    DoujinFilterGroup(
      key: 'filetype',
      label: 'File type',
      options: [
        DoujinFilterOption('', 'Any'),
        DoujinFilterOption('jpg', 'JPG'),
        DoujinFilterOption('png', 'PNG'),
        DoujinFilterOption('gif', 'GIF'),
        DoujinFilterOption('mp4', 'MP4 video'),
        DoujinFilterOption('webm', 'WebM video'),
        DoujinFilterOption('zip', 'Ugoira (zip)'),
        DoujinFilterOption('swf', 'Flash'),
      ],
    ),
    DoujinFilterGroup(
      key: 'age',
      label: 'Posted within',
      options: [
        DoujinFilterOption('', 'Any time'),
        DoujinFilterOption('<1d', 'A day'),
        DoujinFilterOption('<1w', 'A week'),
        DoujinFilterOption('<1mo', 'A month'),
        DoujinFilterOption('<1y', 'A year'),
      ],
    ),
    DoujinFilterGroup(
      key: 'score',
      label: 'Score',
      options: [
        DoujinFilterOption('', 'Any'),
        DoujinFilterOption('>=10', '10+'),
        DoujinFilterOption('>=50', '50+'),
        DoujinFilterOption('>=100', '100+'),
        DoujinFilterOption('>=500', '500+'),
      ],
    ),
    DoujinFilterGroup(
      key: 'favcount',
      label: 'Favorites',
      options: [
        DoujinFilterOption('', 'Any'),
        DoujinFilterOption('>=10', '10+'),
        DoujinFilterOption('>=50', '50+'),
        DoujinFilterOption('>=100', '100+'),
        DoujinFilterOption('>=500', '500+'),
      ],
    ),
    DoujinFilterGroup(
      key: 'status',
      label: 'Status',
      options: [
        DoujinFilterOption('', 'Active (site default)'),
        DoujinFilterOption('pending', 'Pending'),
        DoujinFilterOption('flagged', 'Flagged'),
        DoujinFilterOption('appealed', 'Appealed'),
        DoujinFilterOption('modqueue', 'Mod queue'),
        DoujinFilterOption('deleted', 'Deleted'),
        DoujinFilterOption('any', 'Everything, deleted too'),
      ],
    ),
    DoujinFilterGroup(
      key: 'parent',
      label: 'Child post',
      options: [DoujinFilterOption('', 'Any'), DoujinFilterOption('any', 'Is a child'), DoujinFilterOption('none', 'Not a child')],
    ),
    DoujinFilterGroup(
      key: 'child',
      label: 'Parent post',
      options: [DoujinFilterOption('', 'Any'), DoujinFilterOption('any', 'Has children'), DoujinFilterOption('none', 'No children')],
    ),
    DoujinFilterGroup(
      key: 'commentary',
      label: 'Artist commentary',
      options: [
        DoujinFilterOption('', 'Any'),
        DoujinFilterOption('true', 'Has commentary'),
        DoujinFilterOption('translated', 'Translated'),
        DoujinFilterOption('untranslated', 'Untranslated'),
        DoujinFilterOption('false', 'No commentary'),
      ],
    ),
    DoujinFilterGroup(
      key: 'duration',
      label: 'Animation length',
      options: [
        DoujinFilterOption('', 'Any'),
        DoujinFilterOption('<10', 'Under 10 s'),
        DoujinFilterOption('>10', '10 s+'),
        DoujinFilterOption('>30', '30 s+'),
        DoujinFilterOption('>60', '1 min+'),
      ],
    ),
  ]);

  /// The gelbooru engine's cheat sheet. gelbooru.com rates general,
  /// sensitive, questionable, explicit; the booru.org sites (rule34.xxx, tbib,
  /// xbooru) safe, questionable, explicit. rule34.xxx adds aspectratio:.
  /// Live on tbib and xbooru: score:>=10, width:>=1920, sort:random,
  /// sort:updated:desc.
  static DoujinFilterSpec gelbooru({required bool booruOrgRatings, bool aspectRatio = false}) => DoujinFilterSpec([
    const DoujinFilterGroup(
      key: 'sort',
      label: 'Sort',
      options: [
        DoujinFilterOption('', 'Newest (site default)'),
        DoujinFilterOption('score', 'Score'),
        DoujinFilterOption('updated', 'Recently updated'),
        DoujinFilterOption('random', 'Random'),
        DoujinFilterOption('id:asc', 'Oldest first'),
        DoujinFilterOption('width', 'Widest'),
        DoujinFilterOption('height', 'Tallest'),
      ],
    ),
    DoujinFilterGroup(
      key: 'rating',
      label: 'Rating',
      options: booruOrgRatings
          ? const [
              DoujinFilterOption('', 'All'),
              DoujinFilterOption('safe', 'Safe'),
              DoujinFilterOption('questionable', 'Questionable'),
              DoujinFilterOption('explicit', 'Explicit'),
            ]
          : const [
              DoujinFilterOption('', 'All'),
              DoujinFilterOption('general', 'General'),
              DoujinFilterOption('sensitive', 'Sensitive'),
              DoujinFilterOption('questionable', 'Questionable'),
              DoujinFilterOption('explicit', 'Explicit'),
            ],
    ),
    const DoujinFilterGroup(
      key: 'score',
      label: 'Score',
      options: [
        DoujinFilterOption('', 'Any'),
        DoujinFilterOption('>=10', '10+'),
        DoujinFilterOption('>=50', '50+'),
        DoujinFilterOption('>=100', '100+'),
        DoujinFilterOption('>=500', '500+'),
      ],
    ),
    const DoujinFilterGroup(
      key: 'width',
      label: 'Width',
      options: [
        DoujinFilterOption('', 'Any'),
        DoujinFilterOption('>=1280', '1280+'),
        DoujinFilterOption('>=1920', 'Full HD+'),
        DoujinFilterOption('>=3840', '4K+'),
      ],
    ),
    const DoujinFilterGroup(
      key: 'height',
      label: 'Height',
      options: [
        DoujinFilterOption('', 'Any'),
        DoujinFilterOption('>=720', '720+'),
        DoujinFilterOption('>=1080', '1080+'),
        DoujinFilterOption('>=2160', '2160+'),
      ],
    ),
    if (aspectRatio)
      const DoujinFilterGroup(
        key: 'aspectratio',
        label: 'Aspect ratio',
        options: [
          DoujinFilterOption('', 'Any'),
          DoujinFilterOption('16:9', '16:9'),
          DoujinFilterOption('4:3', '4:3'),
          DoujinFilterOption('1:1', 'Square'),
          DoujinFilterOption('9:16', '9:16 (phone)'),
        ],
      ),
  ]);
}
