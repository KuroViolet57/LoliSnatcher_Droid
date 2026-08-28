import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';

/// Per-source preferences (the reference app's "<source> settings" screen):
/// how the READER behaves on this site, its default sort, and the grid tag
/// strip. Every row is an override of the app-wide behaviour, applied to
/// this source only.
class SourceSettingsPage extends StatefulWidget {
  const SourceSettingsPage({required this.booru, super.key});

  final Booru booru;

  @override
  State<SourceSettingsPage> createState() => _SourceSettingsPageState();
}

class _SourceSettingsPageState extends State<SourceSettingsPage> {
  final sourceSettings = SourceSettingsHandler.instance;

  SourceSettings get s => sourceSettings.settingsFor(widget.booru);

  void _update(void Function(SourceSettings) change) {
    sourceSettings.update(widget.booru, change);
    setState(() {});
  }

  List<MetaTagValue> get _sortValues {
    final handler = BooruHandlerFactory().getBooruHandler([widget.booru], null).booruHandler;
    for (final metaTag in handler.availableMetaTags()) {
      if (metaTag is SortMetaTag) return metaTag.values;
    }
    return const [];
  }

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: Theme.of(context).colorScheme.secondary,
      ),
    ),
  );

  Widget _choiceRow<T>({
    required String title,
    required String subtitle,
    required List<(T, String)> options,
    required T? current,
    required void Function(T?) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 15)),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final option in options)
                ChoiceChip(
                  label: Text(option.$2),
                  selected: current == option.$1,
                  onSelected: (_) => onChanged(current == option.$1 ? null : option.$1),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sorts = _sortValues;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.booru.name ?? 'Source'} settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'These apply to ${widget.booru.name ?? 'this source'} only. '
              'An unselected chip means the app default is used.',
              style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
          ),
          //
          _header('READING'),
          _choiceRow<String>(
            title: 'Reading direction',
            subtitle: 'Right-to-left is the native direction for most manga.',
            options: const [('ltr', 'Left-to-right'), ('rtl', 'Right-to-left'), ('vertical', 'Vertical')],
            current: s.readingDirection,
            onChanged: (v) => _update((s) => s.readingDirection = v),
          ),
          _choiceRow<String>(
            title: 'Page turn animation',
            subtitle: 'How tap zones and the slider move between pages.',
            options: const [('animated', 'Animated'), ('instant', 'Instant')],
            current: s.pageTurnAnimation,
            onChanged: (v) => _update((s) => s.pageTurnAnimation = v),
          ),
          SwitchListTile(
            title: const Text('Tap zones turn pages'),
            subtitle: const Text('Tap the screen edges to change page, the middle for the reader controls.'),
            value: s.tapZones ?? true,
            onChanged: (v) => _update((s) => s.tapZones = v),
          ),
          ListTile(
            title: const Text('Preload pages'),
            subtitle: Text(
              s.preloadPages == null
                  ? 'App default (${SettingsHandler.instance.preloadCount})'
                  : 'Pages fetched ahead in the reader',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Symbols.remove_rounded),
                  onPressed: () => _update(
                    (s) => s.preloadPages = ((s.preloadPages ?? SettingsHandler.instance.preloadCount) - 1).clamp(0, 20),
                  ),
                ),
                Text('${s.preloadPages ?? SettingsHandler.instance.preloadCount}'),
                IconButton(
                  icon: const Icon(Symbols.add_rounded),
                  onPressed: () => _update(
                    (s) => s.preloadPages = ((s.preloadPages ?? SettingsHandler.instance.preloadCount) + 1).clamp(0, 20),
                  ),
                ),
              ],
            ),
          ),
          SwitchListTile(
            title: const Text('Keep screen on while reading'),
            value: s.keepScreenOn ?? true,
            onChanged: (v) => _update((s) => s.keepScreenOn = v),
          ),
          //
          if (sorts.isNotEmpty) ...[
            _header('SEARCH'),
            _choiceRow<String>(
              title: 'Default sort',
              subtitle: 'Applied when a search has no sort: term of its own.',
              options: [for (final v in sorts) (v.value, v.name)],
              current: s.defaultSort,
              onChanged: (v) => _update((s) => s.defaultSort = v),
            ),
          ],
          //
          _header('GRID'),
          SwitchListTile(
            title: const Text('Tags on grid cards'),
            subtitle: const Text('Most relevant tags under each cover, favourites in gold, and the +N button with the full list.'),
            value: s.gridTagStrip ?? true,
            onChanged: (v) => _update((s) => s.gridTagStrip = v),
          ),
        ],
      ),
    );
  }
}
