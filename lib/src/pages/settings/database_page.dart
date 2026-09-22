import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/idol_sankaku_handler.dart';
import 'package:lolisnatcher/src/boorus/sankaku_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/constants.dart';
import 'package:lolisnatcher/src/handlers/database_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/widgets/common/cancel_button.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

class DatabasePage extends StatefulWidget {
  const DatabasePage({super.key});

  @override
  State<DatabasePage> createState() => _DatabasePageState();
}

class _DatabasePageState extends State<DatabasePage> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final SearchHandler searchHandler = SearchHandler.instance;
  final ScrollController scrollController = ScrollController();

  bool dbEnabled = true,
      indexesEnabled = true,
      changingIndexes = false,
      searchHistoryEnabled = true,
      isUpdating = false,
      tagTypeFetchEnabled = true;
  int updatingFailed = 0, updatingDone = 0;
  BooruType? sankakuType;
  CancelToken? cancelToken;
  final TextEditingController sankakuSearchController = TextEditingController();
  List<BooruItem> updatingItems = [], failedItems = [];

  @override
  void initState() {
    super.initState();

    dbEnabled = settingsHandler.dbEnabled;
    indexesEnabled = settingsHandler.indexesEnabled;
    searchHistoryEnabled = settingsHandler.searchHistoryEnabled;
    tagTypeFetchEnabled = settingsHandler.tagTypeFetchEnabled;

    final List<Booru> sankakuBoorus = getSankakuBoorus();
    if (sankakuBoorus.isNotEmpty) {
      sankakuType = sankakuBoorus.first.type;
    }
  }

  @override
  void dispose() {
    scrollController.dispose();
    sankakuSearchController.dispose();
    cancelToken?.cancel();
    super.dispose();
  }

  Future<void> _onPopInvoked(_, _) async {
    if (isUpdating) {
      FlashElements.showSnackbar(
        title: Text(context.loc.settings.database.cantLeavePageNow, style: const TextStyle(fontSize: 20)),
        content: Text(
          context.loc.settings.database.sankakuDataUpdating,
          style: const TextStyle(fontSize: 16),
        ),
        leadingIcon: Symbols.warning_amber_rounded,
        leadingIconColor: Colors.yellow,
        sideColor: Colors.yellow,
      );
      return;
    }

    if (changingIndexes) {
      FlashElements.showSnackbar(
        title: Text(context.loc.settings.database.pleaseWaitTitle, style: const TextStyle(fontSize: 20)),
        content: Text(context.loc.settings.database.indexesBeingChanged, style: const TextStyle(fontSize: 16)),
        leadingIcon: Symbols.info_rounded,
        leadingIconColor: Colors.yellow,
        sideColor: Colors.yellow,
      );
      return;
    }

    settingsHandler.dbEnabled = dbEnabled;
    settingsHandler.indexesEnabled = indexesEnabled;
    settingsHandler.searchHistoryEnabled = searchHistoryEnabled;
    settingsHandler.tagTypeFetchEnabled = tagTypeFetchEnabled;
    await settingsHandler.saveSettings(restate: false);
  }

  List<Booru> getSankakuBoorus() {
    final List<Booru> sankakuBoorus = [];

    for (int i = 0; i < settingsHandler.booruList.length; i++) {
      if ((settingsHandler.booruList[i].type?.isSankaku == true ||
              settingsHandler.booruList[i].type?.isIdolSankaku == true) &&
          [
            ...SankakuHandler.knownUrls,
            ...IdolSankakuHandler.knownUrls,
            'sankakuapi.com',
          ].any((e) => settingsHandler.booruList[i].baseURL?.contains(e) ?? false)) {
        sankakuBoorus.add(settingsHandler.booruList[i]);
      }
    }
    return sankakuBoorus;
  }

  Future<bool> updateSankakuItems({List<BooruItem>? customItems}) async {
    if (isUpdating) {
      return false;
    }

    FlashElements.showSnackbar(
      duration: const Duration(seconds: 6),
      title: Text(context.loc.settings.database.sankakuFavouritesUpdateStarted, style: const TextStyle(fontSize: 20)),
      content: Column(
        children: [
          Text(context.loc.settings.database.sankakuNewUrlsInfo, style: const TextStyle(fontSize: 16)),
          Text(context.loc.settings.database.sankakuDontLeavePage, style: const TextStyle(fontSize: 14)),
        ],
      ),
      leadingIcon: Symbols.info_rounded,
      leadingIconColor: Colors.green,
      sideColor: Colors.green,
    );

    setState(() {
      updatingItems = [];
      failedItems = [];
      updatingFailed = 0;
      updatingDone = 0;
      isUpdating = true;
      cancelToken?.cancel();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });

    final List<Booru> sankakuBoorus = getSankakuBoorus().where((e) => e.type == sankakuType).toList();
    if (sankakuBoorus.isEmpty) {
      FlashElements.showSnackbar(
        title: Text(context.loc.settings.database.noSankakuConfigFound, style: const TextStyle(fontSize: 20)),
        leadingIcon: Symbols.warning_amber_rounded,
        leadingIconColor: Colors.red,
        sideColor: Colors.red,
      );

      setState(() {
        updatingFailed = 0;
        updatingDone = 0;
        isUpdating = false;
      });
      return true;
    }

    for (final Booru sankakuBooru in sankakuBoorus) {
      final SankakuHandler sankakuHandler = sankakuBooru.type?.isIdolSankaku == true
          ? IdolSankakuHandler(sankakuBooru, 10)
          : SankakuHandler(sankakuBooru, 10);
      updatingItems = customItems?.isNotEmpty == true
          ? customItems!
          : await settingsHandler.dbHandler.getSankakuItems(
              search: sankakuSearchController.text,
              idol: sankakuBooru.type?.isIdolSankaku == true,
            );

      safeSetState(() {});

      for (BooruItem item in updatingItems) {
        if (isUpdating) {
          await Future.delayed(const Duration(milliseconds: 100));
          cancelToken = CancelToken();
          final result = await sankakuHandler.loadItem(item: item, cancelToken: cancelToken);
          if (result.failed) {
            safeSetState(() {
              updatingFailed += 1;
              failedItems.add(item);
            });
            Logger.Inst().log(
              'something went wrong updating favourites: ${result.error}',
              'DataBasePage',
              'updateSankakuItems',
              LogTypes.exception,
            );
          } else if (!result.failed && result.item != null) {
            item = result.item!;
            unawaited(settingsHandler.dbHandler.updateBooruItem(item, BooruUpdateMode.urlUpdate));
            safeSetState(() {
              updatingDone += 1;
            });
          } else {
            safeSetState(() {
              updatingFailed += 1;
              failedItems.add(item);
            });
          }
        }
      }
    }

    if (isUpdating) {
      FlashElements.showSnackbar(
        title: Text(
          context.loc.settings.database.sankakuFavouritesUpdateComplete,
          style: const TextStyle(fontSize: 20),
        ),
        leadingIcon: Symbols.check_rounded,
        leadingIconColor: Colors.green,
        sideColor: Colors.green,
      );
    }

    safeSetState(() {
      updatingFailed = 0;
      updatingDone = 0;
      isUpdating = false;
    });

    return true;
  }

  void safeSetState(VoidCallback fn) {
    fn();
    if (mounted) {
      setState(() {});
    }
  }

  Future<bool> purgeFailedSankakuItems() async {
    FlashElements.showSnackbar(
      duration: const Duration(seconds: 6),
      title: Text(context.loc.settings.database.failedItemsPurgeStartedTitle, style: const TextStyle(fontSize: 20)),
      content: Column(
        children: [
          Text(context.loc.settings.database.failedItemsPurgeInfo, style: const TextStyle(fontSize: 16)),
        ],
      ),
      leadingIcon: Symbols.info_rounded,
      leadingIconColor: Colors.green,
      sideColor: Colors.green,
    );

    final List<String> failedIDs = await settingsHandler.dbHandler.getItemIDs(
      failedItems.map((e) => e.postURL).toList(),
    );
    await settingsHandler.dbHandler.deleteItem(failedIDs);
    setState(() {
      failedItems = [];
    });
    return true;
  }

  Future<void> changeIndexes(bool newValue) async {
    changingIndexes = true;
    setState(() {});

    indexesEnabled = newValue;

    if (newValue) {
      await settingsHandler.dbHandler.createIndexes();
    } else {
      await settingsHandler.dbHandler.dropIndexes();
    }

    changingIndexes = false;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !isUpdating && !changingIndexes,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: SettingsAppBar(
          title: context.loc.settings.database.title,
        ),
        body: Center(
          child: ListView(
            controller: scrollController,
            children: [
              SettingsToggle(
                value: dbEnabled,
                onChanged: (newValue) {
                  setState(() {
                    dbEnabled = newValue;
                  });
                },
                title: context.loc.settings.database.enableDatabase,
                trailingIcon: IconButton(
                  icon: const Icon(Symbols.help_rounded),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return SettingsDialog(
                          title: Text(context.loc.settings.database.title),
                          contentItems: [
                            Text(context.loc.settings.database.databaseInfo),
                            Text(context.loc.settings.database.databaseInfoSnatch),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              if (dbEnabled) ...[
                Stack(
                  children: [
                    IgnorePointer(
                      ignoring: changingIndexes,
                      child: Column(
                        children: [
                          SettingsToggle(
                            value: indexesEnabled,
                            onChanged: changeIndexes,
                            title: context.loc.settings.database.enableIndexing,
                            trailingIcon: IconButton(
                              icon: const Icon(Symbols.help_rounded),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (BuildContext context) {
                                    return SettingsDialog(
                                      title: Text(context.loc.settings.database.enableIndexing),
                                      contentItems: [
                                        Text(
                                          context.loc.settings.database.indexingInfo,
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                          if (settingsHandler.isDebug.value) ...[
                            SettingsButton(
                              name: context.loc.settings.database.createIndexesDebug,
                              icon: const Icon(Symbols.create_new_folder_rounded),
                              action: () async {
                                changingIndexes = true;
                                setState(() {});
                                await settingsHandler.dbHandler.createIndexes();
                                changingIndexes = false;
                                setState(() {});
                              },
                            ),
                            SettingsButton(
                              name: context.loc.settings.database.dropIndexesDebug,
                              icon: const Icon(Symbols.delete_forever_rounded),
                              action: () async {
                                changingIndexes = true;
                                setState(() {});
                                await settingsHandler.dbHandler.dropIndexes();
                                changingIndexes = false;
                                setState(() {});
                              },
                            ),
                            const SettingsButton(name: '', enabled: false),
                          ],
                        ],
                      ),
                    ),
                    if (changingIndexes)
                      Positioned.fill(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ColoredBox(
                                color: Colors.black.withValues(alpha: 0.5),
                              ),
                            ),
                            const Align(
                              alignment: Alignment.center,
                              child: SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                SettingsToggle(
                  value: searchHistoryEnabled,
                  onChanged: (newValue) {
                    setState(() {
                      searchHistoryEnabled = newValue;
                    });
                  },
                  title: context.loc.settings.database.enableSearchHistory,
                  trailingIcon: IconButton(
                    icon: const Icon(Symbols.help_rounded),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return SettingsDialog(
                            title: Text(context.loc.settings.database.enableSearchHistory),
                            contentItems: [
                              Text(context.loc.settings.database.searchHistoryInfo),
                              Text(context.loc.settings.database.searchHistoryRecords(limit: Constants.historyLimit)),
                              Text(context.loc.settings.database.searchHistoryTapInfo),
                              Text(
                                context.loc.settings.database.searchHistoryFavouritesInfo,
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
                SettingsToggle(
                  value: tagTypeFetchEnabled,
                  onChanged: (newValue) {
                    setState(() {
                      tagTypeFetchEnabled = newValue;
                    });
                  },
                  title: context.loc.settings.database.enableTagTypeFetching,
                  trailingIcon: IconButton(
                    icon: const Icon(Symbols.help_rounded),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return SettingsDialog(
                            title: Text(context.loc.settings.database.enableTagTypeFetching),
                            contentItems: [
                              Text(context.loc.settings.database.tagTypeFetchingInfo),
                              Text(context.loc.settings.database.tagTypeFetchingWarning),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
                const SettingsButton(name: '', enabled: false),
                SettingsButton(
                  name: context.loc.settings.database.deleteDatabase,
                  icon: Icon(Symbols.delete_forever_rounded, color: Theme.of(context).colorScheme.error),
                  action: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return SettingsDialog(
                          title: Text(context.loc.settings.database.deleteDatabaseConfirm),
                          actionButtons: [
                            const CancelButton(withIcon: true),
                            ElevatedButton.icon(
                              onPressed: () {
                                ServiceHandler.deleteDB(settingsHandler);

                                FlashElements.showSnackbar(
                                  context: context,
                                  title: Text(
                                    context.loc.settings.database.databaseDeleted,
                                    style: const TextStyle(fontSize: 20),
                                  ),
                                  content: Text(
                                    context.loc.settings.database.appRestartRequired,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                  leadingIcon: Symbols.delete_forever_rounded,
                                  leadingIconColor: Colors.red,
                                  sideColor: Colors.yellow,
                                );
                                Navigator.of(context).pop(true);
                              },
                              label: Text(context.loc.delete),
                              icon: const Icon(Symbols.delete_forever_rounded),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
                SettingsButton(
                  name: context.loc.settings.database.clearSnatchedItems,
                  icon: Icon(Symbols.delete_rounded, color: Theme.of(context).colorScheme.error),
                  trailingIcon: const Icon(Symbols.save_alt_rounded),
                  action: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return SettingsDialog(
                          title: Text(context.loc.settings.database.clearAllSnatchedConfirm),
                          actionButtons: [
                            const CancelButton(withIcon: true),
                            ElevatedButton.icon(
                              onPressed: () {
                                if (settingsHandler.dbHandler.db != null) {
                                  settingsHandler.dbHandler.clearSnatched();

                                  for (final tab in searchHandler.tabs) {
                                    for (final item in tab.booruHandler.fetched) {
                                      if (item.isSnatched.value == true) {
                                        item.isSnatched.value = false;
                                      }
                                    }
                                  }

                                  FlashElements.showSnackbar(
                                    context: context,
                                    title: Text(
                                      context.loc.settings.database.snatchedItemsCleared,
                                      style: const TextStyle(fontSize: 20),
                                    ),
                                    content: Text(
                                      context.loc.settings.database.appRestartMayBeRequired,
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                    leadingIcon: Symbols.delete_forever_rounded,
                                    leadingIconColor: Colors.red,
                                    sideColor: Colors.yellow,
                                  );
                                }
                                Navigator.of(context).pop(true);
                              },
                              label: Text(context.loc.clear),
                              icon: const Icon(Symbols.delete_forever_rounded),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
                SettingsButton(
                  name: context.loc.settings.database.clearFavouritedItems,
                  icon: Icon(Symbols.delete_rounded, color: Theme.of(context).colorScheme.error),
                  trailingIcon: const Icon(Symbols.favorite_rounded),
                  action: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return SettingsDialog(
                          title: Text(context.loc.settings.database.clearAllFavouritedConfirm),
                          actionButtons: [
                            const CancelButton(withIcon: true),
                            ElevatedButton.icon(
                              onPressed: () {
                                if (settingsHandler.dbHandler.db != null) {
                                  settingsHandler.dbHandler.clearFavourites();

                                  for (final tab in searchHandler.tabs) {
                                    for (final item in tab.booruHandler.fetched) {
                                      if (item.isFavourite.value == true) {
                                        item.isFavourite.value = false;
                                      }
                                    }
                                  }

                                  FlashElements.showSnackbar(
                                    context: context,
                                    title: Text(
                                      context.loc.settings.database.favouritesCleared,
                                      style: const TextStyle(fontSize: 20),
                                    ),
                                    content: Text(
                                      context.loc.settings.database.appRestartMayBeRequired,
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                    leadingIcon: Symbols.delete_forever_rounded,
                                    leadingIconColor: Colors.red,
                                    sideColor: Colors.yellow,
                                  );
                                }
                                Navigator.of(context).pop(true);
                              },
                              label: Text(context.loc.clear),
                              icon: const Icon(Symbols.delete_forever_rounded),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
                SettingsButton(
                  name: context.loc.settings.database.clearSearchHistory,
                  icon: Icon(Symbols.delete_rounded, color: Theme.of(context).colorScheme.error),
                  trailingIcon: const Icon(Symbols.history_rounded),
                  action: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return SettingsDialog(
                          title: Text(context.loc.settings.database.clearSearchHistoryConfirm),
                          actionButtons: [
                            const CancelButton(withIcon: true),
                            ElevatedButton.icon(
                              onPressed: () {
                                if (settingsHandler.dbHandler.db != null) {
                                  settingsHandler.dbHandler.deleteFromSearchHistory(null);
                                  FlashElements.showSnackbar(
                                    context: context,
                                    title: Text(
                                      context.loc.settings.database.searchHistoryCleared,
                                      style: const TextStyle(fontSize: 20),
                                    ),
                                    content: Text(
                                      context.loc.settings.database.appRestartMayBeRequired,
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                    leadingIcon: Symbols.delete_forever_rounded,
                                    leadingIconColor: Colors.red,
                                    sideColor: Colors.yellow,
                                  );
                                }
                                Navigator.of(context).pop(true);
                              },
                              label: Text(context.loc.clear),
                              icon: const Icon(Symbols.delete_forever_rounded),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
                if (sankakuType != null) ...[
                  const SettingsButton(name: '', enabled: false),
                  SettingsButton(name: context.loc.settings.database.sankakuFavouritesUpdate),
                  Stack(
                    children: [
                      IgnorePointer(
                        ignoring: isUpdating,
                        child: Column(
                          children: [
                            SettingsDropdown<BooruType?>(
                              value: sankakuType,
                              items: getSankakuBoorus().map((e) => e.type).toList(),
                              itemTitleBuilder: (BooruType? item) => item?.alias ?? '',
                              onChanged: (BooruType? newValue) {
                                setState(() {
                                  sankakuType = newValue;
                                });
                              },
                              title: context.loc.settings.database.sankakuTypeToUpdate,
                            ),
                            SettingsTextInput(
                              controller: sankakuSearchController,
                              title: context.loc.settings.database.searchQuery,
                              hintText: context.loc.settings.database.searchQueryOptional,
                              clearable: true,
                              pasteable: true,
                              enableIMEPersonalizedLearning: !settingsHandler.incognitoKeyboard,
                            ),
                            SettingsButton(
                              name: context.loc.settings.database.updateSankakuUrls,
                              trailingIcon: const Icon(Symbols.image_rounded),
                              action: updateSankakuItems,
                            ),
                          ],
                        ),
                      ),
                      if (isUpdating) ...[
                        Positioned.fill(
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: 0.5),
                          ),
                        ),
                        const Positioned.fill(
                          child: Align(
                            alignment: Alignment.center,
                            child: SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (isUpdating) ...[
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.loc.settings.database.updating(
                              count: updatingItems.isEmpty ? 0 : updatingItems.length,
                            ),
                          ),
                          Text(
                            context.loc.settings.database.left(
                              count: max(updatingItems.length - updatingDone - updatingFailed, 0),
                            ),
                          ),
                          Text(context.loc.settings.database.done(count: updatingDone)),
                          Text(context.loc.settings.database.failedSkipped(count: updatingFailed)),
                          const Text(''),
                          Text(
                            context.loc.settings.database.sankakuRateLimitWarning,
                          ),
                        ],
                      ),
                    ),
                    SettingsButton(
                      name: context.loc.settings.database.skipCurrentItem,
                      subtitle: Text(context.loc.settings.database.useIfStuck),
                      trailingIcon: const Icon(Symbols.skip_next_rounded),
                      drawTopBorder: true,
                      action: () {
                        cancelToken?.cancel();
                      },
                    ),
                    SettingsButton(
                      name: context.loc.settings.database.pressToStop,
                      trailingIcon: const Icon(Symbols.cancel_rounded),
                      drawTopBorder: true,
                      action: () {
                        setState(() {
                          isUpdating = false;
                          cancelToken?.cancel();
                        });
                      },
                    ),
                  ],
                  if (!isUpdating && failedItems.isNotEmpty) ...[
                    SettingsButton(
                      name: context.loc.settings.database.purgeFailedItems(count: failedItems.length),
                      trailingIcon: const Icon(Symbols.delete_forever_rounded),
                      drawTopBorder: true,
                      action: () {
                        setState(purgeFailedSankakuItems);
                      },
                    ),
                    SettingsButton(
                      name: context.loc.settings.database.retryFailedItems(count: failedItems.length),
                      trailingIcon: const Icon(Symbols.refresh_rounded),
                      drawTopBorder: true,
                      action: () {
                        updateSankakuItems(customItems: [...failedItems]);
                      },
                    ),
                  ],
                  const SettingsButton(name: '', enabled: false),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
