import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
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
      md5: md5,
      results: candidates,
    ),
  );
}

class _FindElsewhereSheet extends StatefulWidget {
  const _FindElsewhereSheet({
    required this.original,
    required this.md5,
    required this.results,
  });

  final BooruItem original;
  final String md5;
  final List<_LookupResult> results;

  @override
  State<_FindElsewhereSheet> createState() => _FindElsewhereSheetState();
}

class _FindElsewhereSheetState extends State<_FindElsewhereSheet> {
  @override
  void initState() {
    super.initState();
    for (final r in widget.results) {
      _lookup(r);
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
      setState(() {
        r.item = hit;
        r.state = hit != null ? _LookupState.found : _LookupState.notFound;
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
