part of '../search_handler.dart';

class SearchTab {
  SearchTab(
    Booru selectedBooru,
    List<Booru>? secondaryBoorus,
    this.tags, {
    Map<String, String>? tagOverrides,
    Map<String, bool>? inheritMainTags,
    String? tabId,
    // Virtual/synthetic feeds (blended suggestions) supply their own handler
    // instead of one built from the booru's type.
    BooruHandler? customHandler,
    // Pool tabs: identity of the pool this tab shows. Kept as tab STATE (not a
    // tag string) because several sites have no pool metatag at all — the
    // pool only exists as its own page there.
    String? poolId,
    String? poolName,
    // Doujin detail tabs: the tab IS one doujin's detail page, not a feed.
    // postURL is the identity; title/thumb let the tab manager render the
    // cover before (or without) a fetch.
    this.doujinPostURL,
    this.doujinTitle,
    this.doujinThumb,
  }) : id = (tabId != null && tabId.isNotEmpty) ? tabId : uuid.v4() {
    // Locals, not initializing formals: the null check below has to promote them.
    // ignore: prefer_initializing_formals
    this.poolId = poolId;
    // ignore: prefer_initializing_formals
    this.poolName = poolName;
    this.selectedBooru = selectedBooru.obs;
    this.secondaryBoorus = Rxn<List<Booru>?>(secondaryBoorus);
    if (tagOverrides != null && tagOverrides.isNotEmpty) {
      this.tagOverrides.addAll(tagOverrides);
    }
    if (inheritMainTags != null && inheritMainTags.isNotEmpty) {
      this.inheritMainTags.addAll(inheritMainTags);
    }

    final List<Booru> tempBooruList = [];
    tempBooruList.add(selectedBooru);
    if (secondaryBoorus?.isNotEmpty == true) {
      tempBooruList.addAll(secondaryBoorus!);
    }
    if (customHandler != null) {
      booruHandler = customHandler;
      booruHandler.pageNum = 0;
      seedPersistedDoujinItem();
      return;
    }
    // r76: a tab opened from a post's Suggested strip carries the post in
    // its query (`suggest: … post:…`) and builds the strip's own loader,
    // also when restored from a saved tab.
    final SuggestionHandler? suggestions = SuggestionHandler.fromQuery(selectedBooru, 30, tags);
    if (suggestions != null) {
      booruHandler = suggestions;
      booruHandler.pageNum = 0;
      return;
    }
    // Rebuilt from persisted state on restore too, so a pool tab keeps
    // working across restarts.
    if (poolId != null && poolId.isNotEmpty) {
      booruHandler = PoolPostsHandler(
        selectedBooru,
        SettingsHandler.instance.itemLimit,
        poolId: poolId,
        poolName: poolName,
      );
      booruHandler.pageNum = 0;
      seedPersistedDoujinItem();
      return;
    }
    final temp = BooruHandlerFactory().getBooruHandler(tempBooruList, null);
    booruHandler = temp.booruHandler;
    booruHandler.pageNum = temp.startingPage;
    final handler = booruHandler;
    if (handler is MergebooruHandler) {
      handler.tagOverrides = Map<String, String>.from(this.tagOverrides);
      handler.inheritMainTags = Map<String, bool>.from(this.inheritMainTags);
    }
    seedPersistedDoujinItem();
  }
  // unique id to use for booru controller. Preserved across in-place search
  // changes and app restarts (see SearchTab tabId param + TabBackup.id) so the
  // visited-tabs history can track a tab as one entry rather than duplicating.
  final String id;
  String tags = '';
  /// Pool this tab shows, when it is one. Drives the red "pool" chip in
  /// TabRow and is persisted through TabBackup.
  String? poolId;
  String? poolName;
  bool get isPool => poolId?.isNotEmpty ?? false;

