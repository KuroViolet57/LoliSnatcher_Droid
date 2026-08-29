import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// One layer of doujin preferences — either the GLOBAL layer or one
/// source's overrides. Every field is nullable = "not set at this layer".
class SourceSettings {
  SourceSettings({
    this.readingDirection,
    this.pageTurnAnimation,
    this.tapZones,
    this.doubleTapZoom,
    this.preloadPages,
    this.keepScreenOn,
    this.defaultSort,
    this.gridTagStrip,
    this.coverDisplay,
    this.recommendedCount,
    this.pagePreviewColumns,
    this.titleLanguage,
    this.languageFilter,
    this.tagBlacklist,
    this.blacklistMode,
    this.columnsPortrait,
    this.columnsLandscape,
  });

  factory SourceSettings.fromJson(Map<String, dynamic> json) => SourceSettings(
    readingDirection: json['readingDirection'] as String?,
    pageTurnAnimation: json['pageTurnAnimation'] as String?,
    tapZones: json['tapZones'] as bool?,
    doubleTapZoom: json['doubleTapZoom'] as bool?,
    preloadPages: json['preloadPages'] as int?,
    keepScreenOn: json['keepScreenOn'] as bool?,
    defaultSort: json['defaultSort'] as String?,
    gridTagStrip: json['gridTagStrip'] as bool?,
    coverDisplay: json['coverDisplay'] as String?,
    recommendedCount: json['recommendedCount'] as int?,
    pagePreviewColumns: json['pagePreviewColumns'] as int?,
    titleLanguage: json['titleLanguage'] as String?,
    languageFilter: json['languageFilter'] as String?,
    tagBlacklist: json['tagBlacklist'] as String?,
    blacklistMode: json['blacklistMode'] as String?,
    columnsPortrait: json['columnsPortrait'] as int?,
    columnsLandscape: json['columnsLandscape'] as int?,
  );

  /// 'ltr' | 'rtl' | 'vertical'
  String? readingDirection;

  /// 'animated' | 'instant'
  String? pageTurnAnimation;

  /// Tap left/right screen edges to turn pages.
  bool? tapZones;

  /// Double-tap to zoom in the reader. OFF by default: any double-tap
  /// recognizer under the pointer delays every single tap by the double-tap
  /// window (~300ms) and turns rapid tap-tap paging into a zoom — pinch
  /// zoom always works regardless.
  bool? doubleTapZoom;

  /// Pages fetched ahead in the reader.
  int? preloadPages;

  bool? keepScreenOn;

  /// Sort value applied when a search has no sort: term (e.g. 'popular').
  String? defaultSort;

  /// Show the tag strip + language badge on grid cards.
  bool? gridTagStrip;

  /// How feed cards show the cover: 'fit' letterboxes the whole cover,
  /// 'crop' fills the card (the old behaviour), 'adapt' sizes the card to
  /// the cover's aspect ratio (staggered grid).
  String? coverDisplay;

  /// How many items the Recommended strip shows (the site supplies 5; the
  /// rest are found by matching the gallery's signals).
  int? recommendedCount;

  /// Columns of the Pages thumbnail grid (detail page / drawer).
  int? pagePreviewColumns;

  /// Preferred title on doujin sources: 'english' | 'japanese'.
  String? titleLanguage;

  /// Only show this language ('english'/'japanese'/'chinese'; null = all).
  String? languageFilter;

  /// Comma-separated tags excluded from every search on this source.
  String? tagBlacklist;

  /// How the per-source blacklist combines with the doujin-global one:
  /// 'extend' (default; both apply) | 'override' (only this source's list).
  String? blacklistMode;

  /// Grid columns for doujin feeds, overriding the app-wide columns.
  int? columnsPortrait;
  int? columnsLandscape;

