part of '../settings_handler.dart';

/// The table of every saved setting (type, default, limits, options) and its validation.
extension SettingsSchema on SettingsHandler {
  // default values and possible options map for validation
  Map<String, Map<String, dynamic>> get map => {
    // enums
    'previewMode': {
      'type': 'previewQuality',
      'default': PreviewQuality.defaultValue,
      'options': PreviewQuality.values,
    },
    'previewDisplay': {
      'type': 'previewDisplayMode',
      'default': PreviewDisplayMode.defaultValue,
      'options': PreviewDisplayMode.values,
    },
    'previewDisplayFallback': {
      'type': 'previewDisplayMode',
      'default': PreviewDisplayMode.defaultValue,
      'options': PreviewDisplayMode.values.where((e) => e != PreviewDisplayMode.staggered).toList(),
    },
    'shareAction': {
      'type': 'shareAction',
      'default': ShareAction.defaultValue,
      'options': ShareAction.values,
    },
    'videoCacheMode': {
      'type': 'videoCacheMode',
      'default': VideoCacheMode.defaultValue,
      'options': VideoCacheMode.values,
    },
    'galleryMode': {
      'type': 'imageQuality',
      'default': ImageQuality.defaultValue,
      'options': ImageQuality.values,
    },
    'snatchMode': {
      'type': 'imageQuality',
      'default': ImageQuality.defaultValue,
      'options': ImageQuality.values,
    },
    'galleryScrollDirection': {
      'type': 'scrollDirection',
      'default': ScrollDirection.defaultValue,
      'options': ScrollDirection.values,
    },
    'galleryBarPosition': {
      'type': 'verticalPosition',
      'default': VerticalPosition.defaultValue,
      'options': VerticalPosition.values,
    },
    'zoomButtonPosition': {
      'type': 'buttonPosition',
      'default': ButtonPosition.defaultValue,
      'options': ButtonPosition.values,
    },
    'changePageButtonsPosition': {
      'type': 'buttonPosition',
      'default': ButtonPosition.defaultValueDesktopOnly,
      'options': ButtonPosition.values,
    },
    'scrollGridButtonsPosition': {
      'type': 'buttonPosition',
      'default': ButtonPosition.defaultValueDesktopOnly,
      'options': ButtonPosition.values,
    },
    'videoBackendMode': {
      'type': 'videoBackendMode',
      'default': SettingsHandler.isDesktopPlatform ? VideoBackendMode.mpv : VideoBackendMode.defaultValue,
      'options': VideoBackendMode.values,
    },
    'altVideoPlayerVO': {
      'type': 'mpvVideoOutput',
      'default': MpvVideoOutput.defaultValue,
      'options': MpvVideoOutput.values,
    },
    'altVideoPlayerHWDEC': {
      'type': 'mpvHardwareDecoding',
      'default': MpvHardwareDecoding.defaultValue,
      'options': MpvHardwareDecoding.values,
    },
    'proxyType': {
      'type': 'proxyType',
      'default': ProxyType.defaultValue,
      'options': ProxyType.values,
    },

    // string
    'defTags': {
      'type': 'string',
      'default': 'rating:safe',
    },
    'defaultTabAddMode': {
      'type': 'string',
      'default': 'end',
    },
    'prefBooru': {
      'type': 'string',
      'default': '',
    },
    'extPathOverride': {
      'type': 'string',
      'default': '',
    },
    'drawerMascotPathOverride': {
      'type': 'string',
      'default': '',
    },
    'backupPath': {
      'type': 'string',
      'default': '',
    },
    'lastSyncIp': {
      'type': 'string',
      'default': '',
    },
    'lastSyncPort': {
      'type': 'string',
      'default': '',
    },
    'customUserAgent': {
      'type': 'string',
      'default': '',
    },
    'proxyAddress': {
      'type': 'string',
      'default': '',
    },
    'proxyUsername': {
      'type': 'string',
      'default': '',
    },
    'proxyPassword': {
      'type': 'string',
      'default': '',
    },

    // stringList
    'hatedTags': {
      'type': 'stringList',
      'default': <String>[],
    },
    'hiddenTags': {
      'type': 'stringList',
      'default': <String>[],
    },
    // Per-booru hidden tags: {booruName: [tag, ...]}.
    'hiddenTagsPerBooru': {
      'type': 'map',
      'default': <String, List<String>>{},
    },
    'lovedTags': {
      'type': 'stringList',
      'default': <String>[],
    },
    'markedTags': {
      'type': 'stringList',
      'default': <String>[],
    },

    // int
    'limit': {
      'type': 'int',
      'default': Constants.defaultItemLimit,
      'step': 10,
      'upperLimit': 100,
      'lowerLimit': 10,
    },
    'portraitColumns': {
      'type': 'int',
      'default': 2,
      'step': 1,
      'upperLimit': 100,
      'lowerLimit': 1,
    },
    'landscapeColumns': {
      'type': 'int',
      'default': 4,
      'step': 1,
      'upperLimit': 100,
      'lowerLimit': 1,
    },
    'preloadCount': {
      'type': 'int',
      'default': 1,
      'step': 1,
      'upperLimit': 4,
      'lowerLimit': 0,
    },
    'preloadHeight': {
      'type': 'int',
      'default': 4096 * 4,
      'step': 1024,
      'upperLimit': 2_000_000_000,
      'lowerLimit': 0,
    },
    'snatchCooldown': {
      'type': 'int',
      'default': 250,
      'step': 50,
      'upperLimit': 10000,
      'lowerLimit': 0,
    },
    'volumeButtonsScrollSpeed': {
      'type': 'int',
      'default': 200,
      'step': 10,
      'upperLimit': 1000000,
      'lowerLimit': 0,
    },
    'galleryAutoScrollTime': {
      'type': 'int',
      'default': 4000,
      'step': 100,
      'upperLimit': 100000,
      'lowerLimit': 100,
    },
    'galleryAutoScrollVideoTime': {
      'type': 'int',
      'default': 10000,
      'step': 100,
      'upperLimit': 600000,
      'lowerLimit': 100,
    },
    'cacheSize': {
      'type': 'int',
      'default': 3,
      'step': 1,
      'upperLimit': 10,
      'lowerLimit': 0,
    },
    'autoLockTimeout': {
      'type': 'int',
      'default': 120,
      'step': 10,
      'upperLimit': double.infinity,
      'lowerLimit': 0,
    },

    // double
    'mousewheelScrollSpeed': {
      'type': 'double',
      'default': 10.0,
      'upperLimit': 100.0,
      'lowerLimit': 0.1,
      'step': 0.5,
    },
    'preloadSizeLimit': {
      'type': 'double',
      'default': 0.2,
      'upperLimit': double.infinity,
      'lowerLimit': 0.0,
      'step': 0.1,
    },

    // bool
    'jsonWrite': {
      'type': 'bool',
      'default': false,
    },
    'respectManualPause': {
      'type': 'bool',
      'default': true,
    },
    'autoPlayEnabled': {
      'type': 'bool',
      'default': true,
    },
    'preloadVideos': {
      'type': 'bool',
      'default': false,
    },
    'useBetterPlayer': {
      'type': 'bool',
      'default': false,
    },
    'useMediaKitPlayer': {
      'type': 'bool',
      'default': false,
    },
    'videoEngineChoice': {
      'type': 'stringFromList',
      'default': 'off',
      'options': ['off', 'media3', 'mpvlibVulkan', 'mpvlibOpengl'],
    },
    'mediaKitMaxPlayers': {
      'type': 'int',
      'default': 4,
      'step': 1,
      'lowerLimit': 1,
      'upperLimit': 20,
    },
    'videoStartDelayMs': {
      'type': 'int',
      'default': 333,
      'step': 50,
      'lowerLimit': 0,
      'upperLimit': 5000,
    },
    'betterPlayerCacheMb': {
      'type': 'int',
      'default': 500,
      'step': 100,
      'lowerLimit': 0,
      'upperLimit': 50000,
    },
    'betterPlayerPerFileMb': {
      'type': 'int',
      'default': 100,
      'step': 50,
      'lowerLimit': 0,
      'upperLimit': 50000,
    },
    'inlineRelatedGrids': {
      'type': 'bool',
      'default': true,
    },
    'previewWindowRect': {
      'type': 'string',
      'default': '',
    },
    'enableInterestTracking': {
      'type': 'bool',
      'default': true,
    },
    'aiRecommendations': {
      'type': 'bool',
      'default': true,
    },
    'aiLearning': {
      'type': 'bool',
      'default': true,
    },
    'aiEncoder': {
      'type': 'bool',
      'default': true,
    },
    'encoderModel': {
      'type': 'string',
      'default': '',
    },
    'aiImageTagger': {
      'type': 'bool',
      'default': true,
    },
    'imageTaggerModel': {
      'type': 'string',
      'default': '',
    },
    'taggerOnReactions': {
      'type': 'bool',
      'default': false,
    },
    'aiLook': {
      'type': 'bool',
      'default': true,
    },
    'lookModel': {
      'type': 'string',
      'default': '',
    },
    'videoFrames': {
      'type': 'bool',
      'default': true,
    },
    'aiModelsOff': {
      'type': 'bool',
      'default': false,
    },
    'framesForYou': {
      'type': 'stringFromList',
      'default': 'playing',
      'options': ['playing', 'reaction', 'off'],
    },
    'pictureDecoder': {
      'type': 'stringFromList',
      'default': 'phone',
      'options': ['phone', 'phoneFast', 'dart'],
    },
    'framesOtherTabs': {
      'type': 'stringFromList',
      'default': 'playing',
      'options': ['playing', 'reaction', 'off'],
    },
    'rememberLooks': {
      'type': 'bool',
      'default': false,
    },
    'vectorSpaceMb': {
      'type': 'int',
      'default': 250,
      'lowerLimit': 10,
      'upperLimit': 100000,
    },
    'capturesPath': {
      'type': 'string',
      'default': '',
    },
    // r80: debug mode stays on across restarts until it is turned off (it
    // was never saved: every start had it off again).
    'isDebug': {
      'type': 'bool',
      'default': kDebugMode,
    },
    'useBottomInfoSheet': {
      'type': 'bool',
      'default': true,
    },
    'showViewerTutorial': {
      'type': 'bool',
      'default': true,
    },
    'translateHanimeTitles': {
      'type': 'bool',
      'default': true,
    },
    'bottomSheetSizeMultiplier': {
      'type': 'double',
      'default': 2.0,
      'upperLimit': 3.0,
      'lowerLimit': 0.5,
      'step': 0.5,
    },
    'loadingGif': {
      'type': 'bool',
      'default': false,
    },
    'thumbnailCache': {
      'type': 'bool',
      'default': true,
    },
    'mediaCache': {
      'type': 'bool',
      'default': true,
    },
    'autoHideImageBar': {
      'type': 'bool',
      'default': false,
    },
    'hideStatusBar': {
      'type': 'bool',
      'default': false,
    },
    'dbEnabled': {
      'type': 'bool',
      'default': true,
    },
    'indexesEnabled': {
      'type': 'bool',
      'default': false,
    },
    'searchHistoryEnabled': {
      'type': 'bool',
      'default': true,
    },
    'filterHated': {
      'type': 'bool',
      'default': false,
    },
    'filterMarked': {
      'type': 'bool',
      'default': false,
    },
    'filterFavourites': {
      'type': 'bool',
      'default': false,
    },
    'filterSnatched': {
      'type': 'bool',
      'default': false,
    },
    'filterAi': {
      'type': 'bool',
      'default': false,
    },
    'openSourceLinks': {
      'type': 'bool',
      'default': false,
    },
    'useVolumeButtonsForScroll': {
      'type': 'bool',
      'default': false,
    },
    'shitDevice': {
      'type': 'bool',
      'default': false,
    },
    'disableVideo': {
      'type': 'bool',
      'default': false,
    },
    'enableDrawerMascot': {
      'type': 'bool',
      'default': false,
    },
    'allowSelfSignedCerts': {
      'type': 'bool',
      'default': false,
    },
    'disableImageScaling': {
      'type': 'bool',
      'default': false,
    },
    'gifsAsThumbnails': {
      'type': 'bool',
      'default': false,
    },
    'desktopListsDrag': {
      'type': 'bool',
      'default': false,
    },
    'wakeLockEnabled': {
      'type': 'bool',
      'default': true,
    },
    'tagTypeFetchEnabled': {
      'type': 'bool',
      'default': true,
    },
    'downloadNotifications': {
      'type': 'bool',
      'default': true,
    },
    'allowRotation': {
      'type': 'bool',
      'default': false,
    },
    'enableHeroTransitions': {
      'type': 'bool',
      'default': true,
    },
    'disableCustomPageTransitions': {
      'type': 'bool',
      'default': false,
    },
    'incognitoKeyboard': {
      'type': 'bool',
      'default': false,
    },
    'appAlias': {
      'type': 'appAlias',
      'default': AppAlias.defaultValue,
      'options': AppAlias.values,
    },
    'hideNotes': {
      'type': 'bool',
      'default': false,
    },
    'startVideosMuted': {
      'type': 'bool',
      'default': false,
    },
    'snatchOnFavourite': {
      'type': 'bool',
      'default': false,
    },
    'favouriteOnSnatch': {
      'type': 'bool',
      'default': false,
    },
    'disableVibration': {
      'type': 'bool',
      'default': false,
    },
    'altVideoPlayerHwAccel': {
      'type': 'bool',
      'default': true,
    },
    'showBottomSearchbar': {
      'type': 'bool',
      'default': true,
    },
    'useTopSearchbarInput': {
      'type': 'bool',
      'default': false,
    },
    'tabPill': {
      'type': 'bool',
      'default': false,
    },
    'dimSeenPosts': {
      'type': 'bool',
      'default': false,
    },
    'fastGifPlayback': {
      'type': 'bool',
      'default': true,
    },
    'showSearchbarQuickActions': {
      'type': 'bool',
      'default': false,
    },
    'autofocusSearchbar': {
      'type': 'bool',
      'default': true,
    },
    'expandDetails': {
      'type': 'bool',
      'default': false,
    },
    'usePredictiveBack': {
      'type': 'bool',
      'default': true,
    },
    'useLockscreen': {
      'type': 'bool',
      'default': false,
    },
    'blurOnLeave': {
      'type': 'bool',
      'default': false,
    },

    // other
    'buttonOrder': {
      'type': 'stringList',
      'default': <String>[
        ...GalleryButton.values.map((b) => b.toJson()),
      ],
    },
    'disabledButtons': {
      'type': 'stringList',
      'default': <String>[],
      'options': <String>[
        ...GalleryButton.disableable.map((b) => b.toJson()),
      ],
    },
    'cacheDuration': {
      'type': 'duration',
      'default': Duration.zero,
      'options': <Map<String, dynamic>>[
        {'label': 'Never', 'value': Duration.zero},
        {'label': '30 minutes', 'value': const Duration(minutes: 30)},
        {'label': '1 hour', 'value': const Duration(hours: 1)},
        {'label': '6 hours', 'value': const Duration(hours: 6)},
        {'label': '12 hours', 'value': const Duration(hours: 12)},
        {'label': '1 day', 'value': const Duration(days: 1)},
        {'label': '2 days', 'value': const Duration(days: 2)},
        {'label': '1 week', 'value': const Duration(days: 7)},
        {'label': '1 month', 'value': const Duration(days: 30)},
      ],
    },

    // theme
    'appMode': {
      'type': 'appMode',
      'default': AppMode.defaultValue,
      'options': AppMode.values,
    },
    'handSide': {
      'type': 'handSide',
      'default': HandSide.defaultValue,
      'options': HandSide.values,
    },
    'kemonoSidebar': {
      'type': 'bool',
      'default': true,
    },
    'furAffinitySidebar': {
      'type': 'bool',
      'default': true,
    },
    'kemonoPostFullImages': {
      'type': 'bool',
      'default': false,
    },
    'theme': {
      'type': 'theme',
      'default': ThemeItem(name: 'Flow', primary: const Color(0xFFB9A0E8), accent: const Color(0xFFB9A0E8)),
      'options': <ThemeItem>[
        ThemeItem(name: 'Flow', primary: const Color(0xFFB9A0E8), accent: const Color(0xFFB9A0E8)),
        ThemeItem(name: 'Pink', primary: Colors.pink[200], accent: Colors.pink[600]),
        ThemeItem(name: 'Purple', primary: Colors.deepPurple[600], accent: Colors.deepPurple[800]),
        ThemeItem(name: 'Blue', primary: Colors.lightBlue, accent: Colors.lightBlue[600]),
        ThemeItem(name: 'Teal', primary: Colors.teal, accent: Colors.teal[600]),
        ThemeItem(name: 'Red', primary: Colors.red[700], accent: Colors.red[800]),
        ThemeItem(name: 'Green', primary: Colors.green, accent: Colors.green[700]),
        ThemeItem(name: 'Halloween', primary: const Color(0xFF0B192C), accent: const Color(0xFFEB5E28)),
        ThemeItem(name: 'Custom', primary: null, accent: null),
      ],
    },
    'themeMode': {
      'type': 'themeMode',
      'default': ThemeMode.dark,
      'options': ThemeMode.values,
    },
    'useDynamicColor': {
      'type': 'bool',
      'default': false,
    },
    'isAmoled': {
      'type': 'bool',
      'default': false,
    },
    'flowSkinApplied': {
      'type': 'bool',
      'default': false,
    },
    'fontFamily': {
      'type': 'string',
      'default': 'System',
    },
    'locale': {
      'type': 'locale',
      'default': null,
    },
    'customPrimaryColor': {
      'type': 'color',
      'default': Colors.pink[200],
    },
    'customAccentColor': {
      'type': 'color',
      'default': Colors.pink[600],
    },
  };

