import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/image/booru_favicon.dart';

/// "Find this post elsewhere": queries every other configured booru for the
/// item's MD5 and lists where the same file exists, with resolution / tag
/// count compared against the copy being viewed. Tapping a hit opens an
/// `md5:` search tab on that booru (inheriting the current tab group), so
/// jumping from a For You / mirror copy to the original with better tags is
/// one tap.

/// MD5 of [item]: the API-provided hash when the handler parsed one,
/// otherwise a 32-hex run extracted from the file/sample/thumb URL (most
/// boorus name files by their MD5).
String? md5ForItem(BooruItem item) {
  final String? direct = item.md5String;
  // Some handlers stuff non-MD5 hashes in md5String (hydrus sha256, merge
  // sha1) — only trust exact 32-hex.
  if (direct != null && RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(direct)) {
    return direct.toLowerCase();
  }
  for (final url in [item.fileURL, item.sampleURL, item.thumbnailURL]) {
    final match = RegExp('[a-fA-F0-9]{32}').firstMatch(url);
    if (match != null) return match.group(0)!.toLowerCase();
  }
  return null;
}

/// MD5 metatag search string for [type], or null when the site has no
/// MD5 lookup (those boorus are skipped entirely rather than shown as
/// misleading "not found").
String? _md5QueryFor(BooruType? type, String md5) {
  switch (type) {
    // Shimmie2 family uses hash= for MD5.
    case BooruType.Shimmie:
    case BooruType.R34Hentai:
      return 'hash=$md5';
    case BooruType.Danbooru:
    case BooruType.Gelbooru:
    case BooruType.GelbooruV1:
    case BooruType.GelbooruAlike:
    case BooruType.Realbooru:
    case BooruType.Moebooru:
    case BooruType.e621:
    case BooruType.Sankaku:
    case BooruType.IdolSankaku:
    case BooruType.AGNPH:
    case BooruType.Rule34Dev:
    case BooruType.R34US:
    case BooruType.World:
      return 'md5:$md5';
    default:
      return null;
  }
}

enum _LookupState { loading, found, notFound, error }

enum _IqdbState { idle, loading, done, error }

class _IqdbMatch {
  _IqdbMatch({
    required this.url,
    required this.similarity,
    this.thumbUrl,
    this.dims,
    this.rating,
  });

  final String url;
  final int similarity;
  final String? thumbUrl;
  final String? dims;
  final String? rating;

  /// Pretty site name from known IQDB-indexed hosts; bare host otherwise.
  String get siteName {
    final host = Uri.tryParse(url)?.host.replaceFirst('www.', '') ?? '';
    const names = {
      'danbooru.donmai.us': 'Danbooru',
      'gelbooru.com': 'Gelbooru',
      'yande.re': 'Yande.re',
      'konachan.com': 'Konachan',
      'chan.sankakucomplex.com': 'Sankaku',
      'e-shuushuu.net': 'E-Shuushuu',
      'zerochan.net': 'Zerochan',
      'anime-pictures.net': 'Anime-Pictures',
    };
    return names[host] ?? host;
  }
}

class _LookupResult {
  _LookupResult(this.booru, this.query);

  final Booru booru;
  final String query;
  _LookupState state = _LookupState.loading;
  BooruItem? item;
}