  Map<String, dynamic> toJson() => {
    if (readingDirection != null) 'readingDirection': readingDirection,
    if (pageTurnAnimation != null) 'pageTurnAnimation': pageTurnAnimation,
    if (tapZones != null) 'tapZones': tapZones,
    if (doubleTapZoom != null) 'doubleTapZoom': doubleTapZoom,
    if (preloadPages != null) 'preloadPages': preloadPages,
    if (keepScreenOn != null) 'keepScreenOn': keepScreenOn,
    if (defaultSort != null) 'defaultSort': defaultSort,
    if (gridTagStrip != null) 'gridTagStrip': gridTagStrip,
    if (coverDisplay != null) 'coverDisplay': coverDisplay,
    if (recommendedCount != null) 'recommendedCount': recommendedCount,
    if (pagePreviewColumns != null) 'pagePreviewColumns': pagePreviewColumns,
    if (titleLanguage != null) 'titleLanguage': titleLanguage,
    if (languageFilter != null) 'languageFilter': languageFilter,
    if (tagBlacklist != null) 'tagBlacklist': tagBlacklist,
    if (blacklistMode != null) 'blacklistMode': blacklistMode,
    if (columnsPortrait != null) 'columnsPortrait': columnsPortrait,
    if (columnsLandscape != null) 'columnsLandscape': columnsLandscape,
  };

  bool get isEmpty => toJson().isEmpty;
}

/// Doujin settings in two layers, exactly like the reference app:
/// a GLOBAL layer applying to every doujin source, and per-source overrides
/// on top ("Overridden for this source · tap to reset"). Effective value =
/// source override ?? global ?? hardcoded default.
///
/// Persisted as sourceSettings.json next to settings.json; the global layer
/// lives under the reserved '_global' key. Loaded lazily on first use.
class SourceSettingsHandler {
  SourceSettingsHandler._();

  static final SourceSettingsHandler instance = SourceSettingsHandler._();

  static const String globalKey = '_global';

  final Map<String, SourceSettings> _byHost = {};
  bool _loaded = false;

  static String keyFor(Booru? booru) =>
      Uri.tryParse(booru?.baseURL ?? '')?.host ?? (booru?.name ?? '');

  File get _file => File('${SettingsHandler.instance.path}sourceSettings.json');

