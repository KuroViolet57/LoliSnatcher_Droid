import 'package:lolisnatcher/src/boorus/doujin/doujin_filters.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_utils.dart';
import 'package:lolisnatcher/src/handlers/booru_tag_catalog.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';

class PhilomenaHandler extends BooruHandler {
  PhilomenaHandler(super.booru, super.limit);

  /// Artists, characters, species, franchises and general tags from the tag
  /// search API (see PhilomenaTagIndex).
  @override
  late final TagCatalogSource? tagCatalog = BooruTagCatalog.forHandler(this);

  @override
  bool get hasTagSuggestions => true;

  @override
  String validateTags(String tags) {
    if (tags == '' || tags == ' ') {
      return '*';
    } else {
      return tags;
    }
  }

  @override
  String translateOrSyntax(String tags) {
    if (!tags.contains('|')) return tags;
    return tags
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .map((token) {
          if (!token.contains('|')) return token;
          final parts = token.split('|').where((p) => p.isNotEmpty).toList();
          if (parts.isEmpty) return '';
          if (parts.length == 1) return parts.first;
          return '(${parts.join(' || ')})';
        })
        .where((s) => s.isNotEmpty)
        .join(' ');
  }

  @override
  List parseListFromResponse(dynamic response) {
    final Map<String, dynamic> parsedResponse = response.data;
    return (parsedResponse['images'] ?? []) as List;
  }

  @override
  BooruItem? parseItemFromResponse(dynamic responseItem, int index) {
    final current = responseItem as Map<String, dynamic>;
    if (current['representations']['full'] != null) {
      String sampleURL = current['representations']['medium'], thumbURL = current['representations']['thumb_small'];
      if (current['mime_type'].toString().contains('video')) {
        final String tmpURL = "${sampleURL.substring(0, sampleURL.lastIndexOf("/") + 1)}thumb.gif";
        sampleURL = tmpURL;
        thumbURL = tmpURL;
      }

      String fileURL = current['representations']['full'];
      if (!fileURL.contains('http')) {
        sampleURL = booru.baseURL! + sampleURL;
        thumbURL = booru.baseURL! + thumbURL;
        fileURL = booru.baseURL! + fileURL;
      }

      final List<String> currentTags = current['tags'].toString().substring(1, current['tags'].toString().length - 1).split(', ');
      for (int x = 0; x < currentTags.length; x++) {
        currentTags[x] = currentTags[x].replaceAll(' ', '_');
      }
      final BooruItem item = BooruItem(
        fileURL: fileURL,
        fileWidth: current['width']?.toDouble(),
        fileHeight: current['height']?.toDouble(),
        fileSize: current['size'],
        sampleURL: sampleURL,
        thumbnailURL: thumbURL,
        tagsList: currentTags.map(Tag.new).toList(),
        postURL: makePostURL(current['id'].toString()),
        serverId: current['id'].toString(),
        score: current['score'].toString(),
        sources: [current['source_url'].toString()],
        postDate: current['created_at'],
        postDateFormat: 'iso',
        fileNameExtras: "${booru.name}_${current['id']}_",
      );

      return item;
    } else {
      return null;
    }
  }

  @override
  String makePostURL(String id) {
    return '${booru.baseURL}/images/$id';
  }

  String formatTagsWithUnderscores(String tags) => formatTagsWithUnderscoresPhilomena(tags);

