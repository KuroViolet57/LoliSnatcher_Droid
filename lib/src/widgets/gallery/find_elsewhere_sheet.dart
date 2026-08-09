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
import 'package:lolisnatcher/src/handlers/suggestion_engine.dart';
import 'package:lolisnatcher/src/widgets/gallery/tag_view.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';

/// "Find elsewhere": blended suggestions drawn from the user's OTHER boorus.
///
/// Runs the same facet-blend engine as the in-post Suggested strip (see
/// [SuggestionEngine]) but spreads the facets across the other configured
/// boorus, translating each facet tag to that site's own spelling. So instead
/// of "is this exact file over there", it answers "what does this post's
/// character / franchise / artist / theme look like on my other sites".
///
/// IQDB similarity search and the browser reverse-search links stay as manual
/// escape hatches underneath.

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

  /// Other configured boorus — the pool the blend runs across.
  List<Booru> get _otherBoorus {
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
    return SettingsHandler.instance.booruList.where((b) {
      if (b.type == null || virtualTypes.contains(b.type)) return false;
      final String? host = Uri.tryParse(b.baseURL ?? '')?.host;
      if (host != null && host.isNotEmpty && (host == sourceHost || host == postHost)) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final List<Booru> others = _otherBoorus;
    final bool hasFacets = SuggestionEngine.facetsForItem(widget.original).isNotEmpty;

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
                const Expanded(
                  child: Text(
                    'Similar on your other boorus',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
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
                if (others.isEmpty)
                  const ListTile(
                    leading: Icon(Symbols.info_rounded),
                    title: Text('No other boorus configured'),
                    subtitle: Text("Add another booru to discover this post's themes elsewhere"),
                  )
                else if (!hasFacets)
                  const ListTile(
                    leading: Icon(Symbols.sell_rounded),
                    title: Text('Not enough tags on this post'),
                    subtitle: Text('Suggestions need a character, franchise, artist or descriptive tag'),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: TagContentPreview(
                      key: ValueKey('elsewhere-${widget.original.serverId ?? widget.original.fileURL}'),
                      tag: 'suggestions',
                      boorus: others,
                      parentTab: SearchHandler.instance.tabs.isEmpty ? null : SearchHandler.instance.currentTab,
                      compact: true,
                      compactTitle: 'Mixed from ${others.length} boorus',
                      suggestFor: widget.original,
                      suggestBoorus: others,
                    ),
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
