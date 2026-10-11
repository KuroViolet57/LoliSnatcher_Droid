import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';

import 'package:alice_lightweight/alice.dart';
import 'package:alice_lightweight/helper/alice_save_helper.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:lolisnatcher/features/recommender/logic/model_tasks.dart';
import 'package:lolisnatcher/core/settings/modular_ui.dart';
import 'package:lolisnatcher/models/tag.dart';
import 'package:lolisnatcher/core/settings/app_locale_ext.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/blacklist_line.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/core/constants.dart';
import 'package:lolisnatcher/models/settings/app_alias.dart';
import 'package:lolisnatcher/models/settings/app_mode.dart';
import 'package:lolisnatcher/models/settings/button_position.dart';
import 'package:lolisnatcher/models/settings/gallery_button.dart';
import 'package:lolisnatcher/models/settings/settings_enum.dart';
import 'package:lolisnatcher/models/settings/hand_side.dart';
import 'package:lolisnatcher/models/settings/image_quality.dart';
import 'package:lolisnatcher/models/settings/mpv_hardware_decoding.dart';
import 'package:lolisnatcher/models/settings/mpv_video_output.dart';
import 'package:lolisnatcher/models/settings/preview_display_mode.dart';
import 'package:lolisnatcher/models/settings/preview_quality.dart';
import 'package:lolisnatcher/models/settings/proxy_type.dart';
import 'package:lolisnatcher/models/settings/scroll_direction.dart';
import 'package:lolisnatcher/models/settings/share_action.dart';
import 'package:lolisnatcher/models/settings/vertical_position.dart';
import 'package:lolisnatcher/models/settings/video_backend_mode.dart';
import 'package:lolisnatcher/models/settings/video_engine_choice.dart';
import 'package:lolisnatcher/models/settings/video_cache_mode.dart';
import 'package:lolisnatcher/models/theme_item.dart';
import 'package:lolisnatcher/models/update_info.dart';
import 'package:lolisnatcher/core/storage/database_handler.dart';
import 'package:lolisnatcher/features/doujin/logic/doujin_data_handler.dart';
import 'package:lolisnatcher/core/settings/source_settings_handler.dart';
import 'package:lolisnatcher/core/ui/navigation_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/core/platform/secure_storage_handler.dart';
import 'package:lolisnatcher/features/recommender/logic/ml/model_timings.dart';
import 'package:lolisnatcher/features/recommender/logic/onnx/onnx_availability.dart';
import 'package:lolisnatcher/core/platform/service_handler.dart';
import 'package:lolisnatcher/core/platform/get_perms.dart';
import 'package:lolisnatcher/core/platform/saf_file_cache.dart';
import 'package:lolisnatcher/features/links/logic/source_links.dart';
import 'package:lolisnatcher/core/network/dio_network.dart';
import 'package:lolisnatcher/core/network/http_overrides.dart';
import 'package:lolisnatcher/core/logging/logger.dart';
import 'package:lolisnatcher/core/logging/startup_timeline.dart';
import 'package:lolisnatcher/core/utils/tools.dart';
import 'package:lolisnatcher/core/ui/flash_elements.dart';
import 'package:lolisnatcher/core/ui/settings_widgets.dart';
import 'package:lolisnatcher/features/video/logic/media_kit_video_player.dart';

// exporting localization here to avoid import repetition, since we use settingsHandler in a lot of places anyway
export 'package:lolisnatcher/gen/strings.g.dart';
part 'settings_handler/schema.dart';
part 'settings_handler/storage.dart';
part 'settings_handler/boorus.dart';
part 'settings_handler/tag_filters.dart';
part 'settings_handler/updates.dart';
part 'settings_handler/startup.dart';

/// This class is used loading from and writing settings to files
class SettingsHandler {
  static SettingsHandler get instance => GetIt.instance<SettingsHandler>();

  static SettingsHandler register() {
    if (!GetIt.instance.isRegistered<SettingsHandler>()) {
      GetIt.instance.registerSingleton(SettingsHandler());
    }
    return instance;
  }

