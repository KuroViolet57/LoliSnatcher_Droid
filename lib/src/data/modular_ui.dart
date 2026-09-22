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

  static const String gridArea = 'Preview grid';

  static const ModularUiToggle feedScrollbar = ModularUiToggle(
    key: 'grid.feedScrollbar',
    area: gridArea,
    title: 'Feed scrollbar',
    description: 'The thin scrollbar at the side of a feed, which you can drag to jump. Off hides it; the feed scrolls the same.',
    defaultValue: true,
  );

  static const ModularUiToggle gridSeenThumbnailsAtOnce = ModularUiToggle(
    key: 'grid.seenThumbnailsAtOnce',
    area: gridArea,
    title: 'Seen thumbnails appear at once',
    description: 'A thumbnail already shown this session, or still in memory, appears without the short wait and fade-in when you scroll back to it. Off brings the wait and the fade back.',
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

  static const ModularUiToggle videoCapToScreen = ModularUiToggle(
    key: 'viewer.videoCapToScreen',
    area: viewerArea,
    title: 'Videos play at screen size',
    description: 'A video bigger than your screen is played at screen size instead of its own, which costs much less memory and drawing work (an 8K video about 7 times less). Off plays every video at its full resolution.',
    defaultValue: true,
  );

  static const ModularUiToggle imageCap4k = ModularUiToggle(
    key: 'viewer.imageCap4k',
    area: viewerArea,
    title: 'Pictures decode at 4K at most',
    description: 'A picture never decodes taller than 3840 pixels, which bounds very tall pictures. Turning image scaling off, or reloading one post without scaling, still loads it at full size.',
    defaultValue: true,
  );

  static const ModularUiToggle viewerPostActionsAsButtons = ModularUiToggle(
    key: 'viewer.postActionsAsButtons',
    area: viewerArea,
    title: 'Post actions as buttons',
    description: "In a post's info sheet, Comments, Find elsewhere, a new board, Similar posts and Recommend are buttons next to Favorite, Save, Collect and Details. Off brings back their full-width rows below the block.",
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
    feedScrollbar,
    gridSeenThumbnailsAtOnce,
    viewerLinkedMedia,
    videoCapToScreen,
    imageCap4k,
    viewerPostActionsAsButtons,
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
