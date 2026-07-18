import 'dart:async';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:get/get.dart' hide FirstWhereOrNullExt;

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/local_auth_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/pages/collections_page.dart';
import 'package:lolisnatcher/src/pages/foryou_page.dart';
import 'package:lolisnatcher/src/pages/settings_page.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/common/cancel_button.dart';
import 'package:lolisnatcher/src/widgets/common/mascot_image.dart';
import 'package:lolisnatcher/src/widgets/common/multibooru_toggle.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/preview/main_search_bar.dart';
import 'package:lolisnatcher/src/widgets/saved_searches/saved_search_tile.dart';
import 'package:lolisnatcher/src/widgets/saved_searches/saved_searches_page.dart';
import 'package:lolisnatcher/src/widgets/booru/booru_switcher_sheet.dart';
import 'package:lolisnatcher/src/widgets/common/inner_drawer.dart';
import 'package:lolisnatcher/src/widgets/image/booru_favicon.dart';
import 'package:lolisnatcher/src/widgets/webview/webview_page.dart';

class MainDrawer extends StatelessWidget {
  const MainDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    final SearchHandler searchHandler = SearchHandler.instance;

    Future<Booru?> showSelectWebviewBooruDialog(List<Booru> boorus) async {
      return showDialog<Booru?>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(context.loc.mobileHome.selectBooruForWebview),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 16,
              children: [
                SizedBox(
                  width: MediaQuery.sizeOf(context).width,
                  height: 52,
                  child: SettingsBooruDropdown(
                    value: null,
                    items: boorus,
                    onChanged: (Booru? newBooru) {
                      if (newBooru == null) return;

                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        Navigator.of(context).pop(newBooru);
                      });
                    },
                    title: context.loc.booru,
                    contentPadding: EdgeInsets.zero,
                    titleAsLabel: true,
                    drawBottomBorder: false,
                  ),
                ),
                //
                const CancelButton(withIcon: true),
              ],
            ),
          );
        },
      );
    }

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            // Flow drawer header
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 8, 2),
              child: Row(
                children: [
                  Text(
                    'Menu',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Symbols.close_rounded),
                    onPressed: () {
                      final state = SearchHandler.instance.mainDrawerKey.currentState;
                      if (state is InnerDrawerState) state.close();
                    },
                  ),
                ],
              ),
            ),
            RepaintBoundary(
              child: Obx(() {
                if (settingsHandler.booruList.isNotEmpty && searchHandler.tabs.isNotEmpty) {
                  return Container(
                    height: MainSearchBar.height,
                    margin: const EdgeInsets.fromLTRB(2, 4, 2, 12),
                    child: const MainSearchBarWithActions('drawer'),
                  );
                } else {
                  return const SizedBox.shrink();
                }
              }),
            ),
            // Flow current-booru card → opens the Switch booru sheet.
            Obx(() {
              if (settingsHandler.booruList.isEmpty || searchHandler.tabs.isEmpty) {
                return const SizedBox.shrink();
              }
              final booru = searchHandler.currentBooru;
              return Padding(
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => showBooruSwitcherSheet(context),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(width: 32, height: 32, child: BooruFavicon(booru, size: 32)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                booru.name ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                              ),
                              Text(
                                'current booru · tap to switch',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Symbols.unfold_more_rounded, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              );
            }),
            Expanded(
              child: ListView(
                controller: ScrollController(),
                clipBehavior: Clip.antiAlias,
                children: [
                  const SizedBox(height: 8),
                  const MergeBooruToggleAndSelector(),
                  Builder(
                    builder: (context) {
                      Booru? virtual(bool Function(BooruType) test) {
                        for (final b in settingsHandler.booruList) {
                          final t = b.type;
                          if (t != null && test(t)) return b;
                        }
                        return null;
                      }

                      void openVirtual(Booru? b) {
                        if (b == null) return;
                        final state = searchHandler.mainDrawerKey.currentState;
                        if (state is InnerDrawerState) state.close();
                        searchHandler.addTabByString('', customBooru: b, switchToNew: true);
                      }

                      final downloads = virtual((t) => t.isDownloads);
                      final favourites = virtual((t) => t.isFavourites);
                      return Column(
                        children: [
                          if (downloads != null)
                            SettingsButton(
                              name: 'Downloads',
                              icon: const Icon(Symbols.download_rounded),
                              action: () => openVirtual(downloads),
                            ),
                          if (favourites != null)
                            SettingsButton(
                              name: 'Favourites',
                              icon: const Icon(Symbols.favorite_rounded),
                              action: () => openVirtual(favourites),
                            ),
                        ],
                      );
                    },
                  ),
                  ListenableBuilder(
                    listenable: Listenable.merge([
                      LocalAuthHandler.instance.deviceSupportsBiometrics,
                      SettingsHandler.instance.useLockscreen,
                    ]),
                    builder: (_, child) {
                      final deviceSupportsBiometrics = LocalAuthHandler.instance.deviceSupportsBiometrics.value;
                      final useLockscreen = SettingsHandler.instance.useLockscreen.value;

                      if (deviceSupportsBiometrics && useLockscreen) {
                        return child!;
                      }

                      return const SizedBox.shrink();
                    },
                    child: SettingsButton(
                      name: context.loc.mobileHome.lockApp,
                      icon: const Icon(Symbols.lock_rounded),
                      action: () => LocalAuthHandler.instance.lock(manually: true),
                    ),
                  ),
                  SettingsButton(
                    name: context.loc.settings.title,
                    icon: const Icon(Symbols.settings_rounded),
                    page: () => const SettingsPage(),
                  ),
                  if (settingsHandler.dbEnabled)
                    SettingsButton(
                      name: 'For You',
                      icon: const Icon(Symbols.auto_awesome_rounded),
                      page: () => const ForYouPage(),
                    ),
                  if (settingsHandler.dbEnabled)
                    SettingsButton(
                      name: 'Collections',
                      icon: const Icon(Symbols.collections_bookmark_rounded),
                      page: () => const CollectionsPage(),
                    ),
                  Obx(() {
                    if (settingsHandler.booruList.isNotEmpty &&
                        searchHandler.tabs.isNotEmpty &&
                        Tools.isOnPlatformWithWebviewSupport) {
                      final List<Booru> boorus = [
                        searchHandler.currentBooru,
                        ...searchHandler.currentSecondaryBoorus.value ?? <Booru>[],
                      ].where((b) => b.baseURL?.isNotEmpty == true && BooruType.saveable.contains(b.type)).toList();

                      if (boorus.isEmpty) return const SizedBox.shrink();

                      return SettingsButton(
                        name: context.loc.settings.webview.openWebview,
                        icon: const Icon(Symbols.public_rounded),
                        action: () async {
                          final Booru? selectedBooru = boorus.length == 1
                              ? boorus.first
                              : await showSelectWebviewBooruDialog(boorus);
                          if (selectedBooru == null) return;

                          final String? url = selectedBooru.baseURL;
                          final String userAgent = Tools.browserUserAgent;
                          if (url == null || url.isEmpty) {
                            return;
                          }

                          unawaited(
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => InAppWebviewView(
                                  initialUrl: url,
                                  userAgent: userAgent,
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    }

                    return const SizedBox.shrink();
                  }),
                  // (The "update available" row was removed from the drawer
                  // per user request — updates stay reachable via Settings →
                  // Check for updates.)
                  //
                  if (SettingsHandler.isDesktopPlatform)
                    SettingsButton(
                      name: context.loc.closeTheApp,
                      icon: const Icon(Symbols.exit_to_app_rounded),
                      action: () async {
                        // twice to trigger drawer close
                        await Navigator.of(context).maybePop();
                        await Future.delayed(const Duration(milliseconds: 400));
                        await Navigator.of(context).maybePop();
                      },
                    ),
                  //
                  if (settingsHandler.enableDrawerMascot) const MascotImage(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Collapsed-by-default panel in the main drawer that lists saved searches.
// Shows the first 5 entries and a "View all" button that opens the full
// SavedSearchesPage. Only renders when there's at least one saved search.
class SavedSearchesDrawerSection extends StatefulWidget {
  const SavedSearchesDrawerSection({super.key});

  @override
  State<SavedSearchesDrawerSection> createState() => _SavedSearchesDrawerSectionState();
}

class _SavedSearchesDrawerSectionState extends State<SavedSearchesDrawerSection> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SearchHandler.instance.reloadSavedSearches();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final searchHandler = SearchHandler.instance;
      final list = searchHandler.savedSearches;
      final preview = list.take(5).toList(growable: false);
      final theme = Theme.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Symbols.bookmarks_rounded),
            title: Text(
              list.isEmpty ? 'Saved searches' : 'Saved searches (${list.length})',
            ),
            trailing: Icon(_expanded ? Symbols.expand_less_rounded : Symbols.expand_more_rounded),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: !_expanded
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (list.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                          child: Text(
                            'No saved searches yet. Tap the bookmark icon in the search bar to add the current query.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      else
                        for (final entry in preview) SavedSearchTile(entry: entry),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: OutlinedButton.icon(
                          icon: const Icon(Symbols.list_rounded),
                          label: const Text('View all'),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const SavedSearchesPage(),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      );
    });
  }
}