  static void unregister() => GetIt.instance.unregister<SettingsHandler>();

  static bool get isDesktopPlatform => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// r84: once after the whole database came back from a backup, offer to
  /// check the downloads (features/downloads/ui DownloadsCheck). Bound once at
  /// start by app/layer_bindings.dart.
  static Future<void> Function() afterRestoreCheck = _noAfterRestoreCheck;

  static Future<void> _noAfterRestoreCheck() async {}

  DBHandler dbHandler = DBHandler();

  late Alice alice;

  // service vars
  final RxBool isInit = false.obs, isPostInit = false.obs;
  final RxString postInitMessage = ''.obs;
  String cachePath = '';
  String path = '';
  String boorusPath = '';

  final Rx<UpdateInfo?> updateInfo = Rxn(null);

  ////////////////////////////////////////////////////

  // runtime settings vars
  bool hasHydrus = false;
  final RxString discordURL = RxString(Constants.discordURL);

  // debug toggles
  final RxBool isDebug = (kDebugMode || false).obs;
  final RxBool showFps = false.obs;
  final RxBool showPerf = false.obs;
  final RxBool showImageStats = false.obs;
  final RxBool showVideoStats = false.obs;
  final RxBool blurImages = (kDebugMode ? Constants.blurImagesDefaultDev : false).obs;

  ////////////////////////////////////////////////////

  // saveable settings vars
  AppAlias appAlias = AppAlias.defaultValue;
  String defTags = 'rating:safe';
  PreviewQuality previewMode = PreviewQuality.defaultValue;
  VideoCacheMode videoCacheMode = VideoCacheMode.defaultValue;
  String prefBooru = '';
  PreviewDisplayMode previewDisplay = PreviewDisplayMode.defaultValue;
  PreviewDisplayMode previewDisplayFallback = PreviewDisplayMode.defaultValue;
  ImageQuality galleryMode = ImageQuality.defaultValue;
  ImageQuality snatchMode = ImageQuality.defaultValue;
  ShareAction shareAction = ShareAction.defaultValue;
  final Rx<AppMode> appMode = AppMode.defaultValue.obs;
  final Rx<HandSide> handSide = HandSide.defaultValue.obs;

  /// On a Kemono tab, the pinned-tags drawer is replaced by the site's own
  /// sidebar (Artists / Posts / Favorites / DMs). Off = the normal drawer.
  /// Flipped from the bottom of either drawer.
  final RxBool kemonoSidebar = true.obs;

  /// On a FurAffinity tab the pinned-tags side carries the site's own
  /// sidebar (r42). Off = the normal drawer. Flipped from either drawer.
  final RxBool furAffinitySidebar = true.obs;

  /// The kemono post page loads the real files instead of the site's 800 px
  /// pictures. Off by default: pawchive rate-limits heavy downloading.
  final RxBool kemonoPostFullImages = false.obs;
  VerticalPosition galleryBarPosition = VerticalPosition.defaultValue;
  ScrollDirection galleryScrollDirection = ScrollDirection.defaultValue;
  String extPathOverride = '';
  String drawerMascotPathOverride = '';
  String backupPath = '';
  ButtonPosition zoomButtonPosition = ButtonPosition.defaultValue;
  ButtonPosition changePageButtonsPosition = ButtonPosition.defaultValueDesktopOnly;
  ButtonPosition scrollGridButtonsPosition = ButtonPosition.defaultValueDesktopOnly;
  String lastSyncIp = '';
  String lastSyncPort = '';
  // TODO move it to boorus themselves to have different user agents for different boorus?
  String customUserAgent = '';
  ProxyType proxyType = ProxyType.defaultValue;
  String proxyAddress = '';
  String proxyUsername = '';
  String proxyPassword = '';
  VideoBackendMode videoBackendMode = isDesktopPlatform ? VideoBackendMode.mpv : VideoBackendMode.normal;
  MpvVideoOutput altVideoPlayerVO = MpvVideoOutput.defaultValue;
  MpvHardwareDecoding altVideoPlayerHWDEC = MpvHardwareDecoding.defaultValue;

