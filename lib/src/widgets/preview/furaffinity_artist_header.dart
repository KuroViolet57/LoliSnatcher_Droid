import 'dart:async';

import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/boorus/furaffinity_handler.dart';
import 'package:lolisnatcher/src/boorus/furaffinity_parser.dart';
import 'package:lolisnatcher/src/boorus/furaffinity_query.dart';
import 'package:lolisnatcher/src/handlers/furaffinity_session_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/drawers/furaffinity_sidebar.dart';
import 'package:lolisnatcher/src/widgets/gallery/tag_view.dart';
import 'package:lolisnatcher/src/widgets/image/custom_network_image.dart';

/// The artist's card above a FurAffinity gallery, scraps, favorites or folder
/// tab (r40): avatar, name, counts; Gallery / Scraps / Favorites switch the
/// tab; Strips shows all three as horizontal rows instead of scrolling the
/// feed. r42: Folders (the artist's gallery folders) and, logged in, Watch.
class FurAffinityArtistHeader extends StatefulWidget {
  const FurAffinityArtistHeader({required this.tab, super.key});

  final SearchTab tab;

  /// Strips or feed, for the session.
  static final ValueNotifier<bool> strips = ValueNotifier(false);

  @override
  State<FurAffinityArtistHeader> createState() => _FurAffinityArtistHeaderState();
}

class _FurAffinityArtistHeaderState extends State<FurAffinityArtistHeader> {
  Future<FurAffinityUser?>? _user;
  String _for = '';
  bool? _watching;

  Future<void> _checkWatch(FurAffinityHandler handler, String user) async {
    final link = await handler.fetchWatchLink(user);
    if (mounted && _for == user) setState(() => _watching = link?.watching);
  }

  Future<void> _toggleWatch(FurAffinityHandler handler, String user) async {
    final result = await handler.toggleWatch(user);
    if (!mounted) return;
    setState(() => _watching = result.watching);
    FlashElements.showSnackbar(context: context, title: Text(result.message));
  }

  @override
  Widget build(BuildContext context) {
    final handler = widget.tab.booruHandler;
    if (handler is! FurAffinityHandler) return const SizedBox.shrink();
    final FurAffinityQuery query = FurAffinityQuery.parse(widget.tab.tags);
    if (query.user.isEmpty) return const SizedBox.shrink();
    if (_for != query.user) {
      _for = query.user;
      _user = handler.fetchUser(query.user);
      _watching = null;
      if (FurAffinitySessionHandler.instance.isLoggedIn) unawaited(_checkWatch(handler, query.user));
    }
    final theme = Theme.of(context);
    final NumberFormat count = NumberFormat.decimalPattern();

    void open(String route) => SearchHandler.instance.searchAction('$route:${query.user}', null);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.25)),
        ),
        child: FutureBuilder<FurAffinityUser?>(
          future: _user,
          builder: (context, snapshot) {
            final FurAffinityUser? user = snapshot.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: (user?.avatarUrl.isNotEmpty ?? false)
                            ? Image(
                                image: CustomNetworkImage(user!.avatarUrl, withCache: true, cacheFolder: 'avatars'),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black26),
                              )
                            : const ColoredBox(color: Colors.black26),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (user?.displayName.isNotEmpty ?? false) ? user!.displayName : query.user,
                            key: const ValueKey('fa-artist-name'),
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            user == null
                                ? '~${query.user}'
                                : '~${user.username} · ${count.format(user.submissions)} submissions · ${count.format(user.favorites)} favs',
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (_watching != null)
                      FilledButton.tonal(
                        key: const ValueKey('fa-artist-watch'),
                        onPressed: () => _toggleWatch(handler, query.user),
                        child: Text(_watching! ? 'Unwatch' : 'Watch'),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                ValueListenableBuilder<bool>(
                  valueListenable: FurAffinityArtistHeader.strips,
                  builder: (context, strips, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final (FurAffinityRoute route, String label, String key) in const [
                            (FurAffinityRoute.gallery, 'Gallery', 'gallery'),
                            (FurAffinityRoute.scraps, 'Scraps', 'scraps'),
                            (FurAffinityRoute.favorites, 'Favorites', 'favorites'),
                          ])
                            ChoiceChip(
                              key: ValueKey('fa-artist-$key'),
                              label: Text(label),
                              selected: !strips && query.kind == route,
                              onSelected: (_) {
                                FurAffinityArtistHeader.strips.value = false;
                                if (query.kind != route) open(key);
                              },
                            ),
                          ChoiceChip(
                            key: const ValueKey('fa-artist-folders'),
                            avatar: const Icon(Symbols.folder_rounded, size: 18),
                            label: const Text('Folders'),
                            selected: !strips && query.kind == FurAffinityRoute.folder,
                            onSelected: (_) => FurAffinityFolderList.show(
                              context,
                              handler: handler,
                              username: query.user,
                              onOpen: (String term) {
                                FurAffinityArtistHeader.strips.value = false;
                                SearchHandler.instance.searchAction(term, null);
                              },
                            ),
                          ),
                          FilterChip(
                            key: const ValueKey('fa-artist-strips'),
                            avatar: const Icon(Symbols.view_carousel_rounded, size: 18),
                            label: const Text('Strips'),
                            selected: strips,
                            onSelected: (v) => FurAffinityArtistHeader.strips.value = v,
                          ),
                        ],
                      ),
                      if (strips)
                        for (final (String key, String label) in const [('gallery', 'Gallery'), ('scraps', 'Scraps'), ('favorites', 'Favorites')])
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: TagContentPreview(
                              key: ValueKey('fa-strip-$key-${query.user}'),
                              tag: '$key:${query.user}',
                              boorus: [widget.tab.selectedBooru.value],
                              parentTab: widget.tab,
                              compact: true,
                              compactTitle: label,
                              hideWhenEmpty: true,
                            ),
                          ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
