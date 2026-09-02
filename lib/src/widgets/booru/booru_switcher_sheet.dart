import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/pages/settings/booru_edit_page.dart';
import 'package:lolisnatcher/src/widgets/image/booru_favicon.dart';

/// The sources a tab on [current] may switch to: the same world only. A
/// doujin tab is offered doujin sources, a booru tab boorus (and the local
/// feeds, which are booru-side stores). The two vocabularies are unrelated,
/// so a cross-world switch never produces a useful search.
List<Booru> switchableBoorus(List<Booru> all, Booru current) =>
    all.where((b) => DoujinDataHandler.sameDomain(current, b)).toList();

/// Flow "Switch booru" bottom sheet: pick the booru the current tab searches.
/// Opened from the drawer booru card, the query editor pill, etc.
Future<void> showBooruSwitcherSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _BooruSwitcherSheet(),
  );
}

class _BooruSwitcherSheet extends StatelessWidget {
  const _BooruSwitcherSheet();

  String _subtitle(Booru booru) {
    final url = booru.baseURL ?? '';
    if (url.isNotEmpty) {
      String host = url.replaceFirst(RegExp('^https?://'), '');
      if (host.endsWith('/')) host = host.substring(0, host.length - 1);
      return host;
    }
    final t = booru.type;
    if (t?.isForYou == true) return 'recommendation feed';
    if (t?.isHistory == true) return 'viewing history';
    if (t?.isFavourites == true) return 'your favourites';
    if (t?.isCollections == true) return 'your collections';
    if (t?.isDownloads == true) return 'downloaded posts';
    return booru.type?.alias ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searchHandler = SearchHandler.instance;
    final settingsHandler = SettingsHandler.instance;
    final Booru current = searchHandler.currentBooru;
    final bool isDoujin = DoujinDataHandler.isDoujinBooru(current);
    final List<Booru> boorus = switchableBoorus(settingsHandler.booruList, current);

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
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
            child: Row(
              children: [
                Text(
                  isDoujin ? 'Switch doujin source' : 'Switch booru',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  'tap to switch',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: boorus.length,
              itemBuilder: (context, i) {
                final booru = boorus[i];
                final bool isActive = booru == current ||
                    (booru.name == current.name && booru.type == current.type);
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  decoration: BoxDecoration(
                    color: isActive ? theme.colorScheme.secondary.withValues(alpha: 0.12) : theme.colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isActive ? theme.colorScheme.secondary : theme.colorScheme.outlineVariant,
                      width: isActive ? 1.4 : 1,
                    ),
                  ),
                  child: ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: SizedBox(width: 34, height: 34, child: BooruFavicon(booru, size: 34)),
                    ),
                    title: Text(
                      booru.name ?? '',
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      _subtitle(booru),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
                    ),
                    trailing: Icon(
                      isActive ? Symbols.radio_button_checked_rounded : Symbols.radio_button_unchecked_rounded,
                      color: isActive ? theme.colorScheme.secondary : theme.colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      if (!isActive) {
                        searchHandler.searchAction(searchHandler.searchTextController.text, booru);
                      }
                    },
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => BooruEdit(Booru('New', null, '', '', ''))),
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: theme.colorScheme.outline, width: 1.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Symbols.add_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(
                      'Add booru config',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