  Set<String> hiddenTags = {};
  // Per-booru hidden tags. Keyed by booru.name. A tag in this map's value-set
  // hides matching items only on that booru, regardless of the global list.
  Map<String, Set<String>> hiddenTagsPerBooru = {};

  // Modular UI switches (r41): toggle key -> on/off, only those changed
  // from their default. See ModularUi.
  Map<String, bool> modularUi = {};
  Set<String> markedTags = {};

  int itemLimit = Constants.defaultItemLimit;
  int portraitColumns = 2;
  int landscapeColumns = 4;
  int preloadCount = 1;
  int preloadHeight = 4096 * 4;
  int snatchCooldown = 250;
  int volumeButtonsScrollSpeed = 200;
  int galleryAutoScrollTime = 4000;
  // Separate, usually longer, slideshow dwell for video / GIF slides so they
  // get time to play before the slideshow advances.
  int galleryAutoScrollVideoTime = 10000;
  int cacheSize = 3;
  int autoLockTimeout = 120;

  double mousewheelScrollSpeed = 10;
  double preloadSizeLimit = 0.2;

  Duration cacheDuration = Duration.zero;

  List<GalleryButton> buttonOrder = [...GalleryButton.values];
  List<GalleryButton> disabledButtons = [];

  bool jsonWrite = false;
  bool autoPlayEnabled = true;
  bool respectManualPause = true;
  // When false, neighbour pages in the gallery only start downloading their
  // video once the user actually swipes to them. Saves bandwidth and stops
  // the currently-watched video from competing with preloads.
  bool preloadVideos = false;
  // Experimental: swap the Flutter video_player / chewie pipeline for
  // better_player_plus on Android. Exposes ExoPlayer's buffer + cache
  // tuning, which Flutter's default plugin hides. Off by default so the
  // tried-and-true engine stays the safe path.
  bool useBetterPlayer = false;
  // Experimental media_kit (libmpv) engine. Not ExoPlayer/MediaCodec-based,
  // so it sidesteps the hardware-decoder-exhaustion crashes; libmpv manages
  // its own decoding (with software fallback). Takes precedence over
  // useBetterPlayer when both are on.
  bool useMediaKitPlayer = false;
  // off keeps media_kit / better_player / Chewie. media3 and the two mpvlib
  // builds use LoliControls and, on Android, win over those switches.
  String videoEngineChoice = 'off';
  // How many media_kit (libmpv) players to keep warm in the LRU pool. More =
  // scrolling back to a recent video resumes instantly with its buffer
  // intact, at the cost of RAM. libmpv has no MediaCodec limit so this is
  // safe to raise on devices with spare memory.
  int mediaKitMaxPlayers = 4;

