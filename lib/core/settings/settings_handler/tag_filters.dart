part of '../settings_handler.dart';

/// Hidden and marked tags (global and per source), sound/AI tags, and the item checks built on them.
extension SettingsTagFilters on SettingsHandler {
  /// Domain-aware wrapper around [parseTagsList]: doujin items (post URL
  /// host attribution) get their hidden-tag badges from the DOUJIN blacklist;
  /// everything else from the booru global blacklist. Every per-item surface
  /// (thumbnails, viewers, tag lists) should call this instead of
  /// [parseTagsList] so booru blacklist data never decorates doujin items.
  TagsListData parseTagsListForItem(BooruItem item, {bool isCapped = true}) {
    if (DoujinDataHandler.isDoujinItem(item)) {
      DoujinDataHandler.instance.ensureLoaded();
      return parseTagsList(
        item.tagsList,
        isCapped: isCapped,
        hiddenTokensOverride: SourceSettingsHandler.instance.tagBlacklistForItem(item),
        markedTokensOverride: DoujinDataHandler.instance.starredTags,
      );
    }
    return parseTagsList(item.tagsList, isCapped: isCapped);
  }

  TagsListData parseTagsList(
    List<Tag> itemTags, {
    bool isCapped = true,
    Set<String>? hiddenTokensOverride,
    Set<String>? markedTokensOverride,
  }) {
    final List<String> cleanItemTags = cleanTagsList(itemTags);
    // For the visual "this tag is in your blacklist" indicator we check the
    // tag against any plain-tag token mentioned in a global blacklist line.
    // (Multi-token lines still don't surface per-tag, but at least the
    // single-tag entries — which are what every existing user has — keep
    // their badge.)
    // `hiddenTokensOverride` swaps in a different blacklist (the doujin one,
    // normalized lowercase_underscores) in place of the booru-global tokens.
    List<String> hiddenInItem;
    if (hiddenTokensOverride != null) {
      hiddenInItem = cleanItemTags
          .where((tag) => hiddenTokensOverride.contains(SourceSettingsHandler.normalizeTagName(tag)))
          .toList();
    } else {
      final Set<String> globalTokens = blacklistedTagTokens;
      hiddenInItem = cleanItemTags.where(globalTokens.contains).toList();
    }
    // `markedTokensOverride` swaps in the doujin starred-tag store (normalized
    // tokens) in place of the booru markedTags list.
    List<String> markedInItem;
    if (markedTokensOverride != null) {
      markedInItem = cleanItemTags
          .where((tag) => markedTokensOverride.contains(SourceSettingsHandler.normalizeTagName(tag)))
          .toList();
    } else {
      markedInItem = cleanItemTags.where(markedTags.contains).toList();
    }
    final List<String> soundInItem = SettingsHandler.soundTags.where(cleanItemTags.contains).toList();
    final List<String> aiInItem = SettingsHandler.aiTags.where(cleanItemTags.contains).toList();

    if (isCapped) {
      if (hiddenInItem.length > 5) {
        hiddenInItem = [...hiddenInItem.take(5), '...'];
      }
      if (markedInItem.length > 5) {
        markedInItem = [...markedInItem.take(5), '...'];
      }
    }

    return TagsListData(hiddenInItem, markedInItem, soundInItem, aiInItem);
  }

  /// Proper line-based evaluation against the global blacklist only.
  /// Use this from places that don't have per-booru context.
  bool isItemHiddenGlobally(BooruItem item) {
    final lines = globalBlacklistLines;
    if (lines.isEmpty) return false;
    final ctx = BlacklistContext.fromItem(item);
    for (final line in lines) {
      if (line.matches(ctx)) return true;
    }
    return false;
  }

  bool containsMarked(List<String> itemTags) {
    return itemTags.any(markedTags.contains);
  }

  bool containsSound(List<String> itemTags) {
    return itemTags.any(SettingsHandler.soundTags.contains);
  }

  bool containsAI(List<String> itemTags) {
    return itemTags.any(SettingsHandler.aiTags.contains);
  }

