part of '../settings_handler.dart';

/// settings.json: reading, writing, the by-name accessors used by restore and LoliSync.
extension SettingsStorage on SettingsHandler {
  Future<bool> loadSettings() async {
    if (path == '') {
      await setConfigDir();
    }
    if (cachePath == '') {
      cachePath = await ServiceHandler.getCacheDir();
    }

    if (await checkForSettings()) {
      await loadSettingsJson();
    } else {
      // A fresh install already starts on the Flow defaults: mark the one-time
      // migration done, or the next start would undo this session's theme.
      flowSkinApplied.value = true;
      await saveSettings(restate: true);
    }
    return true;
  }

  Future<bool> checkForSettings() {
    final File settingsFile = File('${path}settings.json');
    return settingsFile.exists();
  }

  Future<void> loadSettingsJson() async {
    final File settingsFile = File('${path}settings.json');
    final String settings = await settingsFile.readAsString();
    // print('loadJSON $settings');
    await loadFromJSON(settings, true);
    // If loading just triggered the one-time Flow skin migration (startup OR
    // a restored pre-redesign backup), persist immediately so the migrated
    // state hits disk even if the app is killed before the next save.
    if (_flowMigrationPending) {
      _flowMigrationPending = false;
      await saveSettings(restate: false);
    }
    await _writeMpvlibVariant();
    return;
  }

  Future<void> _writeMpvlibVariant() {
    return ServiceHandler.setMpvlibVariant(mpvlibVariantFileText(videoEngineChoiceFromString(videoEngineChoice)));
  }