  /// r62: how long a video has to stay on screen before its player is built.
  /// Swiping past faster than this builds nothing at all.
  int videoStartDelayMs = 333;
  // ExoPlayer on-disk cache size for the better_player engine, in MB.
  // 0 disables. Default 500 MB; bumping this means more recently-watched
  // videos serve from disk on rewatch / scroll-back without re-hitting the
  // CDN. The per-file cap protects a single huge video from eating the pool.
  int betterPlayerCacheMb = 500;
  int betterPlayerPerFileMb = 100;
  // Inline "more from this artist / uploader" thumbnail grids in the
  // post-details drawer. Mirrors Boorusama's pattern. On by default.
  bool inlineRelatedGrids = true;
  // Persisted rect of the floating tag-preview window, stored as
  // 'left,top,width,height' fractions of the screen (empty = use default).
  // Living in settings.json means it also rides along in backup/restore.
  String previewWindowRect = '';
  // Local behaviour tracking that powers the "For You" recommendation tab.
  // Fully on-device (TagSignal table); can be disabled and wiped at any time.
  bool enableInterestTracking = true;
  // r33: the on-device recommender (RecommenderHandler). `aiRecommendations`
  // = the learned model orders and seeds every recommendation surface;
  // `aiLearning` = it keeps learning from what is viewed, read, favourited
  // and skipped. Independent by design: learning may run while the classic
  // ordering is shown, and the learned model may serve while frozen.
  bool aiRecommendations = true;
  bool aiLearning = true;
  // r34: the downloaded sentence encoder (EncoderHandler). `encoderModel` is
  // a preset id ('english', 'multilingual') or a Hugging Face repo id; ''
  // = none downloaded. `aiEncoder` = its vectors join the learner's features.
  bool aiEncoder = true;
  String encoderModel = '';
  // r74: the downloaded image tagger (ImageTaggerHandler). `imageTaggerModel`
  // is a preset id ('wd-vit', 'wd-convnext', 'wd-swinv2') or a Hugging Face
  // repo id; '' = none. `aiImageTagger` = pictures are read with it once it
  // is downloaded (boards). `taggerOnReactions` = a strong reaction on a
  // booru post also learns the tags read from its thumbnail.
  bool aiImageTagger = true;
  String imageTaggerModel = '';
  bool taggerOnReactions = false;
  // r75: the downloaded "looks" model (LookModelHandler): a preset id ('s0',
  // 's2') or a Hugging Face repo id; '' = none. `aiLook` = boards, Posts like
  // this and the learner read pictures with it once it is downloaded.
  bool aiLook = true;
  String lookModel = '';
  // r76: frames from the playing video (VideoFrames) replace a video's
  // preview picture for the looks model, boards and the tagger.
  bool videoFrames = true;
  // r80: Settings → Recommendations → Models (ModelTasks): every model off
  // at once, a switch per job (`modelTasks`, only the ones switched off are
  // stored) and each model's two thread counts (`modelThreads`, only the
  // ones changed from today's are stored). Not declared settings: written
  // next to them, like `modularUi`.
  bool aiModelsOff = false;
  final Map<String, bool> modelTasks = {};
  final Map<String, int> modelThreads = {};
  // r86: what each model runs on (ModelAccelerator by model name; only the
  // ones moved off the CPU are stored) - this phone's hardware, not restored
  // onto another one - and who decodes the models' pictures.
  final Map<String, String> modelRunOn = {};
  PictureDecoder pictureDecoder = PictureDecoder.phone;
  // r80: where captures (a trace report, a source capture) are written;
  // '' = a "captures" folder inside the download folder.
  String capturesPath = '';
  // r81: when a playing video's frames are taken, on For You and in any
  // other tab (FrameMode; both 'playing' = the behaviour before r81), the
  // "Remember the looks of posts you open" switch, and the space the
  // vectors' database may take (MB).
  FrameMode framesForYou = FrameMode.playing;
  FrameMode framesOtherTabs = FrameMode.playing;
  bool rememberLooks = false;
  int vectorSpaceMb = 250;
  // r82: download folders used before the current one (DownloadFolders),
  // newest first. Written next to the declared settings, like `modularUi`.
  final List<String> earlierDownloadFolders = [];
  // Render the post-info panel (tags, metadata) as a Boorusama-style bottom
  // sheet dragged up from the bottom edge instead of the classic right-side
  // drawer. On by default; turn off to restore the side drawer.
  bool useBottomInfoSheet = true;
  // First open of the viewer explains tap, long-press, and double-tap.
  // Close sets this false and saves. Settings → Viewer turns it back on.
  bool showViewerTutorial = true;
  // Hanime1 titles that are not already English are sent to
  // translate.googleapis.com. Settings → Network turns that off.
  bool translateHanimeTitles = true;
  // How much of the screen the bottom info sheet occupies when open, expressed
  // as "thirds": 1 => ~1/3 of the screen, 1.5 => ~1/2, 2 => ~2/3, 3 => full.
  // The sheet locks at this size (content scrolls inside it). fraction = N/3.
  double bottomSheetSizeMultiplier = 2;
  // Default placement for a new tab when the user single-taps the
  // "open in new tab" button. Long-press still shows the pick dialog.
  // String values: 'end' (default) or 'next' (next to current tab).
  String defaultTabAddMode = 'end';
  bool loadingGif = false;
  bool thumbnailCache = true;
  bool mediaCache = true;
  bool autoHideImageBar = false;
  // When true, the top Android status bar is hidden app-wide (the bottom
  // navigation bar is kept), so it doesn't intrude while scrolling the grid.
  bool hideStatusBar = false;
  bool dbEnabled = true;
  bool indexesEnabled = false;
  bool searchHistoryEnabled = true;
  bool filterHated = false;
  bool filterMarked = false;
  bool filterFavourites = false;
  bool filterSnatched = false;
  bool filterAi = false;
  // r85: Settings → Links - links to your sources open in the app.
  bool openSourceLinks = false;
  bool useVolumeButtonsForScroll = false;
  bool shitDevice = false;
  bool disableVideo = false;
  bool enableDrawerMascot = false;
  bool allowSelfSignedCerts = false;
  bool wakeLockEnabled = true;
  bool tagTypeFetchEnabled = true;
  bool downloadNotifications = true;
  bool allowRotation = false;
  bool enableHeroTransitions = true;
  bool disableCustomPageTransitions = false;
  bool incognitoKeyboard = false;
  bool hideNotes = false;
  bool startVideosMuted = false;
  bool snatchOnFavourite = false;
  bool favouriteOnSnatch = false;
  bool disableVibration = false;
  bool altVideoPlayerHwAccel = true;
  bool disableImageScaling = false;
  bool gifsAsThumbnails = false;
  bool desktopListsDrag = false;
  bool showBottomSearchbar = true;
  bool useTopSearchbarInput = false;
  // r38, experimental: the floating tab pill in the feed (tap = tab strip,
  // swipe = next/previous tab, long-press = tab manager).
  bool tabPill = false;
  bool dimSeenPosts = false;
  // Render .gif files with the extended_image engine (the same one Boorusama
  // uses) instead of Flutter's built-in Image widget. extended_image decodes
  // frames at display resolution and manages its own cache, which fixes the
  // slow/stuttery full-res GIF playback. A settings file that omits the key
  // starts on. A saved false stays off.
  bool fastGifPlayback = true;
  bool showSearchbarQuickActions = false;
  bool autofocusSearchbar = true;
  bool expandDetails = false;
  bool usePredictiveBack = true;
  final RxBool useLockscreen = false.obs;
  final RxBool blurOnLeave = false.obs;
  final RxList<Booru> booruList = RxList<Booru>([]);
  ////////////////////////////////////////////////////

