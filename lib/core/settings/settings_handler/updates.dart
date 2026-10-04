part of '../settings_handler.dart';

/// The update check and the changelog page.
extension SettingsUpdates on SettingsHandler {
  Future<void> checkUpdate({bool withMessage = false}) async {
    if (Tools.isTestMode) {
      return;
    }

    // const String fakeUpdate = '123'; // for tests // broken string
    // const Map<String, dynamic> = {}; // for tests // full json here

    try {
      const String updateFileName = EnvironmentConfig.isFromStore ? 'update_store.json' : 'update.json';
      final response = await DioNetwork.get(
        'https://raw.githubusercontent.com/NO-ob/LoliSnatcher_Droid/master/$updateFileName',
      );
      final json = response.data is String ? jsonDecode(response.data) : (response.data is Map ? response.data : {});
      if (json is Map && json.isEmpty) {
        throw Exception('Update file is empty');
      }

      try {
        Logger.Inst().log(
          jsonEncode(json),
          'SettingsHandler',
          'checkUpdate',
          LogTypes.settingsError,
        );
      } catch (_) {}

      updateInfo.value = UpdateInfo(
        versionName: json['version_name'] ?? '0.0.0',
        buildNumber: json['build_number'] ?? 0,
        title: json['title'] ?? '...',
        changelog: json['changelog'] ?? '...',
        isInStore: json['is_in_store'] ?? false,
        isImportant: json['is_important'] ?? false,
        storePackage: json['store_package'] ?? '',
        githubURL: json['github_url'] ?? 'https://github.com/NO-ob/LoliSnatcher_Droid/releases/latest',
      );

      final String? discordFromGithub = json['discord_url'];
      if (discordFromGithub != null && discordFromGithub.isNotEmpty) {
        // overwrite included discord url if it's not the same as the one in update info
        if (discordFromGithub != discordURL.value) {
          discordURL.value = discordFromGithub;
        }
      }

      if (Constants.updateInfo.buildNumber < (updateInfo.value!.buildNumber)) {
        // if current build number is less than update build number in json
        if (EnvironmentConfig.isFromStore) {
          // installed from store
          if (updateInfo.value!.isInStore) {
            // app is still in store
            showUpdate(withMessage || updateInfo.value!.isImportant);
          } else {
            // app was removed from store
            // then always notify user so they can move to github version and get news about removal
            showUpdate(true);
          }
        } else {
          // installed from github
          showUpdate(withMessage || updateInfo.value!.isImportant);
        }
      } else {
        final secureStorageHandler = SecureStorageHandler.instance;
        final viewedAtBuild = int.tryParse(
          await secureStorageHandler.read(SecureStorageKey.viewedUpdateChangelogForBuild) ?? '',
        );
        if (booruList.isEmpty) {
          // don't bother new (no boorus) users until next update
          await secureStorageHandler.write(
            SecureStorageKey.viewedUpdateChangelogForBuild,
            Constants.updateInfo.buildNumber.toString(),
          );
        } else if (viewedAtBuild == null || viewedAtBuild < Constants.updateInfo.buildNumber) {
          await secureStorageHandler.write(
            SecureStorageKey.viewedUpdateChangelogForBuild,
            Constants.updateInfo.buildNumber.toString(),
          );
          showUpdate(true, isAfterUpdate: true);
        } else {
          if (withMessage) {
            // otherwise show latest version message
            showLastVersionMessage();
          }
        }
      }
    } catch (e, s) {
      Logger.Inst().log(
        e.toString(),
        'SettingsHandler',
        'checkUpdate',
        LogTypes.settingsError,
        s: s,
      );
      if (withMessage) {
        FlashElements.showSnackbar(
          title: Text(
            loc.settings.checkForUpdates.updateCheckError,
            style: const TextStyle(fontSize: 20),
          ),
          content: Text(
            e.toString(),
          ),
          sideColor: Colors.red,
          leadingIcon: Symbols.update_rounded,
          leadingIconColor: Colors.red,
        );
      }
    }
  }

  void showLastVersionMessage() {
    FlashElements.showSnackbar(
      title: Text(
        loc.settings.checkForUpdates.youHaveLatestVersion,
        style: const TextStyle(fontSize: 20),
      ),
      sideColor: Colors.green,
      leadingIcon: Symbols.update_rounded,
      leadingIconColor: Colors.green,
      actionsBuilder: (context, controller) {
        return [
          ElevatedButton.icon(
            onPressed: () {
              controller.dismiss();
              showUpdate(
                true,
                isAfterUpdate: true,
              );
            },
            icon: const Icon(Symbols.list_alt_rounded),
            label: Text(
              loc.settings.checkForUpdates.viewLatestChangelog,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ];
      },
    );
  }

  void showUpdate(
    bool showMessage, {
    bool isAfterUpdate = false,
  }) {
    // ignore: no_leading_underscores_for_local_identifiers
    final _updateInfo = isAfterUpdate ? Constants.updateInfo : updateInfo.value;
    if (showMessage && _updateInfo != null) {
      const bool isFromStore = EnvironmentConfig.isFromStore;

      final bool isDiffVersion = Constants.updateInfo.buildNumber < _updateInfo.buildNumber;

      final ctx = NavigationHandler.instance.navContext;

      SettingsPageOpen(
        context: ctx,
        page: (_) => Scaffold(
          appBar: SettingsAppBar(
            title:
                '${isDiffVersion ? loc.settings.checkForUpdates.updateAvailable : '${isAfterUpdate ? loc.settings.checkForUpdates.whatsNew : loc.settings.checkForUpdates.updateChangelog}:'} ${_updateInfo.versionName}+${_updateInfo.buildNumber}',
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isDiffVersion) ...[
                          Text(
                            '${loc.settings.checkForUpdates.currentVersion}: ${Constants.updateInfo.versionName}+${Constants.updateInfo.buildNumber}',
                          ),
                          const Text(''),
                        ],
                        Text(
                          _updateInfo.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(''),
                        Text(
                          loc.settings.checkForUpdates.changelog,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(''),
                        Text(_updateInfo.changelog),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                        },
                        icon: const Icon(Symbols.close_rounded),
                        label: Text(isDiffVersion ? loc.later : loc.close),
                      ),
                      const SizedBox(width: 16),
                      if (isFromStore && _updateInfo.isInStore)
                        ElevatedButton.icon(
                          onPressed: () {
                            // try {
                            //   launchUrlString("market://details?id=" + _updateInfo.storePackage);
                            // } on PlatformException catch(e) {
                            //   launchUrlString("https://play.google.com/store/apps/details?id=" + _updateInfo.storePackage);
                            // }
                            launchUrlString(
                              'https://play.google.com/store/apps/details?id=${_updateInfo.storePackage}',
                              mode: LaunchMode.externalApplication,
                            );
                            Navigator.of(ctx).pop();
                          },
                          icon: const Icon(Symbols.play_arrow_rounded),
                          label: Text(loc.settings.checkForUpdates.visitPlayStore),
                        )
                      else
                        ElevatedButton.icon(
                          onPressed: () {
                            launchUrlString(
                              _updateInfo.githubURL,
                              mode: LaunchMode.externalApplication,
                            );
                            Navigator.of(ctx).pop();
                          },
                          icon: const Icon(Symbols.exit_to_app_rounded),
                          label: Text(loc.settings.checkForUpdates.visitReleases),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ).open();
    }
  }
}
