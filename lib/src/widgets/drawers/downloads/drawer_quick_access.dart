import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/history_item.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

/// The whole left ("snatch") drawer, repurposed as a navigation panel:
///   - Quick access shortcuts (For You / Collections / Favourites / Downloads)
///   - Pinned tags (favourited searches) at the top
///   - Recent searches at the bottom
/// Long-press a search to pin/unpin it. The download queue lives elsewhere.
class DrawerQuickAccess extends StatefulWidget {
  const DrawerQuickAccess({required this.toggleDrawer, super.key});

  final VoidCallback toggleDrawer;

  @override
  State<DrawerQuickAccess> createState() => _DrawerQuickAccessState();
}

class _DrawerQuickAccessState extends State<DrawerQuickAccess> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final SearchHandler searchHandler = SearchHandler.instance;

  List<HistoryItem> _pinned = [];
  List<HistoryItem> _recent = [];

  late final Booru _forYou;
  late final Booru _collections;
  Booru? _favourites;
  Booru? _downloads;

  @override
  void initState() {
    super.initState();
    _forYou = settingsHandler.ensureForYouBooru();
    _collections = settingsHandler.ensureCollectionsBooru();
    _favourites = _virtual((t) => t.isFavourites);
    _downloads = _virtual((t) => t.isDownloads);
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final items = await settingsHandler.dbHandler.getSearchHistory();
      final seen = <String>{};
      final List<HistoryItem> pinned = [];
      final List<HistoryItem> recent = [];
      for (final h in items) {
        final t = h.searchText.trim();
        if (t.isEmpty || !seen.add(t.toLowerCase())) continue;
        if (h.isFavourite) {
          pinned.add(h);
        } else if (recent.length < 14) {
          recent.add(h);
        }
      }
      if (mounted) {
        setState(() {
          _pinned = pinned;
          _recent = recent;
        });
      }
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

  Future<void> _setPinned(HistoryItem h, bool pin) async {
    await ServiceHandler.vibrate(duration: 35, amplitude: 160);
    await settingsHandler.dbHandler.setFavouriteSearchHistory(h.id, pin);
    await _loadHistory();
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

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _historyChip(HistoryItem h, {required bool pinned}) {
    final Color iconColor = Theme.of(context).colorScheme.onSurface;
    return GestureDetector(
      onLongPress: () => _setPinned(h, !pinned),
      child: ActionChip(
        label: Text(h.searchText, overflow: TextOverflow.ellipsis),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        avatar: Icon(
          pinned ? Icons.push_pin : Icons.history,
          size: 16,
          color: iconColor,
        ),
        onPressed: () => _openRecent(h),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Quick access'),
          Row(
            children: [
              _shortcut(Icons.auto_awesome, 'For You', _forYou),
              _shortcut(Icons.collections_bookmark, 'Collections', _collections),
              _shortcut(Icons.favorite, 'Favourites', _favourites),
              _shortcut(Icons.download, 'Downloads', _downloads),
            ],
          ),
          const SizedBox(height: 12),
          // Pinned tags sit at the top; the list scrolls if it grows so the
          // recent-searches section stays anchored to the bottom.
          _sectionLabel('Pinned tags'),
          Expanded(
            child: _pinned.isEmpty
                ? Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      'Long-press a recent search to pin it here.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      children: [
                        for (final h in _pinned) _historyChip(h, pinned: true),
                      ],
                    ),
                  ),
          ),
          if (_recent.isNotEmpty) ...[
            const Divider(),
            _sectionLabel('Recent searches'),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.28,
              ),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    for (final h in _recent) _historyChip(h, pinned: false),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