  dynamic validateValue(String name, dynamic value, {bool toJSON = false}) {
    final Map<String, dynamic>? settingParams = map[name];

    if (toJSON) {
      value = getByString(name);
    }

    if (value is Rx) {
      value = value.value;
    }

    if (settingParams == null) {
      if (toJSON) {
        return value.toString();
      } else {
        return value;
      }
    }

    try {
      final String type = settingParams['type'];

      // Check if this is a registered SettingsEnum type - handles all enums generically
      if (SettingsEnumRegistry.isRegistered(type)) {
        return SettingsEnumRegistry.validate(
          type,
          value,
          settingParams['default'],
          toJSON: toJSON,
        );
      }

      switch (type) {
        case 'stringFromList':
          final String validValue = List<String>.from(
            settingParams['options']!,
          ).firstWhere((el) => el == value, orElse: () => '');
          if (validValue != '') {
            return validValue;
          } else {
            return settingParams['default'];
          }

        case 'string':
          if (value is! String) {
            throw Exception('value "$value" for $name is not a String');
          } else {
            return value;
          }

        case 'int':
          final int? parse = (value is String) ? int.tryParse(value) : (value is int ? value : null);
          if (parse == null) {
            throw Exception('value "$value" of type ${value.runtimeType} for $name is not an int');
          } else if (parse < settingParams['lowerLimit'] || parse > settingParams['upperLimit']) {
            if (toJSON) {
              // force default value when not passing validation when saving
              setByString(name, settingParams['default']);
            }
            return settingParams['default'];
          } else {
            return parse;
          }

        case 'bool':
          if (value is! bool) {
            if (value is String && (value == 'true' || value == 'false')) {
              return value == 'true';
            } else {
              throw Exception('value "$value" for $name is not a bool');
            }
          } else {
            return value;
          }

        // Special types with custom handling
        case 'theme':
          if (toJSON) {
            return (value as ThemeItem).name;
          } else {
            if (value is String) {
              final ThemeItem findTheme = List<ThemeItem>.from(
                settingParams['options']!,
              ).firstWhere((el) => el.name == value, orElse: () => settingParams['default']);
              return findTheme;
            } else {
              return settingParams['default'];
            }
          }

        case 'themeMode':
          if (toJSON) {
            return (value as ThemeMode).name; // ThemeMode.dark => dark
          } else {
            if (value is String) {
              final List<ThemeMode> findMode = ThemeMode.values
                  .where((element) => element.toString() == 'ThemeMode.$value')
                  .toList();
              if (findMode.isNotEmpty) {
                // if theme mode is present
                return findMode[0];
              } else {
                // if not theme mode with given name
                return settingParams['default'];
              }
            } else {
              return settingParams['default'];
            }
          }

        case 'color':
          if (toJSON) {
            // TODO replace value with toARGB32() in the next flutter release
            // ignore: deprecated_member_use
            return (value as Color?)?.value ?? Colors.pink.value; // Color => int
          } else {
            if (value is int) {
              return Color(value);
            } else {
              return settingParams['default'];
            }
          }

        case 'duration':
          if (toJSON) {
            return (value as Duration).inSeconds; // Duration => int
          } else {
            if (value is Duration) {
              return value;
            } else if (value is int) {
              // int to Duration
              return Duration(seconds: value);
            } else {
              return settingParams['default'];
            }
          }

        case 'locale':
          if (toJSON) {
            return (value as AppLocale?)?.name;
          } else {
            if (value is String) {
              return AppLocaleExt.allowedValues.firstWhereOrNull((e) => e.name == value);
            } else {
              return settingParams['default'];
            }
          }

        case 'double':
          // A whole number in the file (e.g. 25) is still a valid double.
          return value is num ? value.toDouble() : value;

        // case 'stringList':
        default:
          return value;
      }
    } catch (e, s) {
      // return default value on exceptions
      Logger.Inst().log(
        'value validation error: $e',
        'SettingsHandler',
        'validateValue',
        null,
        s: s,
      );
      return settingParams['default'];
    }
  }
}
