part of '../settings_handler.dart';

/// The two startup phases: initialize (before the first frame) and postInit (database, sources, tags, tabs).
extension SettingsStartup on SettingsHandler {
  Future<bool> loadDatabase(ValueChanged<String> onStatusUpdate) async {
    try {
      if (!Tools.isTestMode) {
        if (dbEnabled) {
          await dbHandler.dbConnect(
            path,
            onStatusUpdate: onStatusUpdate,
          );
        } else {
          dbHandler = DBHandler();
        }
      }
      return true;
    } catch (e, s) {
      Logger.Inst().log(
        'loadDatabase error: $e',
        'SettingsHandler',
        'loadDatabase',
        LogTypes.exception,
        s: s,
      );
      return false;
    }
  }

  Future<bool> indexDatabase() async {
    try {
      if (!Tools.isTestMode) {
        if (dbEnabled) {
          if (indexesEnabled) {
            postInitMessage.value = '${loc.settings.database.indexingDatabase}...\n${loc.thisMayTakeSomeTime}';
            await dbHandler.createIndexes();
          } else {
            postInitMessage.value = '${loc.settings.database.droppingIndexes}...\n${loc.thisMayTakeSomeTime}';
            await dbHandler.dropIndexes();
          }
        }
      }
      return true;
    } catch (e, s) {
      Logger.Inst().log(
        'indexDatabase error: $e',
        'SettingsHandler',
        'indexDatabase',
        LogTypes.exception,
        s: s,
      );
      return false;
    }
  }

  Future<void> setLocale(AppLocale? locale) async {
    if (locale == null) {
      await LocaleSettings.useDeviceLocale();
    } else {
      await LocaleSettings.setLocale(locale);
    }
  }

  Future<void> initialize() async {
    if (isInit.value == true) {
      return;
    }

    try {
      await getStoragePermission();
      await loadSettings();
      await setLocale(locale.value);
    } catch (e, s) {
      Logger.Inst().log(
        e.toString(),
        'SettingsHandler',
        'initialize',
        LogTypes.settingsError,
        s: s,
      );
      FlashElements.showSnackbar(
        title: Text(
          loc.init.initError,
          style: const TextStyle(fontSize: 20),
        ),
        content: Text(
          e.toString(),
        ),
        sideColor: Colors.red,
        leadingIcon: Symbols.error_rounded,
        leadingIconColor: Colors.red,
      );
    }
    print('isFromStore: ${EnvironmentConfig.isFromStore}');

    // print('=-=-=-=-=-=-=-=-=-=-=-=-=');
    // print(toJSON());
    // print(jsonEncode(toJSON()));

    alice = Alice(
      quickShareAction: Platform.isWindows
          ? (call) async {
              await Clipboard.setData(
                ClipboardData(
                  text: await AliceSaveHelper.buildCallLog(call),
                ),
              );
            }
          : null,
    );

    if (Platform.isAndroid && extPathOverride.isNotEmpty) {
      unawaited(SAFFileCache.instance.populate(extPathOverride));
    }

    isInit.value = true;
    return;
  }

  Future<void> postInit(AsyncCallback externalAction) async {
    if (isPostInit.value == true) {
      return;
    }

    try {
      postInitMessage.value = loc.init.settingUpProxy;
      await initProxy();

      if (SettingsHandler.isDesktopPlatform) {
        fvp.registerWith();
      } else {
        switch (videoBackendMode) {
          case VideoBackendMode.normal:
            MediaKitVideoPlayer.registerNative();
            break;
          case VideoBackendMode.mpv:
            MediaKitVideoPlayer.registerWith();
            break;
          case VideoBackendMode.mdk:
            fvp.registerWith();
            break;
        }
      }

      StartupTimeline.mark('proxy and player');
      postInitMessage.value = loc.init.loadingDatabase;
      await loadDatabase((newStatus) {
        postInitMessage.value = 'Fixing data in the database...\nThis may take some time\n$newStatus';
      });
      await indexDatabase();
      StartupTimeline.mark('database');
      if (booruList.isEmpty) {
        postInitMessage.value = loc.init.loadingBoorus;
        await loadBoorus();
      }
      StartupTimeline.mark('sources');
      await externalAction();
    } catch (e, s) {
      postInitMessage.value = loc.errorExclamation;
      Logger.Inst().log(
        e.toString(),
        'SettingsHandler',
        'postInit',
        LogTypes.settingsError,
        s: s,
      );
      FlashElements.showSnackbar(
        title: Text(
          loc.init.initError,
          style: const TextStyle(fontSize: 20),
        ),
        content: Text(
          e.toString(),
        ),
        sideColor: Colors.red,
        leadingIcon: Symbols.error_rounded,
        leadingIconColor: Colors.red,
      );
    }

    unawaited(checkUpdate(withMessage: false));
    // r84: once after the whole database came back from a backup.
    unawaited(DownloadsCheck.offerAfterRestore());
    // r85: the link entry follows the saved switch (Settings → Links).
    unawaited(SourceLinks.applySaved());
    // r88: what this build of ONNX Runtime can run on (Run on offers only that).
    unawaited(OnnxAvailability.load());
    // r89 (review): the NPU failure counts from the last runs, before a model
    // opens (they used to load only with a Models page).
    unawaited(ModelTimings.instance.ensureLoaded());

    isPostInit.value = true;
    postInitMessage.value = '';
    return;
  }
}
