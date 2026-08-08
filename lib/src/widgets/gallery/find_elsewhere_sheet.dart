import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_alias_resolver.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/image/booru_favicon.dart';

/// "Find elsewhere": looks a post up on the user's other boorus by pivoting
/// on one of its tags (artist/character preferred), with the tag's spelling
/// resolved per booru. Exact-file (MD5) matching was dropped — re-encoded
/// cross-site reposts (especially video/3D) never hash-match, so it returned
/// nothing in practice. IQDB similarity search and browser reverse-search
/// links round the sheet out.

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

/// One row of the "Related elsewhere" section: the pivot tag looked up on
/// another booru (spelling resolved per-site) with a post count.
class _RelatedResult {
  _RelatedResult(this.booru);

  final Booru booru;
  _LookupState state = _LookupState.loading;
  String resolvedTag = '';
  int count = 0;
  int totalCount = 0;
  bool get hasMore => totalCount == 0 && count >= 20;
}

Future<void> showFindElsewhereSheet(
  BuildContext context,
  BooruItem item,
  Booru? sourceBooru,
) async {
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _FindElsewhereSheet(
      original: item,
      sourceBooru: sourceBooru,
    ),
  );
}

class _FindElsewhereSheet extends StatefulWidget {
  const _FindElsewhereSheet({
    required this.original,
    required this.sourceBooru,
  });

  final BooruItem original;
  final Booru? sourceBooru;

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

  // Metadata pivot: the exact file rarely survives cross-site re-encoding
  // (especially video), but the same artist/character reliably exists on
  // other boorus under a resolvable tag — so pivot on that instead.
  String? pivotTag;
  TagType? pivotType;
  final List<_RelatedResult> related = [];

  @override
  void initState() {
    super.initState();
    _buildRelatedCandidates();
    // Auto-pivot on the narrowest useful typed tag: artist > character >
    // copyright. Boorus without tag-type data (shimmie etc.) leave this
    // null — the user picks the pivot tag manually instead.
    for (final type in [TagType.artist, TagType.character, TagType.copyright]) {
      final tag = widget.original.tagsList.firstWhereOrNull(
        (t) => t.tagType == type && t.fullString.trim().isNotEmpty,
      );
      if (tag != null) {
        pivotTag = tag.fullString.trim();
        pivotType = type;
        break;
      }
    }
    if (pivotTag != null) {
      for (final r in related) {
        _lookupRelated(r);
      }
    }
  }

  void _buildRelatedCandidates() {
    // Every real booru is a candidate — tag search works everywhere.
    // Virtual/local feeds and the post's own source stay out.
    const virtualTypes = {
      BooruType.Favourites,
      BooruType.Downloads,
      BooruType.Collections,
      BooruType.ForYou,
      BooruType.History,
      BooruType.Merge,
      BooruType.WebView,
    };
    final String? sourceHost = Uri.tryParse(widget.sourceBooru?.baseURL ?? '')?.host;
    final String? postHost = Uri.tryParse(widget.original.postURL)?.host;
    for (final booru in SettingsHandler.instance.booruList) {
      if (booru.type == null || virtualTypes.contains(booru.type)) continue;
      final String? host = Uri.tryParse(booru.baseURL ?? '')?.host;
      if (host != null && host.isNotEmpty && (host == sourceHost || host == postHost)) continue;
      related.add(_RelatedResult(booru));
    }
  }

  /// Sets a new pivot tag and reruns every booru lookup against it.
  void _restartRelated(String tag, TagType? type) {
    setState(() {
      pivotTag = tag;
      pivotType = type;
      for (final r in related) {
        r.state = _LookupState.loading;
        r.resolvedTag = '';
        r.count = 0;
        r.totalCount = 0;
      }
    });
    for (final r in related) {
      _lookupRelated(r);
    }
  }