  /// Doujin detail tab state: when set, this tab renders one doujin's DETAIL
  /// PAGE as its whole content (no feed chrome). The handler still fetches
  /// the single item via the id: search in [tags]; these fields carry the
  /// identity and the tab-manager cover across restarts.
  String? doujinPostURL;
  String? doujinTitle;
  String? doujinThumb;

  /// A REAL doujin-detail tab (created as one, or restored with the marker).
  /// The tags heuristic keeps tabs from older backups working — they were
  /// created as `id:` searches on a doujin source before the marker existed.
  bool get isDoujinDetail =>
      (doujinPostURL?.isNotEmpty ?? false) ||
      (booruHandler.hasReader && tags.trim().toLowerCase().startsWith('id:'));

  /// `id:<serverId>` or `id:<serverId>/<key>` when the post URL is `/g/{id}/{key}`
  /// (HDoujin, niyaniya, e-hentai). Sources that only need the numeric id
  /// (nhentai) stay `id:<n>`.
  static String doujinIdQuery(BooruItem item) =>
      doujinIdQueryFrom(serverId: item.serverId ?? '', postURL: item.postURL);

  static String doujinIdQueryFrom({required String serverId, required String postURL}) {
    final String id = serverId.trim();
    if (id.isEmpty) return '';
    final String? key = galleryKeyFromPostURL(postURL, id);
    return key == null ? 'id:$id' : 'id:$id/$key';
  }

  static String? galleryKeyFromPostURL(String postURL, String id) {
    if (id.isEmpty) return null;
    final List<String> parts = [
      for (final p in Uri.tryParse(postURL)?.pathSegments ?? const [])
        if (p.isNotEmpty) p,
    ];
    final int idAt = parts.indexOf(id);
    if (idAt >= 0 && idAt + 1 < parts.length) {
      final String key = parts[idAt + 1];
      if (key.isNotEmpty && key != id) return key;
    }
    return null;
  }

  /// After a restart the listing-key map is gone, but the tab backup still
  /// has the gallery URL (and the key in its path). Plant a stub item so the
  /// detail page can `loadItem` without an `id:` search that would miss.
  bool seedPersistedDoujinItem() {
    final String? url = doujinPostURL;
    if (url == null || url.isEmpty) return false;
    if (booruHandler.fetched.isNotEmpty) return false;
    final String id = _serverIdFromDoujinTab();
    if (id.isEmpty) return false;
    final String thumb = doujinThumb ?? '';
    final item = BooruItem(
      fileURL: thumb,
      sampleURL: thumb,
      thumbnailURL: thumb,
      tagsList: const [],
      postURL: url,
      serverId: id,
    );
    if (doujinTitle != null && doujinTitle!.isNotEmpty) {
      item.description = doujinTitle;
    }
    booruHandler.fetched.add(item);
    booruHandler.filterFetched();
    return booruHandler.filteredFetched.isNotEmpty;
  }

  String _serverIdFromDoujinTab() {
    final match = RegExp(r'^id:([^/\s]+)', caseSensitive: false).firstMatch(tags.trim());
    if (match != null) return match.group(1)!;
    final List<String> parts = [
      for (final p in Uri.tryParse(doujinPostURL ?? '')?.pathSegments ?? const [])
        if (p.isNotEmpty) p,
    ];
    if (parts.length >= 2 && (parts[0] == 'g' || parts[0] == 'gallery')) return parts[1];
    return '';
  }

  // Tab group this tab belongs to (null = ungrouped). Groups are rendered as
  // bordered blocks in the tab manager; tabs opened from within a grouped tab
  // (tag taps etc.) inherit the group. Persisted via TabBackup.
  String? groupName;
  // Per-booru tag overrides used when this tab is in merge mode. Keyed by
  // child booru name. Reactive so the per-booru text fields refresh when
  // a new tab is restored from a backup.
  final RxMap<String, String> tagOverrides = <String, String>{}.obs;
  // Per-booru inherit flag. Missing key means inherit (additive, the default).
  // Explicit false means the override replaces the main tags for that booru.
  final RxMap<String, bool> inheritMainTags = <String, bool>{}.obs;