Future<void> showFindElsewhereSheet(
  BuildContext context,
  BooruItem item,
  Booru? sourceBooru,
) async {
  final String? md5 = md5ForItem(item);
  if (md5 == null) {
    FlashElements.showSnackbar(
      context: context,
      title: const Text('No MD5 available'),
      content: const Text('This post has no hash to search for.'),
      leadingIcon: Symbols.search_off_rounded,
      sideColor: Colors.orange,
    );
    return;
  }

  // Every configured booru with MD5 search support, except the one this
  // copy already lives on (matched by host so virtual feeds exclude the
  // true origin, not the feed itself).
  final String? sourceHost = Uri.tryParse(sourceBooru?.baseURL ?? '')?.host;
  final String? postHost = Uri.tryParse(item.postURL)?.host;
  final candidates = <_LookupResult>[];
  for (final booru in SettingsHandler.instance.booruList) {
    final String? query = _md5QueryFor(booru.type, md5);
    if (query == null) continue;
    final String? host = Uri.tryParse(booru.baseURL ?? '')?.host;
    if (host != null && host.isNotEmpty && (host == sourceHost || host == postHost)) continue;
    candidates.add(_LookupResult(booru, query));
  }

  if (candidates.isEmpty) {
    FlashElements.showSnackbar(
      context: context,
      title: const Text('No boorus to search'),
      content: const Text('None of your other boorus support MD5 lookup.'),
      leadingIcon: Symbols.search_off_rounded,
      sideColor: Colors.orange,
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _FindElsewhereSheet(
      original: item,
      sourceBooru: sourceBooru,
      md5: md5,
      results: candidates,
    ),
  );
}

class _FindElsewhereSheet extends StatefulWidget {
  const _FindElsewhereSheet({
    required this.original,
    required this.sourceBooru,
    required this.md5,
    required this.results,
  });

  final BooruItem original;
  final Booru? sourceBooru;
  final String md5;
  final List<_LookupResult> results;

  @override
  State<_FindElsewhereSheet> createState() => _FindElsewhereSheetState();
}

class _FindElsewhereSheetState extends State<_FindElsewhereSheet> {
  _IqdbState iqdbState = _IqdbState.idle;
  List<_IqdbMatch> iqdbMatches = [];
  String iqdbError = '';
  bool showWeakIqdbMatches = false;

  // IQDB's own relevance threshold sits around 80% — anything below is
  // labelled "possible" and is nearly always noise, especially for content
  // outside its anime index.
  static const int _iqdbConfidence = 80;

  /// Image used for similarity/reverse searches: videos have no still to
  /// compare, so use the preview thumbnail; for images prefer the sample.
  String get _searchImageUrl {
    final BooruItem item = widget.original;
    return item.mediaType.value.isVideo
        ? item.thumbnailURL
        : (item.sampleURL.isNotEmpty ? item.sampleURL : item.thumbnailURL);
  }

  @override
  void initState() {
    super.initState();
    for (final r in widget.results) {
      _lookup(r);
    }
  }

  /// Similarity search: upload the sample/thumbnail image to iqdb.org (no
  /// API key needed) and parse the returned HTML for matches. Catches
  /// resized/recompressed copies that the exact-MD5 lookup can't.
  Future<void> _runIqdb() async {
    setState(() {
      iqdbState = _IqdbState.loading;
      iqdbError = '';
    });
    try {
      final headers = await Tools.getFileCustomHeaders(
        widget.sourceBooru,
        item: widget.original,
        checkForReferer: true,
      );
      final imgRes = await DioNetwork.get(
        _searchImageUrl,
        headers: headers,
        options: Options(responseType: ResponseType.bytes),
      ).timeout(const Duration(seconds: 20));
      final bytes = imgRes.data as List<int>;

      final res = await DioNetwork.post(
        'https://iqdb.org/',
        data: FormData.fromMap({
          'MAX_FILE_SIZE': '8388608',
          'file': MultipartFile.fromBytes(bytes, filename: 'image.jpg'),
        }),
        headers: {'User-Agent': Tools.browserUserAgent},
        options: Options(responseType: ResponseType.plain),
        // IQDB streams the response and queues queries under load, keeping
        // the connection open (with keep-alive script chunks) until the
        // result is ready — allow it several minutes before giving up.
      ).timeout(const Duration(minutes: 4));

      final matches = _parseIqdb(res.data.toString());
      if (!mounted) return;
      setState(() {
        iqdbMatches = matches;
        iqdbState = _IqdbState.done;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        iqdbError = e.toString();
        iqdbState = _IqdbState.error;
      });
    }
  }

  List<_IqdbMatch> _parseIqdb(String body) {
    final doc = html_parser.parse(body);
    final matches = <_IqdbMatch>[];
    // IQDB reports backend hiccups ("Can't read query result! Please try
    // again.", per-IP query limits, ...) inside a div.err — surface those as
    // retryable errors, never as a false "no matches".
    final String? err = doc.querySelector('.err')?.text.trim();
    if (err != null && err.isNotEmpty) {
      throw Exception(err);
    }
    // Result layout: #pages holds one table per match (first is "Your
    // image"); #more1 holds the collapsed low-similarity "possible" ones.
    final tables = [
      ...doc.querySelectorAll('#pages table'),
      ...doc.querySelectorAll('#more1 table'),
    ];
    for (final table in tables) {
      final text = table.text;
      final simMatch = RegExp(r'(\d+)% similarity').firstMatch(text);
      if (simMatch == null) continue; // the "Your image" table has no score
      final link = table.querySelector('td.image a')?.attributes['href'] ??
          table.querySelector('a')?.attributes['href'];
      if (link == null || link.isEmpty) continue;
      final String url = link.startsWith('//') ? 'https:$link' : link;
      String? thumb = table.querySelector('td.image img')?.attributes['src'];
      if (thumb != null && thumb.startsWith('/')) thumb = 'https://iqdb.org$thumb';
      final dimsMatch = RegExp(r'(\d+)[×x](\d+)').firstMatch(text);
      final ratingMatch = RegExp(r'\[(\w+)\]').firstMatch(text);
      matches.add(
        _IqdbMatch(
          url: url,
          similarity: int.parse(simMatch.group(1)!),
          thumbUrl: thumb,
          dims: dimsMatch == null ? null : '${dimsMatch.group(1)}×${dimsMatch.group(2)}',
          rating: ratingMatch?.group(1),
        ),
      );
    }
    matches.sort((a, b) => b.similarity.compareTo(a.similarity));
    return matches;
  }

  void _openIqdbMatch(_IqdbMatch m) {
    // If the match is on a booru the user has configured, jump in-app via an
    // id: search tab; otherwise hand off to the browser.
    final String? host = Uri.tryParse(m.url)?.host.replaceFirst('www.', '');
    final Booru? configured = SettingsHandler.instance.booruList.firstWhereOrNull((b) {
      final String? bh = Uri.tryParse(b.baseURL ?? '')?.host.replaceFirst('www.', '');
      return bh != null && bh.isNotEmpty && bh == host;
    });
    final RegExpMatch? idMatch = RegExp(r'(?:[?&]id=|/posts?/(?:show/)?)(\d+)').firstMatch(m.url);
    if (configured != null && idMatch != null) {
      SearchHandler.instance.addTabByString(
        'id:${idMatch.group(1)}',
        customBooru: configured,
        switchToNew: true,
        group: SearchHandler.inheritGroup,
      );
      Navigator.of(context).pop();
      FlashElements.showSnackbar(
        context: context,
        duration: const Duration(seconds: 2),
        title: Text('Opened on ${configured.name ?? 'booru'}'),
        content: const Text('The tab is behind the viewer — back out to see it.'),
        leadingIcon: Symbols.travel_explore_rounded,
        sideColor: Colors.green,
      );
    } else {
      launchUrlString(m.url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _lookup(_LookupResult r) async {
    if (r.state == _LookupState.error) {
      // Retry path.
      setState(() => r.state = _LookupState.loading);
    }
    try {
      // Throwaway mini-search, same pattern as the preview strips: never let
      // it write tag types into the shared store.
      final tab = SearchTab(r.booru, null, r.query);
      tab.booruHandler.storeTagsGlobally = false;
      tab.booruHandler.pageNum++;
      await tab.booruHandler.search(r.query, null).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (tab.booruHandler.errorString.isNotEmpty && tab.booruHandler.fetched.isEmpty) {
        setState(() => r.state = _LookupState.error);
        return;
      }
      // Raw fetched, not filtered — the user's hide-filters shouldn't make a
      // genuine hit look missing.
      final BooruItem? hit = tab.booruHandler.fetched.isNotEmpty ? tab.booruHandler.fetched.first : null;
      // VERIFY the hit: boorus that don't understand the md5 metatag (e.g.
      // rule34.xyz's POST search API) silently ignore it and return their
      // normal listing — "a result came back" is NOT "the file exists
      // there". Accept only when the hit's own hash equals the query, or —
      // when the hit exposes no hash at all — when the search returned
      // exactly one post (a real md5 lookup matches 0 or 1 posts, an
      // ignored filter returns a whole page).
      bool verified = false;
      if (hit != null) {
        final String? hitMd5 = md5ForItem(hit);
        verified = hitMd5 != null ? hitMd5 == widget.md5 : tab.booruHandler.fetched.length == 1;
      }
      setState(() {
        r.item = verified ? hit : null;
        r.state = verified ? _LookupState.found : _LookupState.notFound;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => r.state = _LookupState.error);
    }
  }

  void _openResult(_LookupResult r) {
    SearchHandler.instance.addTabByString(
      r.query,
      customBooru: r.booru,
      switchToNew: true,
      group: SearchHandler.inheritGroup,
    );
    Navigator.of(context).pop();
    FlashElements.showSnackbar(
      context: context,
      duration: const Duration(seconds: 2),
      title: Text('Opened on ${r.booru.name ?? 'booru'}'),
      content: const Text('The tab is behind the viewer — back out to see it.'),
      leadingIcon: Symbols.travel_explore_rounded,
      sideColor: Colors.green,
    );
  }

  /// "1920×1080 · higher res · 45 tags (+12)" — deltas vs the viewed copy.
  String _foundSubtitle(_LookupResult r) {
    final BooruItem found = r.item!;
    final BooruItem orig = widget.original;
    final parts = <String>[];

    final double? foundPx = (found.fileWidth != null && found.fileHeight != null)
        ? found.fileWidth! * found.fileHeight!
        : null;
    final double? origPx = (orig.fileWidth != null && orig.fileHeight != null)
        ? orig.fileWidth! * orig.fileHeight!
        : null;
    if (foundPx != null) {
      parts.add('${found.fileWidth!.round()}×${found.fileHeight!.round()}');
      if (origPx != null && origPx > 0) {
        if (foundPx > origPx * 1.05) {
          parts.add('higher res');
        } else if (foundPx * 1.05 < origPx) {
          parts.add('lower res');
        }
      }
    }

    final int foundTags = found.tagsList.length;
    final int diff = foundTags - orig.tagsList.length;
    parts.add('$foundTags tags${diff == 0 ? '' : ' (${diff > 0 ? '+' : ''}$diff)'}');

    return parts.join(' · ');
  }

  Widget _trailingFor(_LookupResult r) {
    switch (r.state) {
      case _LookupState.loading:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        );
      case _LookupState.found:
        return const Icon(Symbols.check_circle_rounded, color: Colors.green, fill: 1);
      case _LookupState.notFound:
        return Icon(Symbols.remove_circle_outline_rounded, color: Colors.grey.shade600);
      case _LookupState.error:
        return const Icon(Symbols.refresh_rounded, color: Colors.orange);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final int foundCount = widget.results.where((r) => r.state == _LookupState.found).length;
    final bool anyLoading = widget.results.any((r) => r.state == _LookupState.loading);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 2),
            width: 40,
            height: 4.5,
            decoration: BoxDecoration(
              color: const Color(0xFF4A4260),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Icon(Symbols.travel_explore_rounded, size: 20, color: theme.colorScheme.secondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    anyLoading
                        ? 'Searching your boorus…'
                        : foundCount == 0
                            ? 'Not found elsewhere'
                            : 'Also on $foundCount ${foundCount == 1 ? 'booru' : 'boorus'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'md5: ${widget.md5}',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500, fontFamily: 'monospace'),
              ),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                for (final r in widget.results)
                  ListTile(
                    enabled: r.state == _LookupState.found || r.state == _LookupState.error,
                    leading: BooruFavicon(r.booru, size: 22),
                    title: Text(
                      r.booru.name ?? '?',
                      style: TextStyle(
                        fontWeight: r.state == _LookupState.found ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                    subtitle: switch (r.state) {
                      _LookupState.loading => const Text('Searching…'),
                      _LookupState.found => Text(_foundSubtitle(r)),
                      _LookupState.notFound => const Text('Not found'),
                      _LookupState.error => const Text('Search failed — tap to retry'),
                    },
                    trailing: _trailingFor(r),
                    onTap: () {
                      if (r.state == _LookupState.found) {
                        _openResult(r);
                      } else if (r.state == _LookupState.error) {
                        _lookup(r);
                      }
                    },
                  ),
                const Divider(height: 8),
                ..._iqdbSection(theme),
                ..._browserSearchSection(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _iqdbSection(ThemeData theme) {
    switch (iqdbState) {
      case _IqdbState.idle:
        return [
          ListTile(
            leading: Icon(Symbols.image_search_rounded, color: theme.colorScheme.secondary),
            title: const Text('Similarity search (IQDB)', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Finds resized/recompressed copies on danbooru, gelbooru, yande.re…'),
            onTap: _runIqdb,
          ),
        ];
      case _IqdbState.loading:
        return [
          const ListTile(
            leading: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            title: Text('Searching IQDB…'),
            subtitle: Text('Can take a while when IQDB is busy — queries get queued'),
          ),
        ];
      case _IqdbState.error:
        return [
          ListTile(
            leading: const Icon(Symbols.refresh_rounded, color: Colors.orange),
            title: const Text('IQDB search failed — tap to retry'),
            subtitle: Text(iqdbError, maxLines: 2, overflow: TextOverflow.ellipsis),
            onTap: _runIqdb,
          ),
        ];
      case _IqdbState.done:
        // Confidence gate: below IQDB's own ~80% relevance bar the "matches"
        // are visually unrelated noise, so they hide behind an expander
        // instead of polluting the list with false hope.
        final strong = iqdbMatches.where((m) => m.similarity >= _iqdbConfidence).toList();
        final weak = iqdbMatches.where((m) => m.similarity < _iqdbConfidence).toList();
        return [
          if (strong.isEmpty)
            const ListTile(
              leading: Icon(Symbols.search_off_rounded),
              title: Text('No confident IQDB matches'),
              subtitle: Text("IQDB indexes drawn/anime boorus — 3D and real content usually won't match"),
            ),
          for (final m in strong) _iqdbMatchTile(m),
          if (weak.isNotEmpty && !showWeakIqdbMatches)
            ListTile(
              dense: true,
              leading: const Icon(Symbols.expand_more_rounded),
              title: Text('Show ${weak.length} low-confidence ${weak.length == 1 ? 'match' : 'matches'}'),
              subtitle: const Text('Below 80% similarity — almost always unrelated'),
              onTap: () => setState(() => showWeakIqdbMatches = true),
            ),
          if (showWeakIqdbMatches) ...weak.map(_iqdbMatchTile),
        ];
    }
  }

  Widget _iqdbMatchTile(_IqdbMatch m) {
    return ListTile(
      leading: m.thumbUrl == null
          ? const Icon(Symbols.image_rounded)
          : ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                m.thumbUrl!,
                width: 42,
                height: 42,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(Symbols.image_rounded),
              ),
            ),
      title: Text(
        '${m.siteName} — ${m.similarity}% match',
        style: TextStyle(fontWeight: m.similarity >= _iqdbConfidence ? FontWeight.w700 : FontWeight.w400),
      ),
      subtitle: Text(
        [
          if (m.dims != null) m.dims!,
          if (m.rating != null) m.rating!,
        ].join(' · '),
      ),
      trailing: const Icon(Symbols.open_in_new_rounded, size: 18),
      onTap: () => _openIqdbMatch(m),
    );
  }

  /// External reverse-image engines, opened in the browser with the image
  /// URL prefilled. Yandex in particular has far broader coverage of
  /// reposted content than any booru-specific index.
  List<Widget> _browserSearchSection(ThemeData theme) {
    final String img = Uri.encodeComponent(_searchImageUrl);
    final engines = <(String, String)>[
      ('Yandex', 'https://yandex.com/images/search?rpt=imageview&url=$img'),
      ('Google Lens', 'https://lens.google.com/uploadbyurl?url=$img'),
      ('SauceNAO', 'https://saucenao.com/search.php?url=$img'),
    ];
    return [
      const Divider(height: 8),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reverse search in browser',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final (name, url) in engines)
                  ActionChip(
                    avatar: Icon(Symbols.open_in_new_rounded, size: 16, color: theme.colorScheme.secondary),
                    label: Text(name),
                    onPressed: () => launchUrlString(url, mode: LaunchMode.externalApplication),
                  ),
              ],
            ),
          ],
        ),
      ),
    ];
  }
}