  dynamic getByString(String varName) {
    switch (varName) {
      case 'defTags':
        return defTags;
      case 'previewMode':
        return previewMode;
      case 'videoCacheMode':
        return videoCacheMode;
      case 'previewDisplay':
        return previewDisplay;
      case 'previewDisplayFallback':
        return previewDisplayFallback;
      case 'galleryMode':
        return galleryMode;
      case 'snatchMode':
        return snatchMode;
      case 'shareAction':
        return shareAction;
      case 'limit':
        return itemLimit;
      case 'portraitColumns':
        return portraitColumns;
      case 'landscapeColumns':
        return landscapeColumns;
      case 'preloadCount':
        return preloadCount;
      case 'preloadHeight':
        return preloadHeight;
      case 'snatchCooldown':
        return snatchCooldown;
      case 'galleryBarPosition':
        return galleryBarPosition;
      case 'galleryScrollDirection':
        return galleryScrollDirection;
      case 'buttonOrder':
        return buttonOrder;
      case 'disabledButtons':
        return disabledButtons;
      case 'hatedTags':
      case 'hiddenTags':
        return hiddenTags;
      case 'lovedTags':
      case 'markedTags':
        return markedTags;
      case 'autoPlayEnabled':
        return autoPlayEnabled;
      case 'respectManualPause':
        return respectManualPause;
      case 'preloadVideos':
        return preloadVideos;
      case 'useBetterPlayer':
        return useBetterPlayer;
      case 'useMediaKitPlayer':
        return useMediaKitPlayer;
      case 'videoEngineChoice':
        return videoEngineChoice;
      case 'mediaKitMaxPlayers':
        return mediaKitMaxPlayers;
      case 'videoStartDelayMs':
        return videoStartDelayMs;
      case 'betterPlayerCacheMb':
        return betterPlayerCacheMb;
      case 'betterPlayerPerFileMb':
        return betterPlayerPerFileMb;
      case 'inlineRelatedGrids':
        return inlineRelatedGrids;
      case 'previewWindowRect':
        return previewWindowRect;
      case 'enableInterestTracking':
        return enableInterestTracking;
      case 'aiRecommendations':
        return aiRecommendations;
      case 'aiLearning':
        return aiLearning;
      case 'aiEncoder':
        return aiEncoder;
      case 'encoderModel':
        return encoderModel;
      case 'aiImageTagger':
        return aiImageTagger;
      case 'imageTaggerModel':
        return imageTaggerModel;
      case 'taggerOnReactions':
        return taggerOnReactions;
      case 'aiLook':
        return aiLook;
      case 'lookModel':
        return lookModel;
      case 'videoFrames':
        return videoFrames;
      case 'aiModelsOff':
        return aiModelsOff;
      case 'framesForYou':
        return framesForYou.name;
      case 'pictureDecoder':
        return pictureDecoder.name;
      case 'framesOtherTabs':
        return framesOtherTabs.name;
      case 'rememberLooks':
        return rememberLooks;
      case 'vectorSpaceMb':
        return vectorSpaceMb;
      case 'capturesPath':
        return capturesPath;
      case 'isDebug':
        return isDebug.value;
      case 'useBottomInfoSheet':
        return useBottomInfoSheet;
      case 'showViewerTutorial':
        return showViewerTutorial;
      case 'translateHanimeTitles':
        return translateHanimeTitles;
      case 'bottomSheetSizeMultiplier':
        return bottomSheetSizeMultiplier;
      case 'defaultTabAddMode':
        return defaultTabAddMode;
      case 'loadingGif':
        return loadingGif;
      case 'thumbnailCache':
        return thumbnailCache;
      case 'mediaCache':
        return mediaCache;
      case 'autoHideImageBar':
        return autoHideImageBar;
      case 'hideStatusBar':
        return hideStatusBar;
      case 'dbEnabled':
        return dbEnabled;
      case 'indexesEnabled':
        return indexesEnabled;
      case 'searchHistoryEnabled':
        return searchHistoryEnabled;
      case 'filterHated':
        return filterHated;
      case 'filterMarked':
        return filterMarked;
      case 'filterFavourites':
        return filterFavourites;
      case 'filterSnatched':
        return filterSnatched;
      case 'filterAi':
        return filterAi;
      case 'openSourceLinks':
        return openSourceLinks;
      case 'useVolumeButtonsForScroll':
        return useVolumeButtonsForScroll;
      case 'volumeButtonsScrollSpeed':
        return volumeButtonsScrollSpeed;
      case 'mousewheelScrollSpeed':
        return mousewheelScrollSpeed;
      case 'preloadSizeLimit':
        return preloadSizeLimit;
      case 'disableVideo':
        return disableVideo;
      case 'shitDevice':
        return shitDevice;
      case 'galleryAutoScrollTime':
        return galleryAutoScrollTime;
      case 'galleryAutoScrollVideoTime':
        return galleryAutoScrollVideoTime;
      case 'jsonWrite':
        return jsonWrite;
      case 'zoomButtonPosition':
        return zoomButtonPosition;
      case 'changePageButtonsPosition':
        return changePageButtonsPosition;
      case 'scrollGridButtonsPosition':
        return scrollGridButtonsPosition;
      case 'disableImageScaling':
        return disableImageScaling;
      case 'gifsAsThumbnails':
        return gifsAsThumbnails;
      case 'desktopListsDrag':
        return desktopListsDrag;
      case 'cacheDuration':
        return cacheDuration;
      case 'cacheSize':
        return cacheSize;
      case 'autoLockTimeout':
        return autoLockTimeout;
      case 'allowSelfSignedCerts':
        return allowSelfSignedCerts;
      case 'showBottomSearchbar':
        return showBottomSearchbar;
      case 'useTopSearchbarInput':
        return useTopSearchbarInput;
      case 'tabPill':
        return tabPill;
      case 'dimSeenPosts':
        return dimSeenPosts;
      case 'fastGifPlayback':
        return fastGifPlayback;
      case 'showSearchbarQuickActions':
        return showSearchbarQuickActions;
      case 'autofocusSearchbar':
        return autofocusSearchbar;
      case 'expandDetails':
        return expandDetails;
      case 'usePredictiveBack':
        return usePredictiveBack;
      case 'useLockscreen':
        return useLockscreen;
      case 'blurOnLeave':
        return blurOnLeave;

      case 'prefBooru':
        return prefBooru;
      case 'extPathOverride':
        return extPathOverride;
      case 'drawerMascotPathOverride':
        return drawerMascotPathOverride;
      case 'backupPath':
        return backupPath;
      case 'enableDrawerMascot':
        return enableDrawerMascot;
      case 'lastSyncIp':
        return lastSyncIp;
      case 'lastSyncPort':
        return lastSyncPort;
      case 'customUserAgent':
        return customUserAgent;
      case 'proxyType':
        return proxyType;
      case 'proxyAddress':
        return proxyAddress;
      case 'proxyUsername':
        return proxyUsername;
      case 'proxyPassword':
        return proxyPassword;
      case 'wakeLockEnabled':
        return wakeLockEnabled;
      case 'tagTypeFetchEnabled':
        return tagTypeFetchEnabled;
      case 'downloadNotifications':
        return downloadNotifications;
      case 'allowRotation':
        return allowRotation;
      case 'enableHeroTransitions':
        return enableHeroTransitions;
      case 'disableCustomPageTransitions':
        return disableCustomPageTransitions;
      case 'incognitoKeyboard':
        return incognitoKeyboard;
      case 'appAlias':
        return appAlias;
      case 'hideNotes':
        return hideNotes;
      case 'startVideosMuted':
        return startVideosMuted;
      case 'snatchOnFavourite':
        return snatchOnFavourite;
      case 'favouriteOnSnatch':
        return favouriteOnSnatch;
      case 'disableVibration':
        return disableVibration;
      case 'videoBackendMode':
        return videoBackendMode;
      case 'altVideoPlayerHwAccel':
        return altVideoPlayerHwAccel;
      case 'altVideoPlayerVO':
        return altVideoPlayerVO;
      case 'altVideoPlayerHWDEC':
        return altVideoPlayerHWDEC;
      // theme stuff
      case 'appMode':
        return appMode;
      case 'handSide':
        return handSide;
      case 'kemonoSidebar':
        return kemonoSidebar.value;
      case 'furAffinitySidebar':
        return furAffinitySidebar.value;
      case 'kemonoPostFullImages':
        return kemonoPostFullImages.value;
      case 'theme':
        return theme;
      case 'themeMode':
        return themeMode;
      case 'useDynamicColor':
        return useDynamicColor;
      case 'isAmoled':
        return isAmoled;
      case 'flowSkinApplied':
        return flowSkinApplied;
      case 'fontFamily':
        return fontFamily;
      case 'customPrimaryColor':
        return customPrimaryColor;
      case 'customAccentColor':
        return customAccentColor;
      case 'locale':
        return locale;
      default:
        return null;
    }
  }

