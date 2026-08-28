import 'dart:convert';
import 'dart:io';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// Per-source preferences for one site, keyed by host.
///
/// Every field is nullable = "no override, use the app default"; the getters
/// on [SourceSettingsHandler] resolve the effective value.
class SourceSettings {
  SourceSettings({
    this.readingDirection,
    this.pageTurnAnimation,
    this.tapZones,
    this.preloadPages,
    this.keepScreenOn,
    this.defaultSort,
    this.gridTagStrip,
  });

  factory SourceSettings.fromJson(Map<String, dynamic> json) => SourceSettings(
    readingDirection: json['readingDirection'] as String?,
    pageTurnAnimation: json['pageTurnAnimation'] as String?,
    tapZones: json['tapZones'] as bool?,
    preloadPages: json['preloadPages'] as int?,
    keepScreenOn: json['keepScreenOn'] as bool?,
    defaultSort: json['defaultSort'] as String?,
    gridTagStrip: json['gridTagStrip'] as bool?,
  );

  /// 'ltr' | 'rtl' | 'vertical'
  String? readingDirection;

  /// 'animated' | 'instant'
  String? pageTurnAnimation;

  /// Tap left/right screen edges to turn pages.
  bool? tapZones;

  /// Pages fetched ahead in the reader.
  int? preloadPages;

  bool? keepScreenOn;

  /// Sort value applied when a search has no sort: term (e.g. 'popular').
  String? defaultSort;

  /// Show the tag strip + language badge on grid cards.
  bool? gridTagStrip;

  Map<String, dynamic> toJson() => {
    if (readingDirection != null) 'readingDirection': readingDirection,
    if (pageTurnAnimation != null) 'pageTurnAnimation': pageTurnAnimation,
    if (tapZones != null) 'tapZones': tapZones,
    if (preloadPages != null) 'preloadPages': preloadPages,
    if (keepScreenOn != null) 'keepScreenOn': keepScreenOn,
    if (defaultSort != null) 'defaultSort': defaultSort,
    if (gridTagStrip != null) 'gridTagStrip': gridTagStrip,
  };

  bool get isEmpty => toJson().isEmpty;
}

/// Per-source settings store (the reference app's "nhentai settings" screen):
/// reading direction, page-turn style, tap zones, preload depth, keep screen
/// on, default sort — resolved per site so each source can differ.
///
/// Persisted as sourceSettings.json next to settings.json; loaded lazily on
/// first use, so app startup doesn't pay for it.
class SourceSettingsHandler {
  SourceSettingsHandler._();

  static final SourceSettingsHandler instance = SourceSettingsHandler._();

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

  SourceSettings settingsFor(Booru? booru) {
    _ensureLoaded();
    return _byHost.putIfAbsent(keyFor(booru), SourceSettings.new);
  }

  void update(Booru? booru, void Function(SourceSettings) change) {
    _ensureLoaded();
    change(settingsFor(booru));
    _save();
  }

  // ── effective values (override or app default) ──

  String readingDirection(Booru? booru) => settingsFor(booru).readingDirection ?? 'ltr';

  bool instantPageTurns(Booru? booru) => settingsFor(booru).pageTurnAnimation == 'instant';

  bool tapZones(Booru? booru) => settingsFor(booru).tapZones ?? true;

  int preloadPages(Booru? booru) =>
      settingsFor(booru).preloadPages ?? SettingsHandler.instance.preloadCount;

  bool keepScreenOn(Booru? booru) => settingsFor(booru).keepScreenOn ?? true;

  String? defaultSort(Booru? booru) => settingsFor(booru).defaultSort;

  bool gridTagStrip(Booru? booru) => settingsFor(booru).gridTagStrip ?? true;
}
