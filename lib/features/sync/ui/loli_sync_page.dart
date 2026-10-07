import 'dart:async';
import 'dart:core';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';

import 'package:lolisnatcher/core/logging/logger.dart';
import 'package:lolisnatcher/features/sync/logic/loli_sync_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/core/platform/service_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/features/sync/ui/loli_sync_progress_page.dart';
import 'package:lolisnatcher/core/utils/extensions.dart';
import 'package:lolisnatcher/core/ui/flash_elements.dart';
import 'package:lolisnatcher/core/ui/settings_widgets.dart';
import 'package:lolisnatcher/core/storage/database_handler.dart';

enum SyncSide {
  none,
  receiver,
  sender,
}

enum TabsMode {
  merge,
  replace,
  ;

  bool get isMerge => this == TabsMode.merge;
  bool get isReplace => this == TabsMode.replace;

  String get value {
    switch (this) {
      case TabsMode.merge:
        return 'Merge';
      case TabsMode.replace:
        return 'Replace';
    }
  }

  static TabsMode get defaultValue => TabsMode.merge;

  static TabsMode fromString(String value) {
    switch (value) {
      case 'Merge':
      case 'merge':
        return TabsMode.merge;
      case 'Replace':
      case 'replace':
        return TabsMode.replace;
    }

    return TabsMode.merge;
  }

  String get locName {
    switch (this) {
      case TabsMode.merge:
        return loc.settings.sync.merge;
      case TabsMode.replace:
        return loc.settings.sync.replace;
    }
  }
}

enum TagsMode {
  overwrite,
  preferTypeIfNone,
  ;

  bool get isOverwrite => this == TagsMode.overwrite;
  bool get isPreferTypeIfNone => this == TagsMode.preferTypeIfNone;

  String get value {
    switch (this) {
      case TagsMode.overwrite:
        return 'Overwrite';
      case TagsMode.preferTypeIfNone:
        return 'PreferTypeIfNone';
    }
  }

  static TagsMode get defaultValue => TagsMode.preferTypeIfNone;

  static TagsMode fromString(String value) {
    switch (value) {
      case 'Overwrite':
      case 'overwrite':
        return TagsMode.overwrite;
      case 'PreferTypeIfNone':
      case 'preferTypeIfNone':
        return TagsMode.preferTypeIfNone;
    }

    return TagsMode.preferTypeIfNone;
  }

  String get locName {
    switch (this) {
      case TagsMode.overwrite:
        return loc.settings.sync.overwrite;
      case TagsMode.preferTypeIfNone:
        return loc.settings.sync.preferTypeIfNone;
    }
  }
}

class LoliSyncPage extends StatefulWidget {
  const LoliSyncPage({super.key});

  @override
  State<LoliSyncPage> createState() => _LoliSyncPageState();
}