  // Pushes the current tagOverrides snapshot onto the merge handler. Called
  // by the search bar when the user triggers a new search so per-booru edits
  // made since the tab was created take effect on the next page-1 fetch.
  void syncTagOverridesToHandler() {
    final handler = booruHandler;
    if (handler is MergebooruHandler) {
      handler.tagOverrides = Map<String, String>.from(tagOverrides);
      handler.inheritMainTags = Map<String, bool>.from(inheritMainTags);
    }
  }

  /// Rebuilds this tab around an edited booru config.
  ///
  /// A tab builds its handler ONCE, from the booru's type at creation time,
  /// and holds a reference to that Booru object. Editing the booru replaces
  /// the entry in the booru list with a new object, so without this the open
  /// tab kept using the OLD handler forever — changing a site's type from
  /// (say) Nozomi to Gelbooru appeared to do nothing, and the tab quietly
  /// went on loading the old handler's hardcoded hosts.
  void rebuildHandler(Booru booru) {
    selectedBooru.value = booru;

    final List<Booru> tempBooruList = [booru, ...?secondaryBoorus.value];
    final temp = BooruHandlerFactory().getBooruHandler(tempBooruList, null);
    booruHandler = temp.booruHandler;
    booruHandler.pageNum = temp.startingPage;
    final handler = booruHandler;
    if (handler is MergebooruHandler) {
      handler.tagOverrides = Map<String, String>.from(tagOverrides);
      handler.inheritMainTags = Map<String, bool>.from(inheritMainTags);
    }
    // The previous handler's results came from a different site/API, so they
    // can't be kept. Re-seed a doujin stub from the persisted URL so an
    // HDoujin tab does not fall back to an id: search with no gallery key.
    selected.clear();
    seedPersistedDoujinItem();
  }

  late final Rx<Booru> selectedBooru;
  late final Rxn<List<Booru>?> secondaryBoorus;
  // NOT final: editing a booru's config (type/URL) has to be able to swap the
  // handler of tabs that are already open — see [rebuildHandler].
  late BooruHandler booruHandler;

  double scrollPosition = 0;
  RxList<BooruItem> selected = RxList<BooruItem>.from([]);

  BooruItem? itemWithKey(Key? key) {
    return booruHandler.filteredFetched.firstWhereOrNull((item) => item.key == key);
  }