  // themes wip
  final Rx<ThemeItem> theme = ThemeItem(
    name: 'Flow',
    primary: const Color(0xFFB9A0E8),
    accent: const Color(0xFFB9A0E8),
  ).obs;

  final Rx<Color?> customPrimaryColor = Colors.pink[200]!.obs;
  final Rx<Color?> customAccentColor = Colors.pink[600]!.obs;

  final Rx<ThemeMode> themeMode = ThemeMode.dark.obs; // system, light, dark
  final RxBool useDynamicColor = false.obs;
  final RxBool isAmoled = false.obs;

  /// One-time "Flow" skin migration marker: existing installs keep their old
  /// persisted theme (e.g. Pink/Red + AMOLED + dynamic colours), which makes
  /// the reskin look broken. On the first launch after the redesign we switch
  /// them to the Flow preset once and set this flag; after that their choices
  /// are respected again.
  final RxBool flowSkinApplied = false.obs;

  final Rx<String> fontFamily = 'System'.obs;

  final Rxn<AppLocale> locale = Rxn<AppLocale>(null);
  ////////////////////////////////////////////////////

  // list of setting names which shouldnt be synced with other devices
  List<String> deviceSpecificSettings = [
    'shitDevice',
    'disableVideo',
    'thumbnailCache',
    'mediaCache',
    'dbEnabled',
    'indexesEnabled',
    'searchHistoryEnabled',
    'useVolumeButtonsForScroll',
    'volumeButtonsScrollSpeed',
    'mousewheelScrollSpeed',
    'prefBooru',
    'appMode',
    'handSide',
    'kemonoSidebar',
    'furAffinitySidebar',
    'kemonoPostFullImages',
    'extPathOverride',
    'backupPath',
    'lastSyncIp',
    'lastSyncPort',
    'customUserAgent',
    'proxyType',
    'proxyAddress',
    'proxyUsername',
    'proxyPassword',
    'videoBackendMode',
    'altVideoPlayerVO',
    'altVideoPlayerHWDEC',
    'altVideoPlayerHwAccel',
    'theme',
    'themeMode',
    'isAmoled',
    'fontFamily',
    'locale',
    'useDynamicColor',
    'customPrimaryColor',
    'customAccentColor',
    'version',
    'disableImageScaling',
    'gifsAsThumbnails',
    'cacheDuration',
    'cacheSize',
    'autoLockTimeout',
    'enableDrawerMascot',
    'drawerMascotPathOverride',
    'allowSelfSignedCerts',
    'showFps',
    'showPerf',
    'showImageStats',
    'showVideoStats',
    'isDebug',
    // r80: cores and folders belong to this phone.
    'modelThreads',
    'modelRunOn',
    'capturesPath',
    'earlierDownloadFolders',
    'desktopListsDrag',
    'incognitoKeyboard',
    'appAlias',
    'showBottomSearchbar',
    'useTopSearchbarInput',
    'tabPill',
    'showSearchbarQuickActions',
    'autofocusSearchbar',
    'expandDetails',
    'usePredictiveBack',
    'useLockscreen',
    'blurOnLeave',
  ];