class _LoliSyncPageState extends State<LoliSyncPage> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final SearchHandler searchHandler = SearchHandler.instance;
  final TagHandler tagHandler = TagHandler.instance;

  final TextEditingController ipController = TextEditingController();
  final TextEditingController portController = TextEditingController();

  /// Typed from the receiving phone. Not written to settings.
  final TextEditingController codeController = TextEditingController();
  final TextEditingController favouritesSkipController = TextEditingController();
  final TextEditingController snatchedSkipController = TextEditingController();
  final TextEditingController startPortController = TextEditingController();

  final LoliSync testSync = LoliSync();

  StreamSubscription<String>? sub;

  SyncSide syncSide = SyncSide.none;

  bool favourites = false,
      favouritesv2 = false,
      snatched = false,
      settings = false,
      booru = false,
      tabs = false,
      tags = false,
      searchHistory = false,
      savedSearches = false;
  int favToggleCount = 0;
  TabsMode tabsMode = TabsMode.defaultValue;
  TagsMode tagsMode = TagsMode.defaultValue;
  int? favCount, snatchedCount, historyCount, savedCount;

  List<NetworkInterface> ipList = [];
  List<String> ipListNames = ['Auto', 'Localhost'];
  String selectedInterface = 'Auto';
  String? selectedAddress;

  Future<void> _onPopInvoked(bool didPop, _) async {
    if (didPop) {
      return;
    }

    testSync.killSync();
    settingsHandler.lastSyncIp = ipController.text;
    settingsHandler.lastSyncPort = portController.text;
    final bool result = await settingsHandler.saveSettings(restate: false);
    if (result) {
      Navigator.of(context).pop();
    }
  }

  @override
  void initState() {
    super.initState();

    ipController.text = settingsHandler.lastSyncIp;
    portController.text = settingsHandler.lastSyncPort;
    favouritesSkipController.text = '';

    getFavCount();
    getSnatchedCount();
    getSearchListCounts();
    getIPList();
  }

  void updateState() {
    setState(() {});
  }

  @override
  void dispose() {
    ipController.dispose();
    portController.dispose();
    codeController.dispose();
    favouritesSkipController.dispose();
    snatchedSkipController.dispose();
    startPortController.dispose();

    testSync.killSync();
    sub?.cancel();
    super.dispose();
  }

  Future<void> getFavCount() async {
    favCount = await settingsHandler.dbHandler.getFavouritesCount();
    updateState();
  }

  Future<void> getSnatchedCount() async {
    snatchedCount = await settingsHandler.dbHandler.getSnatchedCount();
    updateState();
  }

  Future<void> getSearchListCounts() async {
    try {
      historyCount = (await settingsHandler.dbHandler.getSearchHistory()).length;
      savedCount = (await settingsHandler.dbHandler.getSavedSearches()).length;
    } catch (e, s) {
      Logger.Inst().log(e.toString(), 'LoliSync', 'getSearchListCounts', LogTypes.exception, s: s);
      historyCount = 0;
      savedCount = 0;
    }
    updateState();
  }

  /// Empty when IP, port, and the session code are all filled.
  String _missingAddressOrCode() {
    if (ipController.text.isEmpty || portController.text.isEmpty) {
      return context.loc.settings.sync.pleaseEnterIPAndPort;
    }
    if (codeController.text.trim().isEmpty) {
      return context.loc.settings.sync.syncCodeRequired;
    }
    return '';
  }

  Future<void> getIPList() async {
    final List<NetworkInterface> temp = await ServiceHandler.getIPList();
    ipList.addAll(temp);
    ipListNames.addAll(temp.map((e) => e.name).toList());
    updateState();
  }

  Future<void> sendTestRequest() async {
    final String missing = _missingAddressOrCode();
    if (missing.isNotEmpty) {
      FlashElements.showSnackbar(
        context: context,
        title: Text(context.loc.settings.sync.errorTitle, style: const TextStyle(fontSize: 20)),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(missing),
          ],
        ),
        sideColor: Colors.red,
        leadingIcon: Symbols.error_rounded,
        leadingIconColor: Colors.red,
      );
      return;
    }

    testSync.killSync();
    final Stream<String> stream = testSync.startSync(
      ipController.text,
      portController.text,
      ['Test'],
      0,
      0,
      TabsMode.merge,
      TagsMode.preferTypeIfNone,
      code: codeController.text,
    );
    sub = stream.listen(
      (data) {
        // print(data);
      },
      onDone: testSync.killSync,
      onError: (e) {
        // print('Error $e');
        testSync.killSync();
      },
      cancelOnError: true,
    );
  }

  Widget selectBuild() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SettingsButton(
          name: context.loc.settings.sync.selectWhatYouWantToDo,
          icon: const Icon(Symbols.help_center_rounded),
          enabled: false,
        ),
        const SettingsButton(
          name: '',
          enabled: false,
        ),
        SettingsButton(
          name: context.loc.settings.sync.sendDataToDevice,
          icon: const Icon(Symbols.send_to_mobile_rounded),
          action: () {
            syncSide = SyncSide.sender;
            updateState();
          },
        ),
        SettingsButton(
          name: context.loc.settings.sync.receiveDataFromDevice,
          icon: const Icon(Symbols.dns_rounded),
          action: () {
            syncSide = SyncSide.receiver;
            updateState();
          },
        ),
      ],
    );
  }

  Widget senderBuild() {
    return ListView(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: Text(
            context.loc.settings.sync.senderInstructions,
          ),
        ),
        SettingsTextInput(
          controller: ipController,
          title: context.loc.settings.sync.ipAddress,
          hintText: context.loc.settings.sync.ipAddressPlaceholder,
          inputType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9.]'))],
          clearable: true,
          pasteable: true,
        ),
        SettingsTextInput(
          controller: portController,
          title: context.loc.settings.sync.port,
          hintText: context.loc.settings.sync.portPlaceholder,
          inputType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
          clearable: true,
          pasteable: true,
        ),
        SettingsTextInput(
          controller: codeController,
          title: context.loc.settings.sync.syncCode,
          hintText: context.loc.settings.sync.syncCodePlaceholder,
          subtitle: Text(context.loc.settings.sync.syncCodeHelp),
          inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]'))],
          clearable: true,
          pasteable: true,
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
        ),
        SettingsToggle(
          value: favouritesv2,
          onChanged: (newValue) {
            if (newValue) {
              favToggleCount++;
            }

            setState(() {
              favouritesv2 = newValue;
            });
          },
          title: context.loc.settings.sync.sendFavourites,
          subtitle: Text(context.loc.settings.sync.favouritesCount(count: favCount?.toString() ?? '...')),
          drawBottomBorder: !favouritesv2,
        ),
        if (favToggleCount > 2)
          SettingsToggle(
            value: favourites,
            onChanged: (newValue) {
              setState(() {
                favourites = newValue;
              });
            },
            title: context.loc.settings.sync.sendFavouritesLegacy,
            subtitle: Text(context.loc.settings.sync.favouritesCount(count: favCount?.toString() ?? '...')),
            drawBottomBorder: !favourites,
          ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: (favouritesv2 || favourites)
              ? SettingsTextInput(
                  controller: favouritesSkipController,
                  title: context.loc.settings.sync.syncFavsFrom,
                  inputType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                  clearable: true,
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  numberButtons: true,
                  numberStep: 100,
                  numberMin: 0,
                  numberMax: favCount?.toDouble() ?? double.infinity,
                  trailingIcon: IconButton(
                    icon: const Icon(Symbols.help_rounded),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) {
                          return SettingsDialog(
                            title: Text(context.loc.settings.sync.syncFavsFrom),
                            contentItems: [
                              Text(
                                context.loc.settings.sync.syncFavsFromHelpText1,
                              ),
                              Text(context.loc.settings.sync.syncFavsFromHelpText2),
                              const Text(''),
                              Text(
                                context.loc.settings.sync.syncFavsFromHelpText3,
                              ),
                              Text(context.loc.settings.sync.syncFavsFromHelpText4),
                            ],
                          );
                        },
                      );
                    },
                  ),
                )
              : const SizedBox.shrink(),
        ),
        SettingsToggle(
          value: snatched,
          onChanged: (newValue) {
            setState(() {
              snatched = newValue;
            });
          },
          title: context.loc.settings.sync.sendSnatchedHistory,
          subtitle: Text(context.loc.settings.sync.snatchedCount(count: snatchedCount?.toString() ?? '...')),
          drawBottomBorder: !snatched,
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: snatched
              ? SettingsTextInput(
                  controller: snatchedSkipController,
                  title: context.loc.settings.sync.syncSnatchedFrom,
                  inputType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                  clearable: true,
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  numberButtons: true,
                  numberStep: 100,
                  numberMin: 0,
                  numberMax: snatchedCount?.toDouble() ?? double.infinity,
                  trailingIcon: IconButton(
                    icon: const Icon(Symbols.help_rounded),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) {
                          return SettingsDialog(
                            title: Text(context.loc.settings.sync.syncSnatchedFrom),
                            contentItems: [
                              Text(
                                context.loc.settings.sync.syncSnatchedFromHelpText1,
                              ),
                              Text(context.loc.settings.sync.syncSnatchedFromHelpText2),
                              const Text(''),
                              Text(
                                context.loc.settings.sync.syncSnatchedFromHelpText3,
                              ),
                              Text(context.loc.settings.sync.syncSnatchedFromHelpText4),
                            ],
                          );
                        },
                      );
                    },
                  ),
                )
              : const SizedBox.shrink(),
        ),
        SettingsToggle(
          value: settings,
          onChanged: (newValue) {
            setState(() {
              settings = newValue;
            });
          },
          title: context.loc.settings.sync.sendSettings,
        ),
        SettingsToggle(
          value: booru,
          onChanged: (newValue) {
            setState(() {
              booru = newValue;
            });
          },
          title: context.loc.settings.sync.sendBooruConfigs,
          subtitle: Text(context.loc.settings.sync.configsCount(count: settingsHandler.booruList.length.toString())),
        ),
        SettingsToggle(
          value: tabs,
          onChanged: (newValue) {
            setState(() {
              tabs = newValue;
            });
          },
          title: context.loc.settings.sync.sendTabs,
          subtitle: Text(context.loc.settings.sync.tabsCount(count: searchHandler.total.toString())),
          drawBottomBorder: !tabs,
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: tabs
              ? SettingsOptionsList(
                  value: tabsMode,
                  items: TabsMode.values,
                  onChanged: (TabsMode? newValue) {
                    setState(() {
                      tabsMode = newValue!;
                    });
                  },
                  title: context.loc.settings.sync.tabsSyncMode,
                  itemTitleBuilder: (m) => m?.locName ?? '',
                  trailingIcon: IconButton(
                    icon: const Icon(Symbols.help_rounded),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) {
                          return SettingsDialog(
                            title: Text(context.loc.settings.sync.tabsSyncMode),
                            contentItems: [
                              Text(
                                context.loc.settings.sync.tabsSyncModeMerge,
                              ),
                              const Text(''),
                              Text(
                                context.loc.settings.sync.tabsSyncModeReplace,
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                )
              : const SizedBox.shrink(),
        ),
        SettingsToggle(
          value: tags,
          onChanged: (newValue) {
            setState(() {
              tags = newValue;
            });
          },
          title: context.loc.settings.sync.sendTags,
          subtitle: Text(context.loc.settings.sync.tagsCount(count: tagHandler.tagMap.entries.length.toString())),
          drawBottomBorder: !tags,
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: tags
              ? SettingsOptionsList(
                  value: tagsMode,
                  items: TagsMode.values,
                  onChanged: (TagsMode? newValue) {
                    setState(() {
                      tagsMode = newValue!;
                    });
                  },
                  title: context.loc.settings.sync.tagsSyncMode,
                  itemTitleBuilder: (m) => m?.locName ?? '',
                  trailingIcon: IconButton(
                    icon: const Icon(Symbols.help_rounded),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) {
                          return SettingsDialog(
                            title: Text(context.loc.settings.sync.tagsSyncMode),
                            contentItems: [
                              Text(
                                context.loc.settings.sync.tagsSyncModePreferTypeIfNone,
                              ),
                              const Text(''),
                              Text(
                                context.loc.settings.sync.tagsSyncModeOverwrite,
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                )
              : const SizedBox.shrink(),
        ),
        SettingsToggle(
          value: searchHistory,
          onChanged: (bool newValue) {
            setState(() {
              searchHistory = newValue;
            });
          },
          title: 'Send search history',
          subtitle: Text(
            'Searches you have typed on this phone: ${historyCount?.toString() ?? '...'}. '
            'A search the other phone already has is left as it is. A favourite here marks that same search there. '
            'This choice is not saved.',
          ),
        ),
        SettingsToggle(
          value: savedSearches,
          onChanged: (bool newValue) {
            setState(() {
              savedSearches = newValue;
            });
          },
          title: 'Send saved searches',
          subtitle: Text(
            'Booru bookmarks on this phone: ${savedCount?.toString() ?? '...'}. '
            'One the other phone already has is left, including its name. '
            'Doujin saved searches stay on the doujin list and are not sent. This choice is not saved.',
          ),
        ),
        const SettingsButton(name: '', enabled: false),
        SettingsButton(
          name: context.loc.settings.sync.testConnection,
          icon: const Icon(Symbols.wifi_tethering_rounded),
          action: sendTestRequest,
          trailingIcon: IconButton(
            icon: const Icon(Symbols.help_rounded),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) {
                  return SettingsDialog(
                    title: Text(context.loc.settings.sync.testConnection),
                    contentItems: [
                      Text(context.loc.settings.sync.testConnectionHelpText1),
                      Text(context.loc.settings.sync.testConnectionHelpText2),
                    ],
                  );
                },
              );
            },
          ),
        ),
        SettingsButton(
          name: context.loc.settings.sync.startSync,
          icon: const Icon(Symbols.send_to_mobile_rounded),
          action: () async {
            final bool isAddressEntered = ipController.text.isNotEmpty && portController.text.isNotEmpty;
            final bool isCodeEntered = codeController.text.trim().isNotEmpty;
            final bool isAnySyncSelected =
                favouritesv2 || favourites || snatched || settings || booru || tabs || tags || searchHistory || savedSearches;
            final bool syncAllowed = isAddressEntered && isCodeEntered && isAnySyncSelected;

            if (syncAllowed) {
              await SettingsPageOpen(
                context: context,
                page: (_) => LoliSyncProgressPage(
                  type: 'sender',
                  ip: ipController.text,
                  port: portController.text,
                  code: codeController.text,
                  favourites: favourites,
                  favouritesv2: favouritesv2,
                  favSkip: int.tryParse(favouritesSkipController.text) ?? 0,
                  snatched: snatched,
                  snatchedSkip: int.tryParse(snatchedSkipController.text) ?? 0,
                  settings: settings,
                  booru: booru,
                  tabs: tabs,
                  tabsMode: tabsMode,
                  tags: tags,
                  tagsMode: tagsMode,
                  searchHistory: searchHistory,
                  savedSearches: savedSearches,
                ),
              ).open();
              updateState();
            } else {
              String errorString = '???';
              if (!isAddressEntered) {
                errorString = context.loc.settings.sync.portAndIPCannotBeEmpty;
              } else if (!isCodeEntered) {
                errorString = context.loc.settings.sync.syncCodeRequired;
              } else if (!isAnySyncSelected) {
                errorString = context.loc.settings.sync.nothingSelectedToSync;
              }
              FlashElements.showSnackbar(
                context: context,
                title: Text(context.loc.settings.sync.errorTitle, style: const TextStyle(fontSize: 20)),
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(errorString),
                  ],
                ),
                sideColor: Colors.red,
                leadingIcon: Symbols.error_rounded,
                leadingIconColor: Colors.red,
              );
            }
          },
        ),
      ],
    );
  }

  Widget receiverBuild() {
    return ListView(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.loc.settings.sync.statsOfThisDevice),
              Text(context.loc.settings.sync.favouritesCount(count: favCount?.toFormattedString() ?? '...')),
              Text(context.loc.settings.sync.snatchedCount(count: snatchedCount?.toFormattedString() ?? '...')),
              Text(context.loc.settings.sync.configsCount(count: settingsHandler.booruList.length.toFormattedString())),
              Text(context.loc.settings.sync.tabsCount(count: searchHandler.total.toFormattedString())),
              Text('Search history: ${historyCount?.toFormattedString() ?? '...'}'),
              Text('Saved searches: ${savedCount?.toFormattedString() ?? '...'}'),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: Text(
            '${context.loc.settings.sync.receiverInstructions}\n${context.loc.settings.sync.syncCodeReceiverNote}',
          ),
        ),
        SettingsOptionsList(
          value: selectedInterface,
          items: ipListNames,
          onChanged: (String? newValue) {
            selectedInterface = newValue!;
            final NetworkInterface? findInterface = ipList.firstWhereOrNull((el) => el.name == newValue);

            if (newValue == 'Localhost') {
              selectedAddress = '127.0.0.1';
            } else {
              selectedAddress = findInterface?.addresses.first.address;
            }
            updateState();
          },
          title: context.loc.settings.sync.availableNetworkInterfaces,
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: Text(context.loc.settings.sync.selectedInterfaceIP(ip: selectedAddress ?? 'none')),
        ),
        SettingsTextInput(
          controller: startPortController,
          title: context.loc.settings.sync.serverPort,
          hintText: context.loc.settings.sync.serverPortPlaceholder,
          inputType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
          clearable: true,
          pasteable: true,
          floatingLabelBehavior: FloatingLabelBehavior.always,
        ),
        SettingsButton(
          name: context.loc.settings.sync.startReceiverServer,
          icon: const Icon(Symbols.dns_rounded),
          action: () async {
            await SettingsPageOpen(
              context: context,
              page: (_) => LoliSyncProgressPage(
                type: 'receiver',
                ip: selectedAddress,
                port: startPortController.text.isEmpty ? '8080' : startPortController.text,
              ),
            ).open();
            updateState();
          },
        ),
      ],
    );
  }

  Widget conditionalBuild() {
    if (syncSide == SyncSide.none) {
      return selectBuild();
    } else if (syncSide == SyncSide.sender) {
      return senderBuild();
    } else if (syncSide == SyncSide.receiver) {
      return receiverBuild();
    } else {
      // Should never happen but just in case
      return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: SettingsAppBar(
          title: context.loc.settings.sync.title,
        ),
        body: Center(child: conditionalBuild()),
      ),
    );
  }
}