  @override
  String makeURL(String tags) {
    // EXAMPLE: https://derpibooru.org/api/v1/json/search/images?q=solo&per_page=20&page=1
    // r43: the site filter (derpibooru), sort field and direction come as
    // filter:/sf:/sd: terms from the Filters card and go to the URL.
    String first(String key) {
      final List<String> v = DoujinFilters.selected(tags, key);
      return v.isEmpty ? '' : v.first;
    }

    final String chosen = first('filter');
    final String sf = first('sf');
    final String sd = first('sd');
    final String words = DoujinFilters.strip(DoujinFilters.strip(DoujinFilters.strip(tags, 'filter'), 'sf'), 'sd');
    final String? picked = _isDerpibooru ? derpibooruFilters[chosen] : null;
    final String filter = picked ?? (_isDerpibooru ? '56027' : '2');
    final String sort = '${sf.isEmpty ? '' : '&sf=$sf'}${sd.isEmpty ? '' : '&sd=$sd'}';

    final formattedTags = formatTagsWithUnderscores(words).replaceAll(' ', ',');
    if (booru.apiKey?.isEmpty ?? true) {
      return '${booru.baseURL}/api/v1/json/search/images?filter_id=$filter&q=$formattedTags&per_page=$limit&page=$pageNum$sort';
    } else {
      final String filterParam = picked == null ? '' : '&filter_id=$picked';
      return '${booru.baseURL}/api/v1/json/search/images?key=${booru.apiKey}&q=$formattedTags&per_page=$limit&page=$pageNum$filterParam$sort';
    }
  }

  /// Derpibooru's system filters (the site's /api/v1/json/filters/system,
  /// 2026-09-15): Everything shows all; Default and Legacy default hide explicit.
  static const Map<String, String> derpibooruFilters = {
    'everything': '56027',
    'default': '100073',
    'legacy': '37431',
    'r34': '37432',
    'dark': '37429',
    'spoilers': '37430',
  };

  bool get _isDerpibooru => booru.baseURL?.contains('derpibooru') ?? false;

  @override
  DoujinFilterSpec get doujinFilters => DoujinFilterSpec([
    if (_isDerpibooru)
      const DoujinFilterGroup(
        key: 'filter',
        label: 'Site filter',
        defaultValue: 'everything',
        options: [
          DoujinFilterOption('everything', 'Everything'),
          DoujinFilterOption('default', 'Default (hides explicit)'),
          DoujinFilterOption('legacy', 'Legacy default'),
          DoujinFilterOption('r34', '18+ R34'),
          DoujinFilterOption('dark', '18+ Dark'),
          DoujinFilterOption('spoilers', 'Maximum spoilers'),
        ],
      ),
    const DoujinFilterGroup(
      key: 'sf',
      label: 'Sort',
      defaultValue: '',
      options: [
        DoujinFilterOption('', 'Newest (site default)'),
        DoujinFilterOption('score', 'Score'),
        DoujinFilterOption('wilson_score', 'Best (Wilson score)'),
        DoujinFilterOption('faves', 'Favorites'),
        DoujinFilterOption('upvotes', 'Upvotes'),
        DoujinFilterOption('first_seen_at', 'First seen'),
        DoujinFilterOption('random', 'Random'),
      ],
    ),
    const DoujinFilterGroup(
      key: 'sd',
      label: 'Direction',
      defaultValue: '',
      options: [DoujinFilterOption('', 'Descending (default)'), DoujinFilterOption('asc', 'Ascending')],
    ),
  ]);

  @override
  String makeTagURL(String input) {
    if (input.isEmpty) {
      input = '*';
    }
    return '${booru.baseURL}/api/v1/json/search/tags?q=*${formatTagsWithUnderscores(input)}*&per_page=20';
  }

  @override
  List parseTagSuggestionsList(dynamic response) {
    final Map<String, dynamic> parsedResponse = response.data;
    return parsedResponse['tags'];
  }

  @override
  TagSuggestion? parseTagSuggestion(dynamic responseItem, int index) {
    final List tagStringReplacements = [
      ['-colon-', ':'],
      ['-dash-', '-'],
      ['-fwslash-', '/'],
      ['-bwslash-', r'\'],
      ['-dot-', '.'],
      ['-plus-', '+'],
    ];

    String tag = responseItem['slug'].toString();
    for (int x = 0; x < tagStringReplacements.length; x++) {
      tag = tag.replaceAll(tagStringReplacements[x][0], tagStringReplacements[x][1]);
    }

    if (tag.contains('_')) {
      tag = '"$tag"';
    }

    tag = tag.replaceAll('+', '_');

    return TagSuggestion(tag: tag);
  }
}
