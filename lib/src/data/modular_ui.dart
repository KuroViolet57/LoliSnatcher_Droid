import 'package:flutter/foundation.dart';

import 'package:lolisnatcher/src/handlers/settings_handler.dart';

/// One part of the interface that can be shown or hidden (r41).
class ModularUiToggle {
  const ModularUiToggle({
    required this.key,
    required this.area,
    required this.title,
    required this.description,
    this.defaultValue = false,
  });

  /// Stored under this name in the settings' `modularUi` map.
  final String key;

  /// Where in the app the part is (the settings page groups by it).
  final String area;
  final String title;

  /// Exactly what the switch shows or hides.
  final String description;

  /// On or off until the person changes it.
  final bool defaultValue;
}

/// Modular UI (r41, Settings → Modular UI): every part of the interface the
/// user asks to remove becomes a switch here instead, so it can come back
/// with its function intact. The values live in the settings file (loaded
/// before the first screen, and part of a settings backup); a widget reads
/// [isOn] where it builds and leaves a hidden part out entirely — never
/// builds it to hide it — so a part switched off costs nothing.
///
/// To add one: a [ModularUiToggle] constant here, listed in [all], and an
/// `if (ModularUi.isOn(...))` where the part is built.
class ModularUi {
  const ModularUi._();

  static const String searchWindowArea = 'Search window';

  static const ModularUiToggle searchHistory = ModularUiToggle(
    key: 'search.history',
    area: searchWindowArea,
    title: 'History',
    description: 'Your recent searches, as a row of chips in the search window, for every source.',
  );

  static const ModularUiToggle searchPinned = ModularUiToggle(
    key: 'search.pinned',
    area: searchWindowArea,
    title: 'Pinned tags',
    description: 'The tags you pinned, as a row of chips in the search window, for every source. Pinning still works while it is hidden.',
  );

  static const ModularUiToggle searchPopular = ModularUiToggle(
    key: 'search.popular',
    area: searchWindowArea,
    title: 'Popular tags',
    description: "The source's most used tags, as a row of chips in the search window.",
  );

  static const ModularUiToggle searchSiteFilters = ModularUiToggle(
    key: 'search.siteFilters',
    area: searchWindowArea,
    title: 'Site filters (booru sources)',
    description: "The Filters card with the site's own sort/order and rating choices, on booru and art sources. Doujin sources always show theirs.",
    defaultValue: true,
  );

  static const String leftSidebarArea = 'Left sidebar';

  static const ModularUiToggle sidebarSourceSettings = ModularUiToggle(
    key: 'sidebar.sourceSettings',
    area: leftSidebarArea,
    title: 'Source settings button',
    description: "The \"<source> settings\" button for the current booru source, above Settings.",
    defaultValue: true,
  );

  static const String viewerArea = 'Viewer';

  static const ModularUiToggle viewerLinkedMedia = ModularUiToggle(
    key: 'viewer.linkedMedia',
    area: viewerArea,
    title: 'Linked media button (FurAffinity)',
    description: "A link button in the viewer's top bar on posts whose description links to media (another source's post, a video file, a video page): it lists those links.",
    defaultValue: true,
  );

  static const ModularUiToggle sidebarPinnedTags = ModularUiToggle(
    key: 'sidebar.pinnedTags',
    area: leftSidebarArea,
    title: 'Pinned tags button',
    description: 'A "<source> pinned tags" button in Quick access: build pins of one or several tags, edit, rename and delete them.',
    defaultValue: true,
  );

  static const ModularUiToggle viewerLinkedMediaReplacesShare = ModularUiToggle(
    key: 'viewer.linkedMediaReplacesShare',
    area: viewerArea,
    title: "Linked media in the share button's place",
    description: 'The share button leaves the top bar; the linked media button takes its place on posts whose description links to media. Off brings the share button back.',
    defaultValue: true,
  );

  static const ModularUiToggle viewerVideoCover = ModularUiToggle(
    key: 'viewer.videoCoverWhileLoading',
    area: viewerArea,
    title: 'Thumbnail until the video shows (media_kit)',
    description: 'While a video loads, and while you swipe to it, the page shows the post thumbnail instead of a black panel.',
    defaultValue: true,
  );

  static const String wholeAppArea = 'Whole app';

  static const ModularUiToggle appDrawUnderHiddenStatusBar = ModularUiToggle(
    key: 'app.drawUnderHiddenStatusBar',
    area: wholeAppArea,
    title: 'Draw under the hidden status bar',
    description: 'With the status bar hidden, pages start at the very top edge. Off keeps that edge free: Android catches taps there (a back arrow) for the swipe that shows the status bar.',
  );

  static const List<ModularUiToggle> all = [
    searchHistory,
    searchPinned,
    searchPopular,
    searchSiteFilters,
    sidebarSourceSettings,
    sidebarPinnedTags,
    viewerLinkedMedia,
    viewerLinkedMediaReplacesShare,
    viewerVideoCover,
    appDrawUnderHiddenStatusBar,
  ];

  /// Bumped on every change, for pages that show the switches.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static bool isOn(ModularUiToggle toggle) => SettingsHandler.instance.modularUi[toggle.key] ?? toggle.defaultValue;

  /// Writes the settings file; replaced in tests.
  @visibleForTesting
  static Future<void> Function() save = () => SettingsHandler.instance.saveSettings(restate: false);

  static Future<void> set(ModularUiToggle toggle, bool on) async {
    final Map<String, bool> values = SettingsHandler.instance.modularUi;
    if (on == toggle.defaultValue) {
      values.remove(toggle.key);
    } else {
      values[toggle.key] = on;
    }
    revision.value++;
    try {
      await save();
    } catch (_) {}
  }

  /// The stored map, keeping only switch values.
  static Map<String, bool> parse(dynamic raw) {
    final Map<String, bool> out = {};
    if (raw is Map) {
      raw.forEach((key, value) {
        if (key is String && value is bool) out[key] = value;
      });
    }
    return out;
  }
}
