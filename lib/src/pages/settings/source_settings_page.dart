import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/pages/settings/booru_edit_page.dart';

/// One layer of the doujin settings, reference-app style.
///
/// With a [booru] this edits that SOURCE's overrides: every row can override
/// the global value and shows "Overridden for this source · tap to reset"
/// while it does. Without a booru it edits the GLOBAL layer that all doujin
/// sources inherit.
class SourceSettingsPage extends StatefulWidget {
  const SourceSettingsPage({this.booru, super.key});

  /// null = edit the global layer.
  final Booru? booru;

  @override
  State<SourceSettingsPage> createState() => _SourceSettingsPageState();
}

class _SourceSettingsPageState extends State<SourceSettingsPage> {
  final sourceSettings = SourceSettingsHandler.instance;

  bool get isGlobal => widget.booru == null;

  SourceSettings get layer =>
      isGlobal ? sourceSettings.globalSettings : sourceSettings.settingsFor(widget.booru);

  SourceSettings get globalLayer => sourceSettings.globalSettings;

  late final TextEditingController _blacklistController =
      TextEditingController(text: layer.tagBlacklist ?? '');

  @override
  void dispose() {
    _blacklistController.dispose();
    super.dispose();
  }

  void _update(void Function(SourceSettings) change) {
    if (isGlobal) {
      sourceSettings.updateGlobal(change);
    } else {
      sourceSettings.update(widget.booru, change);
    }
    setState(() {});
  }

