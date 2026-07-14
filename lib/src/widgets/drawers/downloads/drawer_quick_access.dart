import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/history_item.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

/// A "Quick access" panel that sits at the top of the downloads drawer, turning
/// what was mostly empty space (for people who don't snatch) into shortcuts:
/// jump straight to the For You / Collections / Favourites / Downloads feeds,
/// and re-open a recent search as a new tab.
class DrawerQuickAccess extends StatefulWidget {
  const DrawerQuickAccess({required this.toggleDrawer, super.key});

  final VoidCallback toggleDrawer;

  @override
  State<DrawerQuickAccess> createState() => _DrawerQuickAccessState();
}

class _DrawerQuickAccessState extends State<DrawerQuickAccess> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final SearchHandler searchHandler = SearchHandler.instance;

  List<HistoryItem> _recent = [];

  late final Booru _forYou;
  late final Booru _collections;
  Booru? _favourites;
  Booru? _downloads;

  @override
  void initState() {
    super.initState();
    // ensure* may append a virtual booru to the list — do it once here, not in
    // build().
    _forYou = settingsHandler.ensureForYouBooru();
    _collections = settingsHandler.ensureCollectionsBooru();
    _favourites = _virtual((t) => t.isFavourites);
    _downloads = _virtual((t) => t.isDownloads);
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    try {
      final items = await settingsHandler.dbHandler.getLatestSearchHistory();
      // De-dupe by search text, drop empties, keep the newest few.
      final seen = <String>{};
      final List<HistoryItem> out = [];
      for (final h in items) {
        final t = h.searchText.trim();
        if (t.isEmpty || !seen.add(t.toLowerCase())) continue;
        out.add(h);
        if (out.length >= 8) break;
      }
      if (mounted) setState(() => _recent = out);
    } catch (_) {
      // history is a nicety — ignore failures
    }
  }

  Booru? _virtual(bool Function(BooruType) test) {
    for (final b in settingsHandler.booruList) {
      final t = b.type;
      if (t != null && test(t)) return b;
    }
    return null;
  }

  void _openTab(String query, Booru? booru) {
    if (booru == null) return;
    searchHandler.addTabByString(query, customBooru: booru, switchToNew: true);
    widget.toggleDrawer();
  }

  void _openRecent(HistoryItem h) {
    Booru? booru;
    for (final b in settingsHandler.booruList) {
      if (b.name == h.booruName) {
        booru = b;
        break;
      }
    }
    booru ??= searchHandler.currentBooru;
    _openTab(h.searchText, booru);
  }

  Widget _shortcut(IconData icon, String label, Booru? booru) {
    final bool enabled = booru != null;
    final Color fg = enabled
        ? Theme.of(context).colorScheme.onSurface
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? () => _openTab('', booru) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Icon(icon, size: 22, color: fg),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick access',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _shortcut(Icons.auto_awesome, 'For You', _forYou),
              _shortcut(Icons.collections_bookmark, 'Collections', _collections),
              _shortcut(Icons.favorite, 'Favourites', _favourites),
              _shortcut(Icons.download, 'Downloads', _downloads),
            ],
          ),
          if (_recent.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Recent searches',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 2,
              children: [
                for (final h in _recent)
                  ActionChip(
                    label: Text(
                      h.searchText,
                      overflow: TextOverflow.ellipsis,
                    ),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    avatar: Icon(Icons.history, size: 16, color: Theme.of(context).colorScheme.primary),
                    onPressed: () => _openRecent(h),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Downloads',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Divider(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