  Future<bool?> toggleItemFavourite(
    int itemIndex, {
    bool? forcedValue,
    bool skipSnatching = false,
  }) async {
    final BooruItem item = booruHandler.filteredFetched[itemIndex];
    // Doujin items NEVER touch the shared favourites DB — any caller that
    // lands here with a doujin item (doujin tab OR a merge tab mixing one in)
    // is rerouted to the one doujin path (doujin store + site account sync).
    if (booruHandler.hasReader || DoujinDataHandler.isDoujinItem(item)) {
      if (forcedValue != null && DoujinDataHandler.instance.isFavourite(item) == forcedValue) {
        return forcedValue;
      }
      // In a merge tab, sync through the item's real source handler.
      BooruHandler syncHandler = booruHandler;
      final handler = booruHandler;
      if (!handler.hasReader && handler is MergebooruHandler) {
        syncHandler = handler.subHandlerForItem(item) ?? handler;
      }
      final result = await DoujinDataHandler.instance.toggleFavouriteSynced(item, syncHandler);
      return result.nowFavourite;
    }
    if (item.isFavourite.value != null) {
      if (item.tagsList.isEmpty || item.mediaType.value.isNeedToLoadItem) {
        // try to update the item before favouriting, do nothing on fail
        if (!booruHandler.hasLoadItemSupport) {
          return item.isFavourite.value;
        }

        final res = await booruHandler.loadItem(
          item: item,
          withCapcthaCheck: true,
        );
        if (res.failed ||
            res.item == null ||
            res.item!.tagsList.isEmpty ||
            res.item!.mediaType.value.isNeedToLoadItem) {
          return item.isFavourite.value;
        }
      }

      if (forcedValue == null) {
        await ServiceHandler.vibrate();
      }

      final bool newValue = forcedValue ?? (item.isFavourite.value == true ? false : true);
      item.isFavourite.value = newValue;
      InterestsHandler.instance.onItemFavourited(item, nowFavourite: newValue);

      final SettingsHandler settingsHandler = SettingsHandler.instance;
      if (!skipSnatching && settingsHandler.snatchOnFavourite && newValue && item.isSnatched.value != true) {
        SnatchHandler.instance.queue(
          [item],
          booruHandler.booru,
          settingsHandler.snatchCooldown,
          false,
        );
      }
      await settingsHandler.dbHandler.updateBooruItem(
        item,
        BooruUpdateMode.local,
      );

      // Sources with an account (kemono) mirror the heart to the site. The
      // local state is already set; a refusal is shown, never retried.
      if (booruHandler.hasSiteFavourites) {
        unawaited(
          booruHandler.setSiteFavourite(item, newValue).then((result) {
            if (!result.$1) {
              FlashElements.showSnackbar(
                title: const Text('Favourite kept on the phone only'),
                content: Text(result.$2),
                duration: const Duration(seconds: 5),
                sideColor: Colors.orange,
              );
            }
          }),
        );
      }

      // Keep the post visible for the rest of this session: the favourites /
      // snatched filters are meant to apply on LOAD, not to make a post vanish
      // the moment you like it (which used to happen mid-video). The refilter
      // itself stays so the blacklist and the other filters keep updating.
      booruHandler.exemptFromLiveFilter(item);

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // update filtered items list in case user has favourites filter enabled
        await Future.delayed(const Duration(milliseconds: 200));
        booruHandler.filterFetched();
      });
    }
    return item.isFavourite.value;
  }

  Future<void> updateFavForMultipleItems(
    List<BooruItem> items, {
    required bool newValue,
    bool skipSnatching = false,
  }) async {
    final SettingsHandler settingsHandler = SettingsHandler.instance;

    // Split off doujin items: they go through the one doujin favourite path
    // (doujin store + site sync), never the booru favourites DB.
    final List<BooruItem> doujinItems = [
      for (final i in items)
        if (booruHandler.hasReader || DoujinDataHandler.isDoujinItem(i)) i,
    ];
    if (doujinItems.isNotEmpty) {
      items = [
        for (final i in items)
          if (!doujinItems.contains(i)) i,
      ];
      final handler = booruHandler;
      for (final item in doujinItems) {
        BooruHandler syncHandler = handler;
        if (!handler.hasReader && handler is MergebooruHandler) {
          syncHandler = handler.subHandlerForItem(item) ?? handler;
        }
        if (DoujinDataHandler.instance.isFavourite(item) != newValue) {
          await DoujinDataHandler.instance.toggleFavouriteSynced(item, syncHandler);
        }
        booruHandler.exemptFromLiveFilter(item);
      }
      if (items.isEmpty) return;
    }
    if (!skipSnatching && settingsHandler.snatchOnFavourite && newValue) {
      SnatchHandler.instance.queue(
        items.where((e) => e.isSnatched.value != true).toList(),
        booruHandler.booru,
        settingsHandler.snatchCooldown,
        false,
      );
    }

    for (final BooruItem item in items) {
      item.isFavourite.value = newValue;
      // Same rule as the single-item path: liking something in bulk shouldn't
      // make it disappear until the feed is reloaded.
      booruHandler.exemptFromLiveFilter(item);
    }

    await settingsHandler.dbHandler.updateMultipleBooruItems(
      items,
      BooruUpdateMode.local,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // update filtered items list in case user has favourites filter enabled
      await Future.delayed(const Duration(milliseconds: 200));
      booruHandler.filterFetched();
    });
  }

  @override
  String toString() {
    return 'tags: $tags selectedBooru: $selectedBooru booruHandler: $booruHandler';
  }
}