  dynamic setByString(String varName, dynamic value) {
    final dynamic validatedValue = validateValue(varName, value);
    //Could this just be replaced with getByString(varName) = validatedValue?
    switch (varName) {
      case 'defTags':
        defTags = validatedValue;
        break;
      case 'previewMode':
        previewMode = validatedValue;
        break;
      case 'videoCacheMode':
        videoCacheMode = validatedValue;
        break;
      case 'previewDisplay':
        previewDisplay = validatedValue;
        break;
      case 'previewDisplayFallback':
        previewDisplayFallback = validatedValue;
        break;
      case 'galleryMode':
        galleryMode = validatedValue;
        break;
      case 'snatchMode':
        snatchMode = validatedValue;
        break;
      case 'shareAction':
        shareAction = validatedValue;
        break;
      case 'limit':
        itemLimit = validatedValue;
        break;
      case 'portraitColumns':
        portraitColumns = validatedValue;
        break;
      case 'landscapeColumns':
        landscapeColumns = validatedValue;
        break;
      case 'preloadCount':
        preloadCount = validatedValue;
        break;
      case 'preloadHeight':
        preloadHeight = validatedValue;
        break;
      case 'snatchCooldown':
        snatchCooldown = validatedValue;
        break;
      case 'galleryBarPosition':
        galleryBarPosition = validatedValue;
        break;
      case 'galleryScrollDirection':
        galleryScrollDirection = validatedValue;
        break;

      case 'buttonOrder':
        buttonOrder = validatedValue;
        break;
      case 'disabledButtons':
        disabledButtons = validatedValue;
        break;
      // case 'hatedTags':
      //   hatedTags = validatedValue;
      //   break;
      // case 'lovedTags':
      //   lovedTags = validatedValue;
      //   break;
      case 'autoPlayEnabled':
        autoPlayEnabled = validatedValue;
        break;
      case 'respectManualPause':
        respectManualPause = validatedValue;
        break;
      case 'preloadVideos':
        preloadVideos = validatedValue;
        break;
      case 'useBetterPlayer':
        useBetterPlayer = validatedValue;
        break;
      case 'useMediaKitPlayer':
        useMediaKitPlayer = validatedValue;
        break;
      case 'videoEngineChoice':
        videoEngineChoice = validatedValue;
        break;
      case 'mediaKitMaxPlayers':
        mediaKitMaxPlayers = (validatedValue as int).clamp(1, 20);
        break;
      case 'videoStartDelayMs':
        videoStartDelayMs = (validatedValue as int).clamp(0, 5000);
        break;
      case 'betterPlayerCacheMb':
        betterPlayerCacheMb = (validatedValue as int).clamp(0, 50000);
        break;
      case 'betterPlayerPerFileMb':
        betterPlayerPerFileMb = (validatedValue as int).clamp(0, 50000);
        break;
      case 'inlineRelatedGrids':
        inlineRelatedGrids = validatedValue;
        break;
      case 'previewWindowRect':
        previewWindowRect = validatedValue;
        break;
      case 'enableInterestTracking':
        enableInterestTracking = validatedValue;
        break;
      case 'aiRecommendations':
        aiRecommendations = validatedValue;
        break;
      case 'aiLearning':
        aiLearning = validatedValue;
        break;
      case 'aiEncoder':
        aiEncoder = validatedValue;
        break;
      case 'encoderModel':
        encoderModel = validatedValue;
        break;
      case 'aiImageTagger':
        aiImageTagger = validatedValue;
        break;
      case 'imageTaggerModel':
        imageTaggerModel = validatedValue;
        break;
      case 'taggerOnReactions':
        taggerOnReactions = validatedValue;
        break;
      case 'aiLook':
        aiLook = validatedValue;
        break;
      case 'lookModel':
        lookModel = validatedValue;
        break;
      case 'videoFrames':
        videoFrames = validatedValue;
        break;
      case 'aiModelsOff':
        aiModelsOff = validatedValue;
        break;
      case 'pictureDecoder':
        pictureDecoder = PictureDecoder.parse(validatedValue);
        break;
      case 'framesForYou':
        framesForYou = FrameMode.parse(validatedValue);
        break;
      case 'framesOtherTabs':
        framesOtherTabs = FrameMode.parse(validatedValue);
        break;
      case 'rememberLooks':
        rememberLooks = validatedValue;
        break;
      case 'vectorSpaceMb':
        vectorSpaceMb = validatedValue;
        break;
      case 'capturesPath':
        capturesPath = validatedValue;
        break;
      case 'isDebug':
        isDebug.value = validatedValue;
        break;
      case 'useBottomInfoSheet':
        useBottomInfoSheet = validatedValue;
        break;
      case 'showViewerTutorial':
        showViewerTutorial = validatedValue;
        break;
      case 'translateHanimeTitles':
        translateHanimeTitles = validatedValue;
        break;
      case 'bottomSheetSizeMultiplier':
        bottomSheetSizeMultiplier = (validatedValue as num).toDouble().clamp(0.5, 3.0);
        break;
      case 'defaultTabAddMode':
        defaultTabAddMode = (validatedValue == 'next') ? 'next' : 'end';
        break;
      case 'loadingGif':
        loadingGif = validatedValue;
        break;
      case 'thumbnailCache':
        thumbnailCache = validatedValue;
        break;
      case 'mediaCache':
        mediaCache = validatedValue;
        break;
      case 'autoHideImageBar':
        autoHideImageBar = validatedValue;
        break;
      case 'hideStatusBar':
        hideStatusBar = validatedValue;
        break;
      case 'dbEnabled':
        dbEnabled = validatedValue;
        break;
      case 'indexesEnabled':
        indexesEnabled = validatedValue;
        break;
      case 'searchHistoryEnabled':
        searchHistoryEnabled = validatedValue;
        break;
      case 'filterHated':
        filterHated = validatedValue;
        break;
      case 'filterMarked':
        filterMarked = validatedValue;
        break;
      case 'filterFavourites':
        filterFavourites = validatedValue;
        break;
      case 'filterSnatched':
        filterSnatched = validatedValue;
        break;
      case 'filterAi':
        filterAi = validatedValue;
        break;
      case 'openSourceLinks':
        openSourceLinks = validatedValue;
        break;
      case 'useVolumeButtonsForScroll':
        useVolumeButtonsForScroll = validatedValue;
        break;
      case 'volumeButtonsScrollSpeed':
        volumeButtonsScrollSpeed = validatedValue;
        break;
      case 'mousewheelScrollSpeed':
        mousewheelScrollSpeed = validatedValue;
        break;
      case 'preloadSizeLimit':
        preloadSizeLimit = validatedValue;
        break;
      case 'disableVideo':
        disableVideo = validatedValue;
        break;
      case 'shitDevice':
        shitDevice = validatedValue;
        break;
      case 'galleryAutoScrollVideoTime':
        galleryAutoScrollVideoTime = validatedValue;
        break;
      case 'galleryAutoScrollTime':
        galleryAutoScrollTime = validatedValue;
        break;
      case 'jsonWrite':
        jsonWrite = validatedValue;
        break;
      case 'zoomButtonPosition':
        zoomButtonPosition = validatedValue;
        break;
      case 'changePageButtonsPosition':
        changePageButtonsPosition = validatedValue;
        break;
      case 'scrollGridButtonsPosition':
        scrollGridButtonsPosition = validatedValue;
        break;
      case 'disableImageScaling':
        disableImageScaling = validatedValue;
        break;
      case 'gifsAsThumbnails':
        gifsAsThumbnails = validatedValue;
        break;
      case 'desktopListsDrag':
        desktopListsDrag = validatedValue;
        break;
      case 'cacheDuration':
        cacheDuration = validatedValue;
        break;
      case 'cacheSize':
        cacheSize = validatedValue;
        break;
      case 'autoLockTimeout':
        autoLockTimeout = validatedValue;
        break;
      case 'prefBooru':
        prefBooru = validatedValue;
        break;
      case 'extPathOverride':
        extPathOverride = validatedValue;
        SAFFileCache.instance.invalidate();
        break;
      case 'backupPath':
        backupPath = validatedValue;
        break;
      case 'lastSyncIp':
        lastSyncIp = validatedValue;
        break;
      case 'lastSyncPort':
        lastSyncPort = validatedValue;
        break;
      case 'customUserAgent':
        customUserAgent = validatedValue;
        break;
      case 'proxyType':
        proxyType = validatedValue;
        break;
      case 'proxyAddress':
        proxyAddress = validatedValue;
        break;
      case 'proxyUsername':
        proxyUsername = validatedValue;
        break;
      case 'proxyPassword':
        proxyPassword = validatedValue;
        break;
      case 'allowSelfSignedCerts':
        allowSelfSignedCerts = validatedValue;
        break;
      case 'wakeLockEnabled':
        wakeLockEnabled = validatedValue;
        break;
      case 'tagTypeFetchEnabled':
        tagTypeFetchEnabled = validatedValue;
        break;
      case 'downloadNotifications':
        downloadNotifications = validatedValue;
        break;
      case 'allowRotation':
        allowRotation = validatedValue;
        break;
      case 'enableHeroTransitions':
        enableHeroTransitions = validatedValue;
        break;
      case 'disableCustomPageTransitions':
        disableCustomPageTransitions = validatedValue;
        break;
      case 'incognitoKeyboard':
        incognitoKeyboard = validatedValue;
        break;
      case 'appAlias':
        appAlias = validatedValue;
        break;
      case 'hideNotes':
        hideNotes = validatedValue;
        break;
      case 'startVideosMuted':
        startVideosMuted = validatedValue;
        break;
      case 'snatchOnFavourite':
        snatchOnFavourite = validatedValue;
        break;
      case 'favouriteOnSnatch':
        favouriteOnSnatch = validatedValue;
        break;
      case 'disableVibration':
        disableVibration = validatedValue;
        break;
      case 'videoBackendMode':
        videoBackendMode = validatedValue;
        break;
      case 'altVideoPlayerHwAccel':
        altVideoPlayerHwAccel = validatedValue;
        break;
      case 'altVideoPlayerVO':
        altVideoPlayerVO = validatedValue;
        break;
      case 'altVideoPlayerHWDEC':
        altVideoPlayerHWDEC = validatedValue;
        break;
      case 'showBottomSearchbar':
        showBottomSearchbar = validatedValue;
        break;
      case 'useTopSearchbarInput':
        useTopSearchbarInput = validatedValue;
        break;
      case 'tabPill':
        tabPill = validatedValue;
        break;
      case 'dimSeenPosts':
        dimSeenPosts = validatedValue;
        break;
      case 'fastGifPlayback':
        fastGifPlayback = validatedValue;
        break;
      case 'showSearchbarQuickActions':
        showSearchbarQuickActions = validatedValue;
        break;
      case 'autofocusSearchbar':
        autofocusSearchbar = validatedValue;
        break;
      case 'expandDetails':
        expandDetails = validatedValue;
        break;
      case 'usePredictiveBack':
        usePredictiveBack = validatedValue;
        break;
      case 'useLockscreen':
        useLockscreen.value = validatedValue;
        break;
      case 'blurOnLeave':
        blurOnLeave.value = validatedValue;
        break;

      // theme stuff
      case 'appMode':
        appMode.value = validatedValue;
        break;
      case 'handSide':
        handSide.value = validatedValue;
        break;
      case 'kemonoSidebar':
        kemonoSidebar.value = validatedValue;
        break;
      case 'furAffinitySidebar':
        furAffinitySidebar.value = validatedValue;
        break;
      case 'kemonoPostFullImages':
        kemonoPostFullImages.value = validatedValue;
        break;
      case 'theme':
        theme.value = validatedValue;
        break;
      case 'themeMode':
        themeMode.value = validatedValue;
        break;
      case 'useDynamicColor':
        useDynamicColor.value = validatedValue;
        break;
      case 'isAmoled':
        isAmoled.value = validatedValue;
        break;
      case 'flowSkinApplied':
        flowSkinApplied.value = validatedValue;
        break;
      case 'fontFamily':
        fontFamily.value = validatedValue;
        break;
      case 'customPrimaryColor':
        customPrimaryColor.value = validatedValue;
        break;
      case 'customAccentColor':
        customAccentColor.value = validatedValue;
        break;
      case 'drawerMascotPathOverride':
        drawerMascotPathOverride = validatedValue;
        break;
      case 'enableDrawerMascot':
        enableDrawerMascot = validatedValue;
        break;
      case 'locale':
        locale.value = validatedValue;
        break;
      default:
        break;
    }
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {};

    // Auto-generate JSON from map keys
    for (final key in map.keys) {
      // Special handling for tags (need to be cleaned)
      if (key == 'hatedTags' || key == 'lovedTags') {
        // do nothing, legacy key
      } else if (key == 'hiddenTags') {
        json[key] = cleanTagsList(hiddenTags.map(Tag.new).toList());
      } else if (key == 'hiddenTagsPerBooru') {
        // Serialize the per-booru map; drop empty entries to keep JSON tight.
        final Map<String, List<String>> out = {};
        hiddenTagsPerBooru.forEach((boorus, tags) {
          if (tags.isNotEmpty) out[boorus] = tags.toList();
        });
        json[key] = out;
        // Modular UI (r41) is written next to it: not a declared setting, so
        // the generic loop never validates it as one.
        json['modularUi'] = Map<String, bool>.from(modularUi);
      } else if (key == 'markedTags') {
        json[key] = cleanTagsList(markedTags.map(Tag.new).toList());
      } else {
        json[key] = validateValue(key, null, toJSON: true);
      }
    }

    // r80: Settings → Models, written next to the declared settings.
    json['modelTasks'] = Map<String, bool>.from(modelTasks);
    json['modelThreads'] = Map<String, int>.from(modelThreads);
    json['modelRunOn'] = Map<String, String>.from(modelRunOn);
    json['earlierDownloadFolders'] = List<String>.from(earlierDownloadFolders);

    // Add version info
    json['version'] = Constants.updateInfo.versionName;
    json['build'] = Constants.updateInfo.buildNumber;

    return json;
  }