  void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = _file;
      if (!file.existsSync()) return;
      final Map<String, dynamic> data = jsonDecode(file.readAsStringSync());
      for (final entry in data.entries) {
        _byHost[entry.key] = SourceSettings.fromJson(entry.value as Map<String, dynamic>);
      }
    } catch (e, s) {
      Logger.Inst().log('failed to load source settings: $e', 'SourceSettingsHandler', '_ensureLoaded', LogTypes.exception, s: s);
    }
  }

  void _save() {
    try {
      final Map<String, dynamic> data = {
        for (final entry in _byHost.entries)
          if (!entry.value.isEmpty) entry.key: entry.value.toJson(),
      };
      _file.writeAsStringSync(jsonEncode(data));
    } catch (e, s) {
      Logger.Inst().log('failed to save source settings: $e', 'SourceSettingsHandler', '_save', LogTypes.exception, s: s);
    }
  }

  /// Tests only: forget everything and reload from the (per-test) file on
  /// next access — the singleton otherwise leaks state between tests.
  @visibleForTesting
  void resetForTests() {
    _byHost.clear();
    _loaded = false;
  }

  /// Forgets the in-memory state and reloads from the file — used after a
  /// backup restore replaces sourceSettings.json on disk.
  void reloadFromDisk() {
    _byHost.clear();
    _loaded = false;
    _ensureLoaded();
  }

  SourceSettings settingsFor(Booru? booru) {
    _ensureLoaded();
    return _byHost.putIfAbsent(keyFor(booru), SourceSettings.new);
  }

  SourceSettings get globalSettings {
    _ensureLoaded();
    return _byHost.putIfAbsent(globalKey, SourceSettings.new);
  }

  void update(Booru? booru, void Function(SourceSettings) change) {
    _ensureLoaded();
    change(settingsFor(booru));
    _save();
  }

  void updateGlobal(void Function(SourceSettings) change) {
    _ensureLoaded();
    change(globalSettings);
    _save();
  }

  /// Appends [tag] to the blacklist of one layer: [booru] == null targets the
  /// doujin-global layer, otherwise that source's own list. No-op when the
  /// layer already lists the tag.
  void addBlacklistTag(Booru? booru, String tag) {
    final String normalized = tag.trim();
    if (normalized.isEmpty) return;
    void change(SourceSettings s) {
      final existing = [
        for (final part in (s.tagBlacklist ?? '').split(','))
          if (part.trim().isNotEmpty) part.trim(),
      ];
      if (existing.any((t) => t.toLowerCase() == normalized.toLowerCase())) return;
      existing.add(normalized);
      s.tagBlacklist = existing.join(', ');
    }

    if (booru == null) {
      updateGlobal(change);
    } else {
      update(booru, change);
    }
  }

  // ── effective values: source override ?? global ?? default ──

  T _resolve<T>(Booru? booru, T? Function(SourceSettings) pick, T fallback) =>
      pick(settingsFor(booru)) ?? pick(globalSettings) ?? fallback;

  String readingDirection(Booru? booru) => _resolve(booru, (s) => s.readingDirection, 'ltr');

  bool instantPageTurns(Booru? booru) => _resolve(booru, (s) => s.pageTurnAnimation, 'animated') == 'instant';

  bool tapZones(Booru? booru) => _resolve(booru, (s) => s.tapZones, true);

  bool doubleTapZoom(Booru? booru) => _resolve(booru, (s) => s.doubleTapZoom, false);

  int preloadPages(Booru? booru) =>
      _resolve(booru, (s) => s.preloadPages, SettingsHandler.instance.preloadCount);

  bool keepScreenOn(Booru? booru) => _resolve(booru, (s) => s.keepScreenOn, true);

  String? defaultSort(Booru? booru) =>
      settingsFor(booru).defaultSort ?? globalSettings.defaultSort;

  bool gridTagStrip(Booru? booru) => _resolve(booru, (s) => s.gridTagStrip, true);

  /// 'fit' (default — the whole cover is visible) | 'crop' | 'adapt'.
  String coverDisplay(Booru? booru) => _resolve(booru, (s) => s.coverDisplay, 'fit');

  /// 0 = endless (the Recommended strip keeps loading on scroll).
  int recommendedCount(Booru? booru) {
    final int v = _resolve(booru, (s) => s.recommendedCount, 30);
    return v <= 0 ? 0 : v.clamp(5, 100);
  }

  int pagePreviewColumns(Booru? booru) => _resolve(booru, (s) => s.pagePreviewColumns, 3).clamp(1, 6);

  /// 'english' | 'japanese'
  String titleLanguage(Booru? booru) => _resolve(booru, (s) => s.titleLanguage, 'english');

  String? languageFilter(Booru? booru) =>
      settingsFor(booru).languageFilter ?? globalSettings.languageFilter;

  /// 'extend' | 'override' — how [tagBlacklist] combines the two layers.
  String blacklistMode(Booru? booru) => settingsFor(booru).blacklistMode ?? 'extend';

  List<String> tagBlacklist(Booru? booru) {
    final bool override = blacklistMode(booru) == 'override';
    final String raw = [
      settingsFor(booru).tagBlacklist ?? '',
      if (!override) globalSettings.tagBlacklist ?? '',
    ].join(',');
    return [
      for (final part in raw.split(','))
        if (part.trim().isNotEmpty) part.trim().toLowerCase().replaceAll(' ', '_'),
    ];
  }

  int? columnsPortrait(Booru? booru) =>
      settingsFor(booru).columnsPortrait ?? globalSettings.columnsPortrait;

  int? columnsLandscape(Booru? booru) =>
      settingsFor(booru).columnsLandscape ?? globalSettings.columnsLandscape;
}
