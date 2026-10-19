part of '../tag_view.dart';

enum _BlacklistScope { global, perBooru }

Future<_BlacklistScope?> _pickBlacklistScope(BuildContext context, Booru booru) async {
  final String? booruName = booru.name;
  // If the booru has no usable name (e.g. virtual Favourites/Downloads/Merge),
  // there's no "per-booru" target — just blacklist globally without asking.
  if (booruName == null || booruName.isEmpty) return _BlacklistScope.global;
  return showDialog<_BlacklistScope>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Add to blacklist'),
      contentPadding: EdgeInsets.zero,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Symbols.public_rounded),
            title: const Text('Globally'),
            subtitle: const Text('Hides items with this tag on every booru'),
            onTap: () => Navigator.of(ctx).pop(_BlacklistScope.global),
          ),
          ListTile(
            leading: const Icon(Symbols.collections_bookmark_rounded),
            title: const Text('Only on this booru'),
            subtitle: Text(booruName),
            onTap: () => Navigator.of(ctx).pop(_BlacklistScope.perBooru),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

Future<void> showTagDialog({
  required BuildContext context,
  required String tag,
  required BooruHandler handler,
  required bool isHidden,
  required bool isMarked,
  required bool isInSearch,
  required HasTabWithTagResult hasTabWithTag,
  required VoidCallback onUpdate,
  // The type the tag list shows (the source's own parse, the tag's own
  // type); the shared tag map alone missed artists it never stored (r50).
  TagType? knownType,
}) async {
  final settingsHandler = SettingsHandler.instance;
  final searchHandler = SearchHandler.instance;
  final tagHandler = TagHandler.instance;

  // Domain-aware: on a doujin source the shared booru tag map is not
  // consulted, so the dialog's header can't contradict the chip the user
  // just tapped (or offer an "Artist hub" for a tag the site doesn't call an
  // artist).
  final TagType resolvedType =
      knownType != null && knownType != TagType.none ? knownType : tagHandler.typeForDisplay(tag, handler.booru);
  final Color typeColor = resolvedType.getColour() ?? const Color(0xFF8A80A0);
  final String typeName = resolvedType.locName;
  final bool isDoujin = handler.hasReader;
  Widget buildContent(BuildContext context) {
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: isDoujin ? null : const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // drag handle (sheet only)
            if (!isDoujin)
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 2),
              width: 40,
              height: 4.5,
              decoration: BoxDecoration(
                color: const Color(0xFF4A4260),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            // Flow header: type-colour bar + tag name (in type colour) + type + close
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 30,
                    decoration: BoxDecoration(
                      color: typeColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tag.replaceAll('_', ' '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: typeColor,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          typeName,
                          style: const TextStyle(
                            color: Color(0xFF8A80A0),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Symbols.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  //
          // Boorusama-style floating preview window (draggable/resizable,
          // opens over whatever page spawned this dialog).
          ListTile(
            leading: Icon(
              Symbols.picture_in_picture_alt_rounded,
              color: Theme.of(context).colorScheme.secondary,
            ),
            title: Text(context.loc.tagView.preview),
            onTap: () {
              final Booru previewBooru = handler.booru.type?.isMerge == true
                  ? (handler as MergebooruHandler).booruHandlers.first.booru
                  : handler.booru;
              // r77: the page under this menu, taken before the menu closes.
              final Route<dynamic>? page = FloatingPreviewHandler.instance.topPageRoute;
              Navigator.of(context).pop();
              FloatingPreviewHandler.instance.open(
                tag: tag,
                booru: previewBooru,
                owner: page,
              );
            },
          ),
          //
          // Tag hub — a dedicated page showing this tag across every
          // configured booru. Artists get follow support and their own label.
          ListTile(
            leading: Icon(
              resolvedType.isArtist ? Symbols.artist_rounded : Symbols.hub_rounded,
              color: Theme.of(context).colorScheme.secondary,
            ),
            title: Text(resolvedType.isArtist ? 'Artist hub' : 'Tag hub'),
            subtitle: Text(
              resolvedType.isArtist
                  ? 'Follow + their work across your boorus'
                  : 'This tag across your boorus',
            ),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TagHubPage(
                    tag: tag,
                    originBooru: handler.booru,
                    knownType: resolvedType,
                  ),
                ),
              );
            },
          ),
          //
          ListTile(
            leading: Icon(
              Symbols.content_copy_rounded,
              color: Theme.of(context).iconTheme.color,
            ),
            title: Text(context.loc.tagView.copy),
            onTap: () {
              Clipboard.setData(ClipboardData(text: tag));
              FlashElements.showSnackbar(
                context: context,
                duration: const Duration(seconds: 2),
                title: Text(
                  context.loc.copiedToClipboard,
                  style: const TextStyle(fontSize: 20),
                ),
                content: Text(
                  tag,
                  style: const TextStyle(fontSize: 16),
                ),
                leadingIcon: Symbols.content_copy_rounded,
                sideColor: Colors.green,
              );
              Navigator.of(context).pop();
            },
          ),
          //
          if (isInSearch)
            ListTile(
              leading: Icon(
                Symbols.delete_rounded,
                color: Theme.of(context).iconTheme.color,
              ),
              title: Text(context.loc.tagView.removeFromSearch),
              onTap: () {
                searchHandler.removeTagFromSearch(tag);
                Navigator.of(context).pop();
              },
            )
          else
            const SizedBox.shrink(),
          //
          // Open the tag as a background tab inside a tab group — existing
          // group or a newly named one.
          ListTile(
            leading: Icon(
              Symbols.create_new_folder_rounded,
              color: Theme.of(context).iconTheme.color,
            ),
            title: const Text('Open in group'),
            subtitle: const Text('Inside a group, outside it, or a new one'),
            onTap: () {
              Navigator.of(context).pop();
              showOpenTagInGroupSheet(
                NavigationHandler.instance.navContext,
                tag,
                handler.booru,
              );
            },
          ),
          //
          if (!isHidden && !isMarked)
            ListTile(
              leading: const Icon(Symbols.star_rounded, color: Colors.yellow),
              title: Text(context.loc.tagView.addToMarked),
              onTap: () {
                if (DoujinDataHandler.isDoujinBooru(handler.booru)) {
                  // Doujin stars live in the doujin store only.
                  DoujinDataHandler.instance.starTag(tag);
                } else {
                  settingsHandler.addTagToList('marked', tag);
                }
                searchHandler.filterCurrentFetched();
                handler.filterFetched();
                onUpdate();
                Navigator.of(context).pop(true);
              },
            ),
          // The per-booru list is a BOORU store and never filters doujin
          // items, so it must not decide whether a doujin tag can be hidden.
          if (!isHidden &&
              !isMarked &&
              (DoujinDataHandler.isDoujinBooru(handler.booru) ||
                  !settingsHandler.isTagHiddenForBooru(tag, handler.booru.name)))
            ListTile(
              leading: const Icon(CupertinoIcons.eye_slash, color: Colors.red),
              title: Text(context.loc.tagView.addToHidden),
              onTap: () async {
                final scope = await _pickBlacklistScope(context, handler.booru);
                if (scope == null) return;
                if (DoujinDataHandler.isDoujinBooru(handler.booru)) {
                  // Doujin sources blacklist via sourceSettings only.
                  SourceSettingsHandler.instance.addBlacklistTag(
                    scope == _BlacklistScope.global ? null : handler.booru,
                    tag,
                  );
                } else if (scope == _BlacklistScope.global) {
                  settingsHandler.addTagToList('hidden', tag);
                } else if (handler.booru.name?.isNotEmpty == true) {
                  settingsHandler.addTagToBooruHiddenList(handler.booru.name!, tag);
                }
                searchHandler.filterCurrentFetched();
                handler.filterFetched();
                onUpdate();
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          if (isMarked)
            ListTile(
              leading: Icon(
                Symbols.star_border_rounded,
                color: Theme.of(context).iconTheme.color,
              ),
              title: Text(context.loc.tagView.removeFromMarked),
              onTap: () {
                if (DoujinDataHandler.isDoujinBooru(handler.booru)) {
                  DoujinDataHandler.instance.unstarTag(tag);
                } else {
                  settingsHandler.removeTagFromList('marked', tag);
                }
                onUpdate();
                Navigator.of(context).pop();
              },
            ),
          if (isHidden)
            ListTile(
              leading: Icon(
                CupertinoIcons.eye_slash,
                color: Theme.of(context).iconTheme.color,
              ),
              title: Text(context.loc.tagView.removeFromHidden),
              onTap: () {
                if (DoujinDataHandler.isDoujinBooru(handler.booru)) {
                  // The doujin hidden state comes from the doujin blacklist,
                  // so removal has to happen there.
                  SourceSettingsHandler.instance.removeBlacklistTag(handler.booru, tag);
                } else {
                  settingsHandler.removeTagFromList('hidden', tag);
                }
                searchHandler.filterCurrentFetched();
                handler.filterFetched();
                onUpdate();
                Navigator.of(context).pop();
              },
            ),
          if (!DoujinDataHandler.isDoujinBooru(handler.booru) &&
              settingsHandler.isTagHiddenForBooru(tag, handler.booru.name))
            ListTile(
              leading: Icon(
                CupertinoIcons.eye_slash,
                color: Theme.of(context).iconTheme.color,
              ),
              title: const Text("Remove from this booru's blacklist"),
              subtitle: Text(handler.booru.name ?? ''),
              onTap: () {
                final n = handler.booru.name;
                if (n != null && n.isNotEmpty) {
                  settingsHandler.removeTagFromBooruHiddenList(n, tag);
                  searchHandler.filterCurrentFetched();
                  handler.filterFetched();
                }
                onUpdate();
                Navigator.of(context).pop();
              },
            ),
          //
          FutureBuilder<PinnedTag?>(
            // Against THIS dialog's source, like every other action here. On
            // a merge tab the current booru is the Merge placeholder, so
            // reading the pin state from it disagreed with the batch bar,
            // which pins against the item's real source.
            future: DoujinDataHandler.isDoujinBooru(handler.booru)
                ? Future.value(() {
                    for (final p in doujinPinsAsPinnedTags(handler.booru)) {
                      if (p.tagName == tag) return p;
                    }
                    return null;
                  }())
                : settingsHandler.dbHandler.getPinnedTag(
                    tag,
                    booruType: handler.booru.type?.name,
                    booruName: handler.booru.name,
                  ),
            builder: (_, snapshot) {
              final isPinned = snapshot.data != null;
              final pinnedTag = snapshot.data;

              void reopenDialog() {
                Navigator.of(context).pop();
                showTagDialog(
                  context: context,
                  tag: tag,
                  handler: handler,
                  isHidden: isHidden,
                  isMarked: isMarked,
                  isInSearch: isInSearch,
                  hasTabWithTag: hasTabWithTag,
                  onUpdate: onUpdate,
                  knownType: knownType,
                );
              }

              return ListTile(
                title: Text(isPinned ? context.loc.pinnedTags.unpinTag : context.loc.pinnedTags.pinTag),
                leading: Icon(isPinned ? Symbols.push_pin_rounded : Symbols.push_pin_rounded),
                onTap: () async {
                  if (isPinned && pinnedTag != null) {
                    await showUnpinTagDialog(
                      context,
                      tag,
                      pinnedTag,
                      () {},
                    );
                  } else {
                    await showPinTagDialog(
                      context,
                      tag,
                      handler.booru,
                      () {},
                    );
                  }
                  reopenDialog();
                },
              );
            },
          ),
          //
          if (hasTabWithTag.hasTagInAnyForm)
            ListTile(
              leading: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    CupertinoIcons.doc_on_doc,
                    color: Theme.of(context).iconTheme.color,
                  ),

                  Positioned(
                    right: -5,
                    top: -5,
                    child: Icon(
                      Symbols.circle_rounded,
                      size: 6,
                      color: hasTabWithTag.color(context),
                    ),
                  ),
                ],
              ),
              title: Text(context.loc.tagView.relatedTabs),
              onTap: () => showRelatedTabsDialog(context, tag),
            ),
          // Edit tag removed from this menu — double-tapping the chip opens
          // the tag editor directly.
                ],
              ),
            ),
          ],
        ),
      );
  }

  // Doujin sources get the tag menu as a CENTERED popup; boorus keep the
  // bottom sheet.
  if (isDoujin) {
    await showDialog<void>(
      context: context,
      routeSettings: RouteSettings(name: 'tagDialog/$tag'),
      builder: (BuildContext context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: buildContent(context),
        ),
      ),
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    routeSettings: RouteSettings(name: 'tagDialog/$tag'),
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: buildContent,
  );
}

/// Bottom sheet to open [tag] as a background tab inside a tab group:
/// pick an existing group or name a new one on the spot.
/// Domain-correct "is this tag blacklisted / starred" for a bare tag STRING
/// on the source that [handler] belongs to. Doujin sources read the doujin
/// blacklist and the doujin star store; boorus read the global blacklist and
/// markedTags. Used where only a tag name is available (no item to run
/// parseTagsListForItem on).
bool tagHiddenForHandler(String tag, BooruHandler handler) {
  if (DoujinDataHandler.isDoujinBooru(handler.booru)) {
    return SourceSettingsHandler.instance
        .tagBlacklist(handler.booru)
        .contains(DoujinDataHandler.normalizeTag(tag));
  }
  return SettingsHandler.instance.hiddenTags.contains(tag);
}

bool tagMarkedForHandler(String tag, BooruHandler handler) {
  if (DoujinDataHandler.isDoujinBooru(handler.booru)) {
    return DoujinDataHandler.instance.isTagStarred(tag);
  }
  return SettingsHandler.instance.markedTags.contains(tag);
}