  Future<bool> loadFromJSON(String jsonString, bool setMissingKeys) async {
    Map<String, dynamic> json = {};
    try {
      json = jsonDecode(jsonString);
    } catch (e, s) {
      Logger.Inst().log(
        'Failed to parse settings config $e',
        'SettingsHandler',
        'loadFromJSON',
        LogTypes.exception,
        s: s,
      );
    }

    // TODO add error handling for invalid values
    // (don't allow user to exit the page until the value is correct? or just set to default (current behaviour)? mix of both?)

    try {
      dynamic tempBtnOrder = json['buttonOrder'];
      if (tempBtnOrder is List) {
        // print('btnorder is a list');
      } else if (tempBtnOrder is String) {
        // print('btnorder is a string');
        tempBtnOrder = tempBtnOrder.split(',');
      } else {
        // print('btnorder is a ${tempBtnOrder.runtimeType} type');
        tempBtnOrder = [];
      }
      final List<GalleryButton> btnOrder = List<GalleryButton?>.from(
        tempBtnOrder.map((b) => b is String ? GalleryButton.fromString(b) : null),
      ).where((b) => b != null).toList().cast<GalleryButton>();
      btnOrder.addAll(
        GalleryButton.values.where(
          (b) => !btnOrder.contains(b),
        ),
      ); // add all buttons that are not present in the parsed list (future proofing, in case we add more buttons later)
      buttonOrder = btnOrder;
    } catch (e, s) {
      Logger.Inst().log(
        'Failed to parse button order list $e',
        'SettingsHandler',
        'loadFromJSON',
        LogTypes.exception,
        s: s,
      );
    }

    try {
      dynamic tempDisabledButtons = json['disabledButtons'];
      if (tempDisabledButtons is List) {
        tempDisabledButtons = [
          ...tempDisabledButtons
              .map((b) => b is String ? GalleryButton.fromString(b) : null)
              .where((b) => b != null)
              .toList()
              .cast<GalleryButton>(),
        ];

        final disableableButtons = [...GalleryButton.disableable];
        // Over a copy: removing from the list being iterated threw.
        for (final button in [...tempDisabledButtons]) {
          if (disableableButtons.any((e) => e == button)) {
            // do nothing
          } else {
            // remove unknown and not allowed to remove buttons
            tempDisabledButtons.remove(button);
          }
        }

        disabledButtons = [...tempDisabledButtons];
      } else {
        disabledButtons = [];
      }
    } catch (e, s) {
      Logger.Inst().log(
        'Failed to parse button disabled list $e',
        'SettingsHandler',
        'loadFromJSON',
        LogTypes.exception,
        s: s,
      );
    }

    try {
      dynamic tempHiddenTags = json['hiddenTags'] ?? json['hatedTags'];
      if (tempHiddenTags is List) {
        // print('hiddenTags is a list');
      } else if (tempHiddenTags is String) {
        // print('hiddenTags is a string');
        tempHiddenTags = tempHiddenTags.split(',');
      } else {
        // print('hiddenTags is a ${tempHiddenTags.runtimeType} type');
        tempHiddenTags = [];
      }
      hiddenTags.clear();
      final List<String> hideTags = List<String>.from(tempHiddenTags);
      for (int i = 0; i < hideTags.length; i++) {
        hiddenTags.add(hideTags.elementAt(i));
      }
      invalidateBlacklistCache();
    } catch (e, s) {
      Logger.Inst().log(
        'Failed to parse hidden tags $e',
        'SettingsHandler',
        'loadFromJSON',
        LogTypes.exception,
        s: s,
      );
    }

    modularUi
      ..clear()
      ..addAll(ModularUi.parse(json['modularUi']));
    modelTasks
      ..clear()
      ..addAll(ModelTasks.parse(json['modelTasks']));
    // These three belong to this phone (deviceSpecificSettings): a LoliSync
    // payload (setMissingKeys false) leaves them out and must not clear them.
    if (setMissingKeys || json.containsKey('modelThreads')) {
      modelThreads
        ..clear()
        ..addAll(ModelTasks.parseThreads(json['modelThreads']));
    }
    if (setMissingKeys || json.containsKey('modelRunOn')) {
      modelRunOn
        ..clear()
        ..addAll(ModelTasks.parseRunOn(json['modelRunOn']));
    }
    if (setMissingKeys || json.containsKey('earlierDownloadFolders')) {
      earlierDownloadFolders.clear();
      final dynamic earlierFolders = json['earlierDownloadFolders'];
      if (earlierFolders is List) {
        for (final dynamic f in earlierFolders) {
          if (f is String && f.isNotEmpty && !earlierDownloadFolders.contains(f)) earlierDownloadFolders.add(f);
        }
      }
    }

    try {
      final dynamic raw = json['hiddenTagsPerBooru'];
      hiddenTagsPerBooru.clear();
      if (raw is Map) {
        raw.forEach((boorus, tagsAny) {
          if (boorus is! String) return;
          final List<String> tags = [];
          if (tagsAny is List) {
            for (final t in tagsAny) {
              if (t is String && t.isNotEmpty) tags.add(t);
            }
          }
          if (tags.isNotEmpty) hiddenTagsPerBooru[boorus] = tags.toSet();
        });
      }
      invalidateBlacklistCache();
    } catch (e, s) {
      Logger.Inst().log(
        'Failed to parse per-booru hidden tags $e',
        'SettingsHandler',
        'loadFromJSON',
        LogTypes.exception,
        s: s,
      );
    }

    try {
      dynamic tempMarkedTags = json['markedTags'] ?? json['lovedTags'];
      if (tempMarkedTags is List) {
        // print('markedTags is a list');
      } else if (tempMarkedTags is String) {
        // print('markedTags is a string');
        tempMarkedTags = tempMarkedTags.split(',');
      } else {
        // print('markedTags is a ${tempMarkedTags.runtimeType} type');
        tempMarkedTags = [];
      }
      markedTags.clear();
      final List<String> markTags = List<String>.from(tempMarkedTags);
      for (int i = 0; i < markTags.length; i++) {
        markedTags.add(markTags.elementAt(i));
      }
    } catch (e, s) {
      Logger.Inst().log(
        'Failed to parse marked tags $e',
        'SettingsHandler',
        'loadFromJSON',
        LogTypes.exception,
        s: s,
      );
    }

    final List<String> leftoverKeys = json.keys
        .where(
          (e) => ![
            'buttonOrder',
            'disabledButtons',
            'hiddenTags',
            'markedTags',
          ].contains(e),
        )
        .toList();
    for (final String key in leftoverKeys) {
      try {
        setByString(key, json[key]);
      } catch (e, s) {
        Logger.Inst().log(
          'Failed to set value for key $key',
          'SettingsHandler',
          'loadFromJSON',
          LogTypes.exception,
          s: s,
        );
      }
      // print('key $key val ${json[key]} type ${json[key].runtimeType}');
    }

    if (setMissingKeys) {
      // find all keys that are missing in the file and set them to default values
      map.forEach((key, value) {
        // The lists read above already got their defaults; their declared
        // defaults are strings, which setByString cannot assign.
        if (!json.keys.contains(key) &&
            !['buttonOrder', 'disabledButtons', 'hiddenTags', 'markedTags'].contains(key)) {
          if (map[key] != null) {
            setByString(key, map[key]!['default']);
          }
        }
      });
    }

    // force mobile app mode, until we redo UI for desktop and start doing builds again
    appMode.value = AppMode.Mobile;

    // One-time Flow skin migration (startup loads only, not sync payloads):
    // older installs carry a pre-redesign theme (Pink/Red accent, AMOLED,
    // dynamic wallpaper colours) that fights the Flow skin. Switch them to the
    // Flow preset once; afterwards any manual theme change sticks.
    if (setMissingKeys && flowSkinApplied.value != true) {
      theme.value = ThemeItem(
        name: 'Flow',
        primary: const Color(0xFFB9A0E8),
        accent: const Color(0xFFB9A0E8),
      );
      themeMode.value = ThemeMode.dark;
      isAmoled.value = false;
      useDynamicColor.value = false;
      flowSkinApplied.value = true;
      _flowMigrationPending = true;
    }

    return true;
  }

