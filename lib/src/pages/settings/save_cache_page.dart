import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';

import 'package:lolisnatcher/src/data/settings/image_quality.dart';
import 'package:lolisnatcher/src/data/settings/video_cache_mode.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/download_folders.dart';
import 'package:lolisnatcher/src/services/image_writer.dart';
import 'package:lolisnatcher/src/services/image_writer_isolate.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/common/downloads_check.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

class SaveCachePage extends StatefulWidget {
  const SaveCachePage({super.key});

  @override
  State<SaveCachePage> createState() => _SaveCachePageState();
}

class _SaveCachePageState extends State<SaveCachePage> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final ImageWriter imageWriter = ImageWriter();

  final TextEditingController snatchCooldownController = TextEditingController();
  final TextEditingController cacheSizeController = TextEditingController();

  late VideoCacheMode videoCacheMode;
  late String extPathOverride;
  late ImageQuality snatchMode;
  bool jsonWrite = false,
      thumbnailCache = true,
      mediaCache = false,
      downloadNotifications = true,
      snatchOnFavourite = false,
      favouriteOnSnatch = false;

  static const List<_CacheType> cacheTypes = [
    _CacheType(_CacheTypeEnum.total, null),
    // TODO ask before deleting favicons, since they cause unneeded network requests on each render if not cached
    _CacheType(_CacheTypeEnum.favicons, 'favicons'),
    _CacheType(_CacheTypeEnum.thumbnails, 'thumbnails'),
    _CacheType(_CacheTypeEnum.samples, 'samples'),
    _CacheType(_CacheTypeEnum.media, 'media'),
    _CacheType(_CacheTypeEnum.webView, 'WebView'),
  ]; // {displayed name, cache folder}
  List<Map<String, dynamic>> cacheStats = [];
  Map<String, dynamic>? cacheDurationSelected;
  late Duration cacheDuration;
  Isolate? isolate;

  @override
  void initState() {
    super.initState();

    snatchCooldownController.text = settingsHandler.snatchCooldown.toString();
    thumbnailCache = settingsHandler.thumbnailCache;
    mediaCache = settingsHandler.mediaCache;
    videoCacheMode = settingsHandler.videoCacheMode;
    extPathOverride = settingsHandler.extPathOverride;
    snatchMode = settingsHandler.snatchMode;
    jsonWrite = settingsHandler.jsonWrite;
    cacheDuration = settingsHandler.cacheDuration;
    cacheDurationSelected = settingsHandler.map['cacheDuration']!['options']!.firstWhere((dur) {
      return dur['value'].inSeconds == cacheDuration.inSeconds;
    });
    cacheSizeController.text = settingsHandler.cacheSize.toString();
    downloadNotifications = settingsHandler.downloadNotifications;
    snatchOnFavourite = settingsHandler.snatchOnFavourite;
    favouriteOnSnatch = settingsHandler.favouriteOnSnatch;

    getCacheStats(null);
  }

  @override
  void dispose() {
    snatchCooldownController.dispose();
    cacheSizeController.dispose();
    isolate?.kill(priority: Isolate.immediate);
    isolate = null;
    super.dispose();
  }

  Future<void> getCacheStats(String? folder) async {
    if (folder != null) {
      // delete selected folder stats + global
      cacheStats.removeWhere((e) => e['type'] == folder || e['type'] == '' || e['type'] == null);
    } else {
      cacheStats = [];
    }

    final cacheTypesToGet = folder == null
        ? cacheTypes
        : cacheTypes.where((e) => e.folder == folder || e.folder == null).toList();

    for (final _CacheType type in cacheTypesToGet) {
      final ReceivePort receivePort = ReceivePort();
      isolate = await Isolate.spawn(_isolateEntry, receivePort.sendPort);

      receivePort.listen((dynamic data) async {
        if (mounted) {
          if (data is SendPort) {
            data.send({
              'path': await ServiceHandler.getCacheDir(),
              'type': type.folder,
            });
          } else {
            cacheStats.add(data);
            setState(() {});
          }
        }
      });
    }
    return;
  }

  static Future<void> _isolateEntry(dynamic d) async {
    final ReceivePort receivePort = ReceivePort();
    d.send(receivePort.sendPort);

    final config = await receivePort.first;
    d.send(await ImageWriterIsolate(config['path']).getCacheStat(config['type']));
  }

  Future<void> _onPopInvoked(_, _) async {
    settingsHandler.snatchCooldown = int.parse(snatchCooldownController.text);
    settingsHandler.jsonWrite = jsonWrite;
    settingsHandler.mediaCache = mediaCache;
    settingsHandler.thumbnailCache = thumbnailCache;
    settingsHandler.videoCacheMode = videoCacheMode;
    settingsHandler.cacheDuration = cacheDuration;
    settingsHandler.cacheSize = int.parse(cacheSizeController.text);
    // r82: through DownloadFolders, so the folder left is remembered and
    // the new one's file list is read at once.
    if (extPathOverride != settingsHandler.extPathOverride) await DownloadFolders.change(extPathOverride);
    settingsHandler.snatchMode = snatchMode;
    settingsHandler.downloadNotifications = downloadNotifications;
    settingsHandler.snatchOnFavourite = snatchOnFavourite;
    settingsHandler.favouriteOnSnatch = favouriteOnSnatch;
    await settingsHandler.saveSettings(restate: false);
  }

  /// r82: Settings → Save & cache → Earlier download folders.
  List<Widget> _earlierFolders(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<String> folders = List<String>.of(DownloadFolders.earlier);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 2),
        child: Text('Earlier download folders', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Text(
          'The Downloads list and the doujin downloads also look here for files saved before you changed the folder. '
          'New downloads always go to the folder above; nothing is moved or written here.',
          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
        ),
      ),
      if (folders.isEmpty)
        Padding(
          key: const ValueKey('earlier-folders-none'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Text('None yet. A folder you change away from is added here.', style: theme.textTheme.bodySmall),
        ),
      for (final String folder in folders)
        ListTile(
          key: ValueKey('earlier-folder-$folder'),
          dense: true,
          leading: const Icon(Symbols.folder_open_rounded),
          title: Text(DownloadFolders.describe(folder)),
          trailing: IconButton(
            key: ValueKey('earlier-folder-remove-$folder'),
            tooltip: 'Stop looking here',
            icon: const Icon(Symbols.close_rounded),
            onPressed: () async {
              await DownloadFolders.removeEarlier(folder);
              if (mounted) setState(() {});
            },
          ),
        ),
      SettingsButton(
        key: const ValueKey('earlier-folder-add'),
        name: 'Add a folder you used before',
        icon: const Icon(Symbols.create_new_folder_rounded),
        action: _addEarlierFolder,
      ),
      // r84: it used to sit in a drawer panel the app no longer shows.
      SettingsButton(
        key: const ValueKey('downloads-check'),
        name: 'Check downloads against disk',
        subtitle: const Text('Finds downloads whose file is in none of these folders, and offers to forget them'),
        icon: const Icon(Symbols.fact_check_rounded),
        action: () => DownloadsCheck.run(context),
      ),
    ];
  }

  Future<void> _addEarlierFolder() async {
    if (!Platform.isAndroid) {
      FlashElements.showSnackbar(
        context: context,
        title: Text(context.loc.settings.cache.notAvailableForPlatform),
        leadingIcon: Symbols.error_rounded,
      );
      return;
    }
    final String picked = await ServiceHandler.getSAFDirectoryAccess();
    if (picked.isEmpty || !mounted) return;
    final bool added = await DownloadFolders.addEarlier(picked);
    if (!mounted) return;
    setState(() {});
    FlashElements.showSnackbar(
      context: context,
      title: Text(added ? 'Folder added' : 'Already there'),
      content: Text(
        added
            ? 'The Downloads list looks in ${DownloadFolders.describe(picked)} too. Tap the Downloads tab to load it again.'
            : 'That folder is the current download folder or already in the list.',
      ),
      leadingIcon: added ? Symbols.check_rounded : Symbols.info_rounded,
    );
  }

  void setPath(String path) {
    if (path.isNotEmpty) {
      settingsHandler.extPathOverride = path;
    }
  }

  Widget buildCacheButton(_CacheType type) {
    final Map<String, dynamic> stat = cacheStats.firstWhere(
      (stat) => stat['type'] == type.folder,
      orElse: () => {
        'type': 'loading',
        'totalSize': -1,
        'fileNum': -1,
      },
    );
    final String? folder = type.folder;
    final String label = type.type.locName;
    final String size = Tools.formatBytes(stat['totalSize']!, 2);
    final int fileCount = stat['fileNum'] ?? 0;
    final bool isEmpty = stat['fileNum'] == 0 || stat['totalSize'] == 0;
    final bool isLoading = stat['type'] == 'loading';
    final String text = isLoading
        ? context.loc.settings.cache.loading
        : (isEmpty
              ? context.loc.settings.cache.empty
              : (fileCount == 1
                    ? context.loc.settings.cache.inFileSingular(size: size)
                    : context.loc.settings.cache.inFilesPlural(size: size, count: fileCount)));

    final bool allowedToClear = folder != null && folder != 'favicons' && !isEmpty;

    return SettingsButton(
      name: '$label: $text',
      icon: isLoading ? const CircularProgressIndicator() : Icon(allowedToClear ? Symbols.delete_forever_rounded : null),
      action: () async {
        if (allowedToClear) {
          FlashElements.showSnackbar(
            context: context,
            position: FlashPosition.top,
            duration: const Duration(seconds: 2),
            title: Text(
              context.loc.settings.cache.cacheCleared,
              style: const TextStyle(fontSize: 20),
            ),
            content: Text(
              context.loc.settings.cache.clearedCacheType(type: label),
              style: const TextStyle(fontSize: 16),
            ),
            leadingIcon: Symbols.delete_forever_rounded,
            leadingIconColor: Colors.red,
            leadingIconSize: 40,
            sideColor: Colors.yellow,
          );
          await imageWriter.deleteCacheFolder(folder);
          await getCacheStats(folder);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: SettingsAppBar(
          title: context.loc.settings.cache.title,
        ),
        body: Center(
          child: ListView(
            children: [
              // r88: the page in three named parts.
              const SettingsPart(
                key: ValueKey('save-part-downloads'),
                title: 'Downloads',
                subtitle: 'How posts are saved: the quality, the pace, notifications, saving and favouriting together.',
              ),
              SettingsOptionsList<ImageQuality>(
                value: snatchMode,
                items: ImageQuality.values,
                onChanged: (ImageQuality? newValue) {
                  setState(() {
                    snatchMode = newValue ?? ImageQuality.defaultValue;
                  });
                },
                title: context.loc.settings.cache.snatchQuality,
                itemTitleBuilder: (e) => e?.locName ?? '',
              ),
              SettingsTextInput(
                controller: snatchCooldownController,
                title: context.loc.settings.cache.snatchCooldown,
                inputType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                resetText: () => settingsHandler.map['snatchCooldown']!['default']!.toString(),
                numberButtons: true,
                numberStep: 50,
                numberMin: 0,
                numberMax: double.infinity,
                validator: (String? value) {
                  final int? parse = int.tryParse(value ?? '');
                  if (value == null || value.isEmpty) {
                    return context.loc.validationErrors.required;
                  } else if (parse == null) {
                    return context.loc.settings.cache.pleaseEnterAValidTimeout;
                  } else if (parse < 10) {
                    return context.loc.settings.cache.biggerThan10;
                  } else {
                    return null;
                  }
                },
              ),
              SettingsToggle(
                value: downloadNotifications,
                onChanged: (newValue) {
                  setState(() {
                    downloadNotifications = newValue;
                  });
                },
                title: context.loc.settings.cache.showDownloadNotifications,
              ),
              SettingsToggle(
                value: snatchOnFavourite,
                onChanged: (newValue) {
                  setState(() {
                    snatchOnFavourite = newValue;
                  });
                },
                trailingIcon: const Row(
                  children: [
                    Icon(Symbols.favorite_rounded, color: Colors.red),
                    Icon(Symbols.arrow_right_alt_rounded),
                    Icon(Symbols.save_rounded),
                  ],
                ),
                title: context.loc.settings.cache.snatchItemsOnFavouriting,
              ),
              SettingsToggle(
                value: favouriteOnSnatch,
                onChanged: (newValue) {
                  setState(() {
                    favouriteOnSnatch = newValue;
                  });
                },
                trailingIcon: const Row(
                  children: [
                    Icon(Symbols.save_rounded),
                    Icon(Symbols.arrow_right_alt_rounded),
                    Icon(Symbols.favorite_rounded, color: Colors.red),
                  ],
                ),
                title: context.loc.settings.cache.favouriteItemsOnSnatching,
              ),
              SettingsToggle(
                value: (!Platform.isAndroid || extPathOverride.isNotEmpty) && jsonWrite,
                onChanged: (newValue) {
                  setState(() {
                    jsonWrite = newValue;
                  });
                },
                enabled: !Platform.isAndroid || extPathOverride.isNotEmpty,
                title: context.loc.settings.cache.writeImageDataOnSave,
                subtitle: (!Platform.isAndroid || extPathOverride.isNotEmpty)
                    ? null
                    : Text(context.loc.settings.cache.requiresCustomStorageDirectory),
              ),
              const SettingsPart(
                key: ValueKey('save-part-folders'),
                title: 'Download folders',
                subtitle: 'Where saved files go, the folders used before, and checking the list against them.',
              ),
              SettingsButton(
                name: context.loc.settings.cache.setStorageDirectory,
                subtitle: extPathOverride.isEmpty
                    ? null
                    : Text(context.loc.settings.cache.currentPath(path: extPathOverride)),
                icon: const Icon(Symbols.folder_rounded),
                action: () async {
                  //String url = await ServiceHandler.setExtDir();

                  if (Platform.isAndroid) {
                    final String newPath = await ServiceHandler.setExtDir();
                    // r82: a cancelled picker keeps the folder (it used to
                    // reset it to the default); a new one is applied at once.
                    if (newPath.isEmpty) return;
                    await DownloadFolders.change(newPath);
                    extPathOverride = newPath;
                    if (mounted) setState(() {});
                    // TODO Store uri in settings and make another button so can set seetings dir and pictures dir
                  } else {
                    // TODO need to update dir picker to work on desktop
                    // String? value;
                    // if(settingsHandler.appMode.value.isDesktop) {
                    //   value = await showDialog(
                    //     context: context,
                    //     builder: (BuildContext context) {
                    //       return Dialog(
                    //         child: SizedBox(
                    //           width: 500,
                    //           child: DirPicker(path),
                    //         ),
                    //       );
                    //     },
                    //   );
                    // } else {
                    // TODO remove this Get
                    //   value = await Get.to(() => DirPicker(path))!;
                    // }
                    // setPath(value ?? "");

                    FlashElements.showSnackbar(
                      context: context,
                      title: Text(
                        context.loc.settings.cache.errorExclamation,
                        style: const TextStyle(fontSize: 20),
                      ),
                      content: Text(
                        context.loc.settings.cache.notAvailableForPlatform,
                        style: const TextStyle(fontSize: 16),
                      ),
                      leadingIcon: Symbols.error_rounded,
                      leadingIconColor: Colors.red,
                      sideColor: Colors.red,
                    );
                  }
                },
              ),
              if (extPathOverride.isNotEmpty)
                SettingsButton(
                  name: context.loc.settings.cache.resetStorageDirectory,
                  icon: const Icon(Symbols.refresh_rounded),
                  action: () async {
                    await DownloadFolders.change('');
                    if (!mounted) return;
                    setState(() {
                      extPathOverride = '';
                    });
                  },
                ),
              // r82: the folders used before, still looked in.
              ..._earlierFolders(context),
              const SettingsPart(
                key: ValueKey('save-part-cache'),
                title: 'Cache',
                subtitle: 'Copies of previews and media kept on the phone so posts open faster next time; nothing here is a download.',
              ),
              SettingsToggle(
                value: thumbnailCache,
                onChanged: (newValue) {
                  setState(() {
                    thumbnailCache = newValue;
                  });
                },
                title: context.loc.settings.cache.cachePreviews,
              ),
              SettingsToggle(
                value: mediaCache,
                onChanged: (newValue) {
                  setState(() {
                    mediaCache = newValue;
                  });
                },
                title: context.loc.settings.cache.cacheMedia,
              ),
              SettingsOptionsList<VideoCacheMode>(
                value: videoCacheMode,
                items: VideoCacheMode.values,
                onChanged: (VideoCacheMode? newValue) {
                  setState(() {
                    videoCacheMode = newValue ?? VideoCacheMode.defaultValue;
                  });
                },
                title: context.loc.settings.cache.videoCacheMode,
                itemTitleBuilder: (e) => e?.locName ?? '',
                trailingIcon: IconButton(
                  icon: const Icon(Symbols.help_rounded),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) {
                        return SettingsDialog(
                          title: Text(context.loc.settings.cache.videoCacheModesTitle),
                          contentItems: [
                            Text(context.loc.settings.cache.videoCacheModeStream),
                            Text(context.loc.settings.cache.videoCacheModeCache),
                            Text(context.loc.settings.cache.videoCacheModeStreamCache),
                            const Text(''),
                            Text(context.loc.settings.cache.videoCacheNoteEnable),
                            const Text(''),
                            if (SettingsHandler.isDesktopPlatform)
                              Text(context.loc.settings.cache.videoCacheWarningDesktop),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              SettingsDropdown(
                value: (cacheDurationSelected?['label'] ?? '') as String,
                items: List<String>.from(
                  settingsHandler.map['cacheDuration']!['options'].map((dur) {
                    return dur['label'];
                  }),
                ),
                onChanged: (String? newValue) {
                  setState(() {
                    cacheDurationSelected = settingsHandler.map['cacheDuration']!['options'].firstWhere((dur) {
                      return dur['label'] == newValue;
                    });
                    cacheDuration = cacheDurationSelected!['value'];
                  });
                },
                title: context.loc.settings.cache.deleteCacheAfter,
              ),
              SettingsTextInput(
                controller: cacheSizeController,
                title: context.loc.settings.cache.cacheSizeLimit,
                hintText: context.loc.settings.cache.maximumTotalCacheSize,
                inputType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                resetText: () => settingsHandler.map['cacheSize']!['default']!.toString(),
                numberButtons: true,
                numberStep: 1,
                numberMin: 0,
                numberMax: double.infinity,
              ),
              const SettingsButton(name: '', enabled: false),
              SettingsButton(name: context.loc.settings.cache.cacheStats),
              ...cacheTypes.map(buildCacheButton),
              SettingsButton(
                name: context.loc.settings.cache.clearAllCache,
                icon: Icon(
                  Symbols.delete_forever_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
                action: () async {
                  FlashElements.showSnackbar(
                    context: context,
                    position: FlashPosition.top,
                    title: Text(
                      context.loc.settings.cache.cacheCleared,
                      style: const TextStyle(fontSize: 20),
                    ),
                    content: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.loc.settings.cache.clearedCacheCompletely,
                          style: const TextStyle(fontSize: 16),
                        ),
                        Text(
                          context.loc.settings.cache.appRestartRequired,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                    leadingIcon: Symbols.delete_forever_rounded,
                    leadingIconColor: Colors.red,
                    leadingIconSize: 40,
                    sideColor: Colors.yellow,
                  );
                  await imageWriter.deleteCacheFolder('');
                  // await serviceHandler.emptyCache();
                  await getCacheStats(null);
                },
                drawBottomBorder: false,
              ),
              const SettingsButton(name: '', enabled: false),
            ],
          ),
        ),
      ),
    );
  }
}

enum _CacheTypeEnum {
  total,
  favicons,
  thumbnails,
  samples,
  media,
  webView,
  ;

  String get locName {
    switch (this) {
      case total:
        return loc.settings.cache.cacheTypeTotal;
      case favicons:
        return loc.settings.cache.cacheTypeFavicons;
      case thumbnails:
        return loc.settings.cache.cacheTypeThumbnails;
      case samples:
        return loc.settings.cache.cacheTypeSamples;
      case media:
        return loc.settings.cache.cacheTypeMedia;
      case webView:
        return loc.settings.cache.cacheTypeWebView;
    }
  }
}

class _CacheType {
  const _CacheType(
    this.type,
    this.folder,
  );

  final _CacheTypeEnum type;
  final String? folder;
}