  List<MetaTagValue> get _sortValues {
    final Booru? booru = widget.booru;
    if (booru == null) {
      // Global layer: nhentai's sorts are the doujin vocabulary for now.
      return [
        MetaTagValue(name: 'Newest', value: 'date'),
        MetaTagValue(name: 'Popular (all time)', value: 'popular'),
        MetaTagValue(name: 'Popular today', value: 'popular-today'),
        MetaTagValue(name: 'Popular this week', value: 'popular-week'),
        MetaTagValue(name: 'Popular this month', value: 'popular-month'),
      ];
    }
    final handler = BooruHandlerFactory().getBooruHandler([booru], null).booruHandler;
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

  /// The reference app's override marker. Shown under any row whose
  /// per-source layer holds a value; tapping it resets to the global.
  Widget _overrideMarker(bool overridden, VoidCallback reset) {
    if (isGlobal || !overridden) return const SizedBox.shrink();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: reset,
      child: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          'Overridden for this source · tap to reset',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      ),
    );
  }

  Widget _choiceRow<T>({
    required String title,
    required String subtitle,
    required List<(T, String)> options,
    required T? layerValue,
    required T? inheritedValue,
    required void Function(T?) onChanged,
  }) {
    final T? shown = layerValue ?? (isGlobal ? layerValue : inheritedValue);
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
                  selected: shown == option.$1,
                  onSelected: (_) => onChanged(layerValue == option.$1 ? null : option.$1),
                ),
            ],
          ),
          _overrideMarker(layerValue != null, () => onChanged(null)),
        ],
      ),
    );
  }

  Widget _switchRow({
    required String title,
    String? subtitle,
    required bool? layerValue,
    required bool inheritedValue,
    required void Function(bool?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          value: layerValue ?? inheritedValue,
          onChanged: onChanged,
        ),
        if (!isGlobal && layerValue != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 6),
            child: _overrideMarker(true, () => onChanged(null)),
          ),
      ],
    );
  }

  Widget _stepperRow({
    required String title,
    required String subtitle,
    required int? layerValue,
    required int effective,
    required int min,
    required int max,
    required int step,
    required void Function(int?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Symbols.remove_rounded),
                onPressed: () => onChanged((effective - step).clamp(min, max)),
              ),
              Text('$effective'),
              IconButton(
                icon: const Icon(Symbols.add_rounded),
                onPressed: () => onChanged((effective + step).clamp(min, max)),
              ),
            ],
          ),
        ),
        if (!isGlobal && layerValue != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 6),
            child: _overrideMarker(true, () => onChanged(null)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final sorts = _sortValues;
    final Booru? booru = widget.booru;

    return Scaffold(
      appBar: AppBar(
        title: Text(isGlobal ? 'Doujin settings' : '${booru!.name ?? 'Source'} settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              isGlobal
                  ? 'These apply to every doujin source. Each source can override any of them in its own settings page.'
                  : 'These apply to ${booru!.name ?? 'this source'} only, overriding the global doujin settings.',
              style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
          ),
          //
          if (!isGlobal) ...[
            _header('ACCOUNT'),
            ListTile(
              leading: const Icon(Symbols.key_rounded),
              title: Text((booru!.apiKey?.isNotEmpty ?? false) ? 'API key configured' : 'No API key'),
              subtitle: Text(
                (booru.apiKey?.isNotEmpty ?? false)
                    ? 'Favourites sync with your account. Tap to edit the key.'
                    : "Add your key (from the site's account settings) to sync favourites. Tap to edit.",
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => BooruEdit(booru)),
                );
              },
            ),
          ],
          //
          _header('READING'),
          _choiceRow<String>(
            title: 'Reading direction',
            subtitle: 'Right-to-left is the native direction for most manga. (Webtoon continuous scroll is not available yet.)',
            options: const [('ltr', 'Left-to-right'), ('rtl', 'Right-to-left'), ('vertical', 'Vertical')],
            layerValue: layer.readingDirection,
            inheritedValue: globalLayer.readingDirection ?? 'ltr',
            onChanged: (v) => _update((s) => s.readingDirection = v),
          ),
          _choiceRow<String>(
            title: 'Page turn animation',
            subtitle: 'How tap zones and the slider move between pages.',
            options: const [('animated', 'Animated'), ('instant', 'Instant')],
            layerValue: layer.pageTurnAnimation,
            inheritedValue: globalLayer.pageTurnAnimation ?? 'animated',
            onChanged: (v) => _update((s) => s.pageTurnAnimation = v),
          ),
          _switchRow(
            title: 'Tap zones turn pages',
            subtitle: 'Tap the screen edges to change page, the middle for the reader controls.',
            layerValue: layer.tapZones,
            inheritedValue: globalLayer.tapZones ?? true,
            onChanged: (v) => _update((s) => s.tapZones = v),
          ),
          _switchRow(
            title: 'Double-tap to zoom',
            subtitle: 'Adds a small delay to every tap and turns rapid tap-tap paging into zoom — pinch zoom always works.',
            layerValue: layer.doubleTapZoom,
            inheritedValue: globalLayer.doubleTapZoom ?? false,
            onChanged: (v) => _update((s) => s.doubleTapZoom = v),
          ),
          _stepperRow(
            title: 'Preload pages',
            subtitle: 'Pages fetched ahead in the reader.',
            layerValue: layer.preloadPages,
            effective: sourceSettings.preloadPages(booru),
            min: 0,
            max: 20,
            step: 1,
            onChanged: (v) => _update((s) => s.preloadPages = v),
          ),
          _switchRow(
            title: 'Keep screen on while reading',
            layerValue: layer.keepScreenOn,
            inheritedValue: globalLayer.keepScreenOn ?? true,
            onChanged: (v) => _update((s) => s.keepScreenOn = v),
          ),
          //
          _header('SEARCH'),
          if (sorts.isNotEmpty)
            _choiceRow<String>(
              title: 'Default sort',
              subtitle: 'Applied when a search has no sort: term of its own.',
              options: [for (final v in sorts) (v.value, v.name)],
              layerValue: layer.defaultSort,
              inheritedValue: globalLayer.defaultSort,
              onChanged: (v) => _update((s) => s.defaultSort = v),
            ),
          _choiceRow<String>(
            title: 'Only show language',
            subtitle: 'Adds a language filter to every search.',
            options: const [('english', 'English'), ('japanese', 'Japanese'), ('chinese', 'Chinese')],
            layerValue: layer.languageFilter,
            inheritedValue: globalLayer.languageFilter,
            onChanged: (v) => _update((s) => s.languageFilter = v),
          ),
          _choiceRow<String>(
            title: 'Title language',
            subtitle: 'Which title shows first on cards and the detail page.',
            options: const [('english', 'English'), ('japanese', 'Japanese')],
            layerValue: layer.titleLanguage,
            inheritedValue: globalLayer.titleLanguage ?? 'english',
            onChanged: (v) => _update((s) => s.titleLanguage = v),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tag blacklist', style: TextStyle(fontSize: 15)),
                const SizedBox(height: 2),
                Text(
                  'Comma-separated tags excluded from every search on ${isGlobal ? 'all doujin sources' : 'this source'}.',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _blacklistController,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'e.g. netorare, guro',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onChanged: (value) => _update((s) => s.tagBlacklist = value.trim().isEmpty ? null : value.trim()),
                ),
                _overrideMarker(layer.tagBlacklist != null, () {
                  _blacklistController.clear();
                  _update((s) => s.tagBlacklist = null);
                }),
              ],
            ),
          ),
          if (!isGlobal)
            _choiceRow<String>(
              title: 'Blacklist mode',
              subtitle: 'Extend applies this list on top of the global doujin blacklist; override uses only this list here.',
              options: const [('extend', 'Extend'), ('override', 'Override')],
              layerValue: layer.blacklistMode,
              inheritedValue: 'extend',
              onChanged: (v) => _update((s) => s.blacklistMode = v),
            ),
          //
          _header('TABS'),
          _choiceRow<String>(
            title: 'New-tab placement',
            subtitle: 'Where "Open in new tab" on a doujin card puts the tab.',
            options: const [('end', 'End of list'), ('next', 'Next to current')],
            layerValue: layer.tabPlacement,
            inheritedValue: globalLayer.tabPlacement ?? 'end',
            onChanged: (v) => _update((s) => s.tabPlacement = v),
          ),
          _choiceRow<String>(
            title: 'Tag chip tap',
            subtitle: 'What tapping a tag chip does — long-press always does the other one. Cards keep the opposite: tap opens, long-press menus.',
            options: const [('menu', 'Open menu'), ('newtab', 'Background tab')],
            layerValue: layer.tagChipTap,
            inheritedValue: globalLayer.tagChipTap ?? 'menu',
            onChanged: (v) => _update((s) => s.tagChipTap = v),
          ),
          //
          _header('RECOMMENDATIONS'),
          _switchRow(
            title: 'Endless recommendations',
            subtitle: 'The Recommended strip keeps loading more as you scroll.',
            layerValue: layer.recommendedCount == null ? null : layer.recommendedCount == 0,
            inheritedValue: sourceSettings.recommendedCount(booru) == 0,
            onChanged: (v) => _update((s) => s.recommendedCount = (v ?? false) ? 0 : 30),
          ),
          if (sourceSettings.recommendedCount(booru) != 0)
            _stepperRow(
              title: 'Recommended items per gallery',
              subtitle: "The source supplies a handful; the rest are found by matching the gallery's tags (artist stays a small minority).",
              layerValue: layer.recommendedCount,
              effective: sourceSettings.recommendedCount(booru),
              min: 5,
              max: 100,
              step: 5,
              onChanged: (v) => _update((s) => s.recommendedCount = v),
            ),
          //
          _header('GRID'),
          _choiceRow<String>(
            title: 'Cover display',
            subtitle: 'Fit letterboxes the whole cover; crop fills the card; adapt sizes the card to the cover.',
            options: const [('fit', 'Fit'), ('crop', 'Crop'), ('adapt', 'Adapt')],
            layerValue: layer.coverDisplay,
            inheritedValue: globalLayer.coverDisplay ?? 'fit',
            onChanged: (v) => _update((s) => s.coverDisplay = v),
          ),
          _switchRow(
            title: 'Tags on grid cards',
            subtitle: 'Most relevant tags under each cover, favourites in gold, and the +N button with the full list.',
            layerValue: layer.gridTagStrip,
            inheritedValue: globalLayer.gridTagStrip ?? true,
            onChanged: (v) => _update((s) => s.gridTagStrip = v),
          ),
          _stepperRow(
            title: 'Feed columns (portrait)',
            subtitle: 'Overrides the app-wide column count on doujin feeds.',
            layerValue: layer.columnsPortrait,
            effective: sourceSettings.columnsPortrait(booru) ?? SettingsHandler.instance.portraitColumns,
            min: 1,
            max: 5,
            step: 1,
            onChanged: (v) => _update((s) => s.columnsPortrait = v),
          ),
          _stepperRow(
            title: 'Feed columns (landscape / tablet)',
            subtitle: 'Overrides the app-wide column count on doujin feeds.',
            layerValue: layer.columnsLandscape,
            effective: sourceSettings.columnsLandscape(booru) ?? SettingsHandler.instance.landscapeColumns,
            min: 1,
            max: 8,
            step: 1,
            onChanged: (v) => _update((s) => s.columnsLandscape = v),
          ),
          _stepperRow(
            title: 'Page preview columns',
            subtitle: 'Thumbnails per row in the Pages grid. Fewer columns means bigger previews.',
            layerValue: layer.pagePreviewColumns,
            effective: sourceSettings.pagePreviewColumns(booru),
            min: 1,
            max: 6,
            step: 1,
            onChanged: (v) => _update((s) => s.pagePreviewColumns = v),
          ),
        ],
      ),
    );
  }
}