  Future<bool> saveSettings({required bool restate}) async {
    await getStoragePermission();
    if (path == '') {
      await setConfigDir();
    }
    await Directory(path).create(recursive: true);
    // Each save writes a file of its own and renames it over settings.json:
    // a kill or an error mid-write leaves the previous file whole, and two
    // saves at once no longer write into the same file together.
    final String json = jsonEncode(toJson());
    final int snapshot = ++_saveSnapshot;
    final File settingsFile = File('${path}settings.json');
    final File tempFile = File('${path}settings.json.$snapshot.tmp');
    final writer = tempFile.openWrite();
    writer.write(json);
    await writer.close();
    if (snapshot > _savedSnapshot) {
      try {
        // Synchronous, so no other save lands between the check and the rename.
        tempFile.renameSync(settingsFile.path);
        _savedSnapshot = snapshot;
      } on FileSystemException {
        // The rename was refused (a file another program holds open): write
        // in place, as before.
        _savedSnapshot = snapshot;
        final inPlace = settingsFile.openWrite();
        inPlace.write(json);
        await inPlace.close();
        try {
          await tempFile.delete();
        } catch (_) {}
      }
    } else {
      // A save that read the settings later has already landed.
      try {
        await tempFile.delete();
      } catch (_) {}
    }

    if (restate) {
      final searchHandler = SearchHandler.instance;
      searchHandler.filterCurrentFetched(); // refilter fetched because user could have changed the filtering settings
      unawaited(
        Future.delayed(const Duration(seconds: 1)).then((_) {
          searchHandler.rootRestate?.call(); // force global state update to redraw stuff
        }),
      );
    }
    await _writeMpvlibVariant();
    return true;
  }

  Future<void> setConfigDir() async {
    // print('-=-=-=-=-=-=-=-');
    // print(Platform.environment);
    path = await ServiceHandler.getConfigDir();
    boorusPath = '${path}boorus/';
    return;
  }
}
