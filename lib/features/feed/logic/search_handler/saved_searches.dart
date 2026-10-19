part of '../search_handler.dart';

/// Saved searches.
extension SearchSavedSearches on SearchHandler {
  Future<void> reloadSavedSearches() async {
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    savedSearches.assignAll(await settingsHandler.dbHandler.getSavedSearches());
  }

  // Snapshots the current tab as a SavedSearch and persists it. Returns the
  // new id (or null if persistence failed). Name is optional; empty falls
  // back to the tag string at display time.
  Future<int?> addCurrentTabAsSavedSearch({String? name}) async {
    if (tabs.isEmpty) return null;
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    final SearchTab tab = currentTab;
    // Doujin tabs save into the doujin store, never the booru SavedSearch
    // table — the doujin saved-searches screen scopes them per source.
    // Merge tabs (secondaries present) are hybrids and stay booru-side so
    // their secondaries/overrides aren't dropped.
    if (DoujinDataHandler.isDoujinBooru(tab.selectedBooru.value) &&
        (tab.secondaryBoorus.value?.isEmpty ?? true)) {
      final entry = DoujinDataHandler.instance.addSavedSearch(
        name: name?.trim() ?? '',
        query: tab.tags,
        booru: tab.selectedBooru.value,
      );
      return entry.id;
    }
    final entry = SavedSearch(
      id: null,
      name: name?.trim() ?? '',
      tags: tab.tags,
      booru: tab.selectedBooru.value.name ?? '',
      secondaryBoorus:
          tab.secondaryBoorus.value?.map((b) => b.name ?? '').where((e) => e.isNotEmpty).toList() ?? const [],
      tagOverrides: Map<String, String>.from(tab.tagOverrides)..removeWhere((_, v) => v.trim().isEmpty),
      inheritMainTags: Map<String, bool>.from(tab.inheritMainTags)..removeWhere((_, v) => v),
      createdAt: DateTime.now(),
    );
    final int? id = await settingsHandler.dbHandler.addSavedSearch(entry);
    await reloadSavedSearches();
    return id;
  }

  Future<void> deleteSavedSearch(int id) async {
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    await settingsHandler.dbHandler.deleteSavedSearch(id);
    await reloadSavedSearches();
  }

  Future<void> renameSavedSearch(int id, String name) async {
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    await settingsHandler.dbHandler.renameSavedSearch(id, name);
    await reloadSavedSearches();
  }

  // Opens a saved search as a new tab. `customBooru` overrides the saved
  // primary (used by the "open in another booru" action). Respects the
  // user's defaultTabAddMode setting and switches focus to the new tab.
  void openSavedSearch(
    SavedSearch entry, {
    Booru? customBooru,
  }) {
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    final List<Booru> allBoorus = settingsHandler.booruList;
    final Booru? primary = customBooru ??
        allBoorus.firstWhereOrNull((b) => b.name == entry.booru);
    if (primary == null) return;

    final TabAddMode addMode = TabAddMode.values.firstWhereOrNull(
          (m) => m.name == settingsHandler.defaultTabAddMode,
        ) ??
        TabAddMode.end;
    addTabByString(
      entry.tags,
      switchToNew: true,
      customBooru: primary,
      secondaryBoorus: entry.resolveSecondaryBoorus(allBoorus),
      addMode: addMode,
      tagOverrides: entry.tagOverrides.isEmpty ? null : Map<String, String>.from(entry.tagOverrides),
      inheritMainTags:
          entry.inheritMainTags.isEmpty ? null : Map<String, bool>.from(entry.inheritMainTags),
    );
  }
}