  /// Manual pivot picker: full tag list of the post, typed tags first.
  /// This is the only way in for boorus that report no tag types at all.
  Future<void> _pickPivot() async {
    int rank(TagType t) => switch (t) {
          TagType.artist => 0,
          TagType.character => 1,
          TagType.copyright => 2,
          TagType.species => 3,
          TagType.meta => 5,
          _ => 4,
        };
    final tags = [...widget.original.tagsList]..sort((a, b) {
        final int byType = rank(a.tagType).compareTo(rank(b.tagType));
        return byType != 0 ? byType : a.fullString.compareTo(b.fullString);
      });
    if (tags.isEmpty) return;

    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pivot on which tag?'),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: SizedBox(
          width: double.maxFinite,
          height: 420,
          child: ListView.builder(
            itemCount: tags.length,
            itemBuilder: (_, i) {
              final t = tags[i];
              final bool typed = t.tagType != TagType.none;
              return ListTile(
                dense: true,
                title: Text(t.fullString),
                subtitle: typed ? Text(t.tagType.name) : null,
                selected: t.fullString == pivotTag,
                onTap: () => Navigator.of(ctx).pop(i),
              );
            },
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final t = tags[picked];
    _restartRelated(t.fullString.trim(), t.tagType == TagType.none ? null : t.tagType);
  }

  Future<void> _lookupRelated(_RelatedResult r) async {
    if (r.state == _LookupState.error) {
      setState(() => r.state = _LookupState.loading);
    }
    // The pivot may change while a slow lookup is in flight — bind this run
    // to the pivot it started with and drop the result if it went stale.
    final String? runPivot = pivotTag;
    if (runPivot == null) return;
    try {
      // Resolve the pivot's spelling on the target booru first (e.g.
      // `artistname` -> `artistname_(artist)`), then count what it has.
      String query = runPivot;
      try {
        final res = await TagAliasResolver.resolveQuery(query, r.booru).timeout(const Duration(seconds: 15));
        query = res.query;
      } catch (_) {}

      final tab = SearchTab(r.booru, null, query);
      tab.booruHandler.storeTagsGlobally = false;
      tab.booruHandler.pageNum++;
      await tab.booruHandler.search(query, null).timeout(const Duration(seconds: 15));
      if (!mounted || pivotTag != runPivot) return;
      if (tab.booruHandler.errorString.isNotEmpty && tab.booruHandler.fetched.isEmpty) {
        setState(() => r.state = _LookupState.error);
        return;
      }
      final int count = tab.booruHandler.fetched.length;
      if (count > 0 && tab.booruHandler.totalCount.value == 0) {
        try {
          await tab.booruHandler.searchCount(query).timeout(const Duration(seconds: 10));
        } catch (_) {}
      }
      if (!mounted || pivotTag != runPivot) return;
      setState(() {
        r.resolvedTag = query;
        r.count = count;
        r.totalCount = tab.booruHandler.totalCount.value;
        r.state = count > 0 ? _LookupState.found : _LookupState.notFound;
      });
    } catch (_) {
      if (!mounted || pivotTag != runPivot) return;
      setState(() => r.state = _LookupState.error);
    }
  }

  void _openRelated(_RelatedResult r) {
    SearchHandler.instance.addTabByString(
      r.resolvedTag,
      customBooru: r.booru,
      switchToNew: true,
      group: SearchHandler.inheritGroup,
    );
    Navigator.of(context).pop();
    FlashElements.showSnackbar(
      context: context,
      duration: const Duration(seconds: 2),
      title: Text('Opened on ${r.booru.name ?? 'booru'}'),
      content: Text('Searching "${r.resolvedTag}" — the tab is behind the viewer.'),
      leadingIcon: Symbols.travel_explore_rounded,
      sideColor: Colors.green,
    );
  }

  /// Similarity search: upload the sample/thumbnail image to iqdb.org (no
  /// API key needed) and parse the returned HTML for matches. Catches
  /// resized/recompressed copies of drawn content.
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
      _launchExternal(m.url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final int foundCount = related.where((r) => r.state == _LookupState.found).length;
    final bool anyLoading = pivotTag != null && related.any((r) => r.state == _LookupState.loading);

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
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Row(
              children: [
                Icon(Symbols.travel_explore_rounded, size: 20, color: theme.colorScheme.secondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    pivotTag == null
                        ? 'Find elsewhere'
                        : anyLoading
                            ? 'Searching your boorus…'
                            : foundCount == 0
                                ? 'Nothing related found'
                                : 'Related on $foundCount ${foundCount == 1 ? 'booru' : 'boorus'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                ..._relatedSection(theme),
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

  List<Widget> _relatedSection(ThemeData theme) {
    // No pivot yet (booru gave no tag types): prompt for a manual pick
    // instead of silently hiding the whole section.
    if (pivotTag == null) {
      return [
        ListTile(
          leading: Icon(Symbols.sell_rounded, color: theme.colorScheme.secondary),
          title: const Text('Pick a tag to search elsewhere', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text(
            "This booru doesn't say which tag is the artist/character — choose the one to look up on your other boorus",
          ),
          onTap: _pickPivot,
        ),
      ];
    }
    final String typeLabel = switch (pivotType) {
      TagType.artist => 'artist',
      TagType.character => 'character',
      TagType.copyright => 'copyright',
      _ => 'tag',
    };
    return [
      // Section header doubles as the pivot switcher.
      InkWell(
        onTap: _pickPivot,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Related elsewhere — $typeLabel: $pivotTag',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.grey.shade500),
                ),
              ),
              Icon(Symbols.edit_rounded, size: 16, color: theme.colorScheme.secondary),
            ],
          ),
        ),
      ),
      for (final r in related)
        ListTile(
          dense: true,
          enabled: r.state == _LookupState.found || r.state == _LookupState.error,
          leading: BooruFavicon(r.booru, size: 20),
          title: Text(
            r.booru.name ?? '?',
            style: TextStyle(
              fontWeight: r.state == _LookupState.found ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          subtitle: switch (r.state) {
            _LookupState.loading => const Text('Searching…'),
            _LookupState.found => Text(
                '${r.totalCount > 0 ? r.totalCount : r.count}${r.hasMore ? '+' : ''} posts'
                '${r.resolvedTag != pivotTag ? ' · as "${r.resolvedTag}"' : ''}',
              ),
            _LookupState.notFound => const Text('Nothing found'),
            _LookupState.error => const Text('Search failed — tap to retry'),
          },
          trailing: r.state == _LookupState.loading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5))
              : r.state == _LookupState.found
                  ? const Icon(Symbols.arrow_forward_rounded, size: 18)
                  : r.state == _LookupState.error
                      ? const Icon(Symbols.refresh_rounded, color: Colors.orange, size: 18)
                      : const SizedBox.shrink(),
          onTap: () {
            if (r.state == _LookupState.found) {
              _openRelated(r);
            } else if (r.state == _LookupState.error) {
              _lookupRelated(r);
            }
          },
        ),
    ];
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

  /// Opens the engine page in a Custom Tab (in-app browser view) first:
  /// externalApplication lets an installed native app (the Google app for
  /// lens.google.com, the Yandex app) capture the link as a deep link and
  /// drop the ?url= parameter — which showed up as "engine opens but no
  /// image was passed". A Custom Tab always loads the literal URL.
  Future<void> _launchExternal(String url) async {
    try {
      final ok = await launchUrlString(url, mode: LaunchMode.inAppBrowserView);
      if (ok) return;
    } catch (_) {}
    try {
      await launchUrlString(url, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  /// External reverse-image engines, opened in the browser with the image
  /// URL prefilled. Yandex in particular has far broader coverage of
  /// reposted content than any booru-specific index.
  List<Widget> _browserSearchSection(ThemeData theme) {
    final String img = Uri.encodeComponent(_searchImageUrl);
    final engines = <(String, String)>[
      ('Yandex', 'https://yandex.com/images/search?rpt=imageview&url=$img'),
      // searchbyimage is the battle-tested entry point (what reverse-search
      // extensions use); it redirects into Lens WITH the image attached,
      // unlike lens.google.com/uploadbyurl which often lands on a bare page.
      ('Google Lens', 'https://www.google.com/searchbyimage?sbisrc=cr_1_5_2&image_url=$img'),
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
                    onPressed: () => _launchExternal(url),
                  ),
              ],
            ),
          ],
        ),
      ),
    ];
  }
}