  /// Set when [loadFromJSON] just performed the one-time Flow skin migration —
  /// tells [loadSettings] to persist immediately so it never re-runs.
  bool _flowMigrationPending = false;

  /// Numbers each save's copy of the settings in the order it was taken, and
  /// the newest copy that reached settings.json.
  int _saveSnapshot = 0;
  int _savedSnapshot = 0;

  // TODO add more tags?
  static const List<String> soundTags = [
    'sound',
    'sound_edit',
    'has_audio',
    'voice_acted',
  ];

  static const List<String> aiTags = [
    'ai_assisted',
    'ai-assisted',
    'ai_created',
    'ai-created',
    'ai_generated',
    'ai-generated',
    'novelai',
    'stable_diffusion',
    'stable-diffusion',
  ];

  /// The lines are keyed by booru name: a renamed booru (or one added as
  /// 'New' on the booru editor) takes its lines to its saved name.
  Future<void> moveBooruHiddenList(String fromName, String toName) async {
    if (fromName.isEmpty || toName.isEmpty || fromName == toName) return;
    final Set<String>? lines = hiddenTagsPerBooru.remove(fromName);
    if (lines == null || lines.isEmpty) return;
    hiddenTagsPerBooru.putIfAbsent(toName, () => <String>{}).addAll(lines);
    invalidateBlacklistCache();
    await saveSettings(restate: false);
  }

  // ─── Blacklist line cache ────────────────────────────────────────────────
  // Each entry in `hiddenTags` / `hiddenTagsPerBooru[name]` is treated as an
  // e621-style blacklist line. We cache the parsed form so filtering N items
  // doesn't re-tokenise the lines every time.

  List<BlacklistLine>? _cachedGlobalLines;
  final Map<String, List<BlacklistLine>> _cachedPerBooruLines = {};
}

class EnvironmentConfig {
  static const bool isFromStore = bool.fromEnvironment(
    'LS_IS_STORE',
    defaultValue: false,
  );

  static const bool isTesting = bool.fromEnvironment(
    'LS_IS_TESTING',
    defaultValue: false,
  );
}

class TagsListData {
  const TagsListData([
    this.hiddenTags = const [],
    this.markedTags = const [],
    this.soundTags = const [],
    this.aiTags = const [],
  ]);

  final List<String> hiddenTags;
  final List<String> markedTags;
  final List<String> soundTags;
  final List<String> aiTags;
}