  void addTagToList(String type, String tag) {
    switch (type) {
      case 'hated':
      case 'hidden':
        hiddenTags.add(tag);
        invalidateBlacklistCache();
        break;
      case 'loved':
      case 'marked':
        markedTags.add(tag);
        break;
      default:
        break;
    }
    saveSettings(restate: false);
  }

  void removeTagFromList(String type, String tag) {
    switch (type) {
      case 'hated':
      case 'hidden':
        hiddenTags.remove(tag);
        invalidateBlacklistCache();
        break;
      case 'loved':
      case 'marked':
        markedTags.remove(tag);
        break;
      default:
        break;
    }
    saveSettings(restate: false);
  }

  /// Per-booru hidden-tag helpers. `booruName` keys the map; `null`/empty
  /// names are ignored so virtual boorus (Favourites/Downloads/Merge) don't
  /// pollute the storage.
  bool isTagHiddenForBooru(String tag, String? booruName) {
    if (booruName == null || booruName.isEmpty) return false;
    return hiddenTagsPerBooru[booruName]?.contains(tag) ?? false;
  }

  Set<String> hiddenTagsForBooru(String? booruName) {
    if (booruName == null || booruName.isEmpty) return const <String>{};
    return hiddenTagsPerBooru[booruName] ?? const <String>{};
  }

  void addTagToBooruHiddenList(String booruName, String tag) {
    if (booruName.isEmpty || tag.isEmpty) return;
    hiddenTagsPerBooru.putIfAbsent(booruName, () => <String>{}).add(tag);
    invalidateBlacklistCache(booruName: booruName);
    saveSettings(restate: false);
  }

  void removeTagFromBooruHiddenList(String booruName, String tag) {
    final set = hiddenTagsPerBooru[booruName];
    if (set == null) return;
    set.remove(tag);
    if (set.isEmpty) hiddenTagsPerBooru.remove(booruName);
    invalidateBlacklistCache(booruName: booruName);
    saveSettings(restate: false);
  }

  List<BlacklistLine> get globalBlacklistLines {
    return _cachedGlobalLines ??= parseBlacklist(hiddenTags);
  }

  List<BlacklistLine> blacklistLinesForBooru(String? booruName) {
    if (booruName == null || booruName.isEmpty) return const [];
    final set = hiddenTagsPerBooru[booruName];
    if (set == null || set.isEmpty) return const [];
    return _cachedPerBooruLines.putIfAbsent(booruName, () => parseBlacklist(set));
  }

  void invalidateBlacklistCache({String? booruName}) {
    if (booruName == null) {
      _cachedGlobalLines = null;
      _cachedPerBooruLines.clear();
    } else {
      _cachedPerBooruLines.remove(booruName);
    }
  }

  /// True if any blacklist line that applies to [booru] matches [item].
  /// Honours the per-booru `ignoreGlobalBlacklist` toggle.
  bool isItemHiddenForBooru(BooruItem item, Booru booru) {
    final perBooru = blacklistLinesForBooru(booru.name);
    final global = booru.ignoreGlobalBlacklist ? const <BlacklistLine>[] : globalBlacklistLines;
    if (perBooru.isEmpty && global.isEmpty) return false;
    final ctx = BlacklistContext.fromItem(item);
    for (final line in perBooru) {
      if (line.matches(ctx)) return true;
    }
    for (final line in global) {
      if (line.matches(ctx)) return true;
    }
    return false;
  }

  /// All plain tag tokens referenced by any global blacklist line — used by
  /// the UI to mark individual tag chips with the red eye-slash indicator.
  Set<String> get blacklistedTagTokens {
    final out = <String>{};
    for (final line in globalBlacklistLines) {
      out.addAll(line.plainTagTokens);
    }
    return out;
  }

  List<String> cleanTagsList(List<Tag> tags) {
    List<String> cleanTags = [];
    cleanTags = tags
        .where((tag) => tag.fullString.isNotEmpty)
        .map((tag) => tag.fullString.trim().toLowerCase())
        .toList();
    cleanTags.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return cleanTags;
  }
}
