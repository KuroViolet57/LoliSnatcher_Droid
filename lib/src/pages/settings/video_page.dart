import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:fvp/fvp.dart' as fvp;

import 'package:lolisnatcher/src/data/settings/mpv_hardware_decoding.dart';
import 'package:lolisnatcher/src/data/settings/mpv_video_output.dart';
import 'package:lolisnatcher/src/data/settings/video_backend_mode.dart';
import 'package:lolisnatcher/src/data/settings/video_cache_mode.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/video/media_kit_video_player.dart';

class VideoSettingsPage extends StatefulWidget {
  const VideoSettingsPage({super.key});

  @override
  State<VideoSettingsPage> createState() => _VideoSettingsPageState();
}

class _VideoSettingsPageState extends State<VideoSettingsPage> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;

  bool autoPlay = true;
  bool startVideosMuted = false;
  bool disableVideo = false;
  bool useBetterPlayer = false;
  bool useMediaKitPlayer = false;
  final TextEditingController mediaKitMaxPlayersController = TextEditingController();
  final TextEditingController betterPlayerCacheMbController = TextEditingController();
  final TextEditingController betterPlayerPerFileMbController = TextEditingController();
  bool altVideoPlayerHwAccel = true;
  VideoBackendMode videoBackendMode = SettingsHandler.isDesktopPlatform
      ? VideoBackendMode.mpv
      : VideoBackendMode.normal;
  late MpvVideoOutput altVideoPlayerVO;
  late MpvHardwareDecoding altVideoPlayerHWDEC;
  late VideoCacheMode videoCacheMode;

  @override
  void initState() {
    super.initState();

    autoPlay = settingsHandler.autoPlayEnabled;
    startVideosMuted = settingsHandler.startVideosMuted;
    disableVideo = settingsHandler.disableVideo;
    useBetterPlayer = settingsHandler.useBetterPlayer;
    useMediaKitPlayer = settingsHandler.useMediaKitPlayer;
    mediaKitMaxPlayersController.text = settingsHandler.mediaKitMaxPlayers.toString();
    betterPlayerCacheMbController.text = settingsHandler.betterPlayerCacheMb.toString();
    betterPlayerPerFileMbController.text = settingsHandler.betterPlayerPerFileMb.toString();
    videoBackendMode = settingsHandler.videoBackendMode;
    altVideoPlayerHwAccel = settingsHandler.altVideoPlayerHwAccel;
    altVideoPlayerVO = settingsHandler.altVideoPlayerVO;
    altVideoPlayerHWDEC = settingsHandler.altVideoPlayerHWDEC;
    videoCacheMode = settingsHandler.videoCacheMode;
  }

  Future<void> _onPopInvoked(_, _) async {
    settingsHandler.autoPlayEnabled = autoPlay;
    settingsHandler.startVideosMuted = startVideosMuted;
    settingsHandler.disableVideo = disableVideo;
    settingsHandler.useBetterPlayer = useBetterPlayer;
    settingsHandler.useMediaKitPlayer = useMediaKitPlayer;
    settingsHandler.mediaKitMaxPlayers =
        (int.tryParse(mediaKitMaxPlayersController.text) ?? 4).clamp(1, 20);
    settingsHandler.betterPlayerCacheMb =
        (int.tryParse(betterPlayerCacheMbController.text) ?? 500).clamp(0, 50000);
    settingsHandler.betterPlayerPerFileMb =
        (int.tryParse(betterPlayerPerFileMbController.text) ?? 100).clamp(0, 50000);
    settingsHandler.videoBackendMode = SettingsHandler.isDesktopPlatform ? VideoBackendMode.mpv : videoBackendMode;
    settingsHandler.altVideoPlayerHwAccel = altVideoPlayerHwAccel;
    settingsHandler.altVideoPlayerVO = altVideoPlayerVO;
    settingsHandler.altVideoPlayerHWDEC = altVideoPlayerHWDEC;
    settingsHandler.videoCacheMode = videoCacheMode;

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

    await settingsHandler.saveSettings(restate: false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: SettingsAppBar(
          title: context.loc.settings.video.title,
        ),
        body: Center(
          child: ListView(
            children: [
              SettingsToggle(
                value: disableVideo,
                onChanged: (newValue) {
                  setState(() {
                    disableVideo = newValue;
                  });
                },
                title: context.loc.settings.video.disableVideos,
                trailingIcon: IconButton(
                  icon: const Icon(Symbols.help_rounded),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) {
                        return SettingsDialog(
                          title: Text(context.loc.settings.video.disableVideos),
                          contentItems: [
                            Text(
                              context.loc.settings.video.disableVideosHelp,
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              SettingsToggle(
                value: autoPlay,
                onChanged: (newValue) {
                  setState(() {
                    autoPlay = newValue;
                  });
                },
                title: context.loc.settings.video.autoplayVideos,
              ),
              SettingsToggle(
                value: startVideosMuted,
                onChanged: (newValue) {
                  setState(() {
                    startVideosMuted = newValue;
                  });
                },
                title: context.loc.settings.video.startVideosMuted,
              ),
              //
              const SettingsButton(name: '', enabled: false),
              SettingsButton(
                name: context.loc.settings.video.experimental,
                icon: const Icon(Symbols.science_rounded),
              ),
              if (!SettingsHandler.isDesktopPlatform)
                SettingsToggle(
                  value: useMediaKitPlayer,
                  onChanged: (newValue) {
                    setState(() {
                      useMediaKitPlayer = newValue;
                    });
                  },
                  title: 'Use media_kit engine (experimental)',
                  leadingIcon: const Icon(Symbols.bolt_rounded),
                  subtitle: const Text(
                    'A completely separate video engine built on media_kit (libmpv) instead of ExoPlayer. libmpv manages its own decoders with software fallback, so it sidesteps the hardware-decoder-exhaustion crashes that can happen when scrolling fast through many videos. Same custom controls (tap, double-tap to skip, scrubber, fullscreen). Takes precedence over better_player when both are on. Restart the viewer for changes to take effect.',
                  ),
                ),
              if (!SettingsHandler.isDesktopPlatform && useMediaKitPlayer)
                SettingsTextInput(
                  controller: mediaKitMaxPlayersController,
                  title: 'media_kit warm player pool size',
                  hintText: '4',
                  inputType: TextInputType.number,
                  numberStep: 1,
                  numberButtons: true,
                  resetText: () => '4',
                  subtitle: const Text(
                    "How many recently-viewed videos to keep warm in memory. Scrolling back to a video that's still in the pool resumes with its buffer intact instead of restarting the download. Higher = smoother scrub-back but more RAM. libmpv has no MediaCodec limit, so values up to ~10 are safe on most devices. Default 4 (current + previous + next + one more).",
                  ),
                ),
              if (!SettingsHandler.isDesktopPlatform)
                SettingsToggle(
                  value: useBetterPlayer,
                  onChanged: (newValue) {
                    setState(() {
                      useBetterPlayer = newValue;
                    });
                  },
                  title: 'Use better_player engine (experimental)',
                  leadingIcon: const Icon(Symbols.science_rounded),
                  subtitle: const Text(
                    "Swaps the default video pipeline for better_player_plus, which exposes ExoPlayer's buffer and HTTP-cache tuning. Helps with the stall-buffer-stall cycle on jittery CDNs. Disables LoliControls-specific features (long-tap fast-forward) and the MPV fallback path while on. Restart the viewer for changes to take effect.",
                  ),
                ),
              if (!SettingsHandler.isDesktopPlatform && useBetterPlayer) ...[
                SettingsTextInput(
                  controller: betterPlayerCacheMbController,
                  title: 'better_player video cache (MB)',
                  hintText: '500',
                  inputType: TextInputType.number,
                  numberStep: 100,
                  numberButtons: true,
                  resetText: () => '500',
                  subtitle: const Text(
                    'Total on-disk cache for the better_player engine. Recently-watched videos serve from here on rewatch / scroll-back without re-hitting the CDN. 0 disables. Default 500. Bump higher (e.g. 2000-5000) if you have spare storage and want long browsing sessions to stay snappy.',
                  ),
                ),
                SettingsTextInput(
                  controller: betterPlayerPerFileMbController,
                  title: 'better_player cache size per video (MB)',
                  hintText: '100',
                  inputType: TextInputType.number,
                  numberStep: 50,
                  numberButtons: true,
                  resetText: () => '100',
                  subtitle: const Text(
                    'Per-file cap. Stops a single very long video from eating the whole cache pool.',
                  ),
                ),
              ],
              if (!SettingsHandler.isDesktopPlatform)
                SettingsDropdown(
                  value: videoBackendMode,
                  items: VideoBackendMode.values,
                  itemTitleBuilder: (item) => switch (item) {
                    VideoBackendMode.normal => context.loc.settings.video.backendDefault,
                    VideoBackendMode.mpv => context.loc.settings.video.backendMPV,
                    VideoBackendMode.mdk => context.loc.settings.video.backendMDK,
                    _ => '',
                  },
                  itemSubtitleBuilder: (item) => switch (item) {
                    VideoBackendMode.normal => context.loc.settings.video.backendDefaultHelp,
                    VideoBackendMode.mpv => context.loc.settings.video.backendMPVHelp,
                    VideoBackendMode.mdk => context.loc.settings.video.backendMDKHelp,
                    _ => '',
                  },
                  onChanged: (newValue) {
                    setState(() {
                      videoBackendMode = newValue ?? VideoBackendMode.normal;
                    });
                  },
                  title: context.loc.settings.video.videoPlayerBackend,
                ),

              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                child: (!videoBackendMode.isNormal || SettingsHandler.isDesktopPlatform)
                    ? Column(
                        children: [
                          if (videoBackendMode.isMpv) ...[
                            Padding(
                              padding: const EdgeInsets.only(left: 16, right: 16, top: 8),
                              child: Text(
                                context.loc.settings.video.mpvSettingsHelp,
                              ),
                            ),
                            SettingsToggle(
                              value: altVideoPlayerHwAccel,
                              onChanged: (newValue) {
                                setState(() {
                                  altVideoPlayerHwAccel = newValue;
                                });
                              },
                              title: context.loc.settings.video.mpvUseHardwareAcceleration,
                            ),
                            SettingsDropdown<MpvVideoOutput>(
                              value: altVideoPlayerVO,
                              items: MpvVideoOutput.values,
                              onReset: () {
                                setState(() {
                                  altVideoPlayerVO = MpvVideoOutput.defaultValue;
                                });
                              },
                              onChanged: (MpvVideoOutput? newValue) {
                                setState(() {
                                  altVideoPlayerVO = newValue ?? MpvVideoOutput.defaultValue;
                                });
                              },
                              title: context.loc.settings.video.mpvVO,
                              itemTitleBuilder: (e) => e?.locName ?? '',
                            ),
                            SettingsDropdown<MpvHardwareDecoding>(
                              value: altVideoPlayerHWDEC,
                              items: MpvHardwareDecoding.values,
                              onReset: () {
                                setState(() {
                                  altVideoPlayerHWDEC = MpvHardwareDecoding.defaultValue;
                                });
                              },
                              onChanged: (MpvHardwareDecoding? newValue) {
                                setState(() {
                                  altVideoPlayerHWDEC = newValue ?? MpvHardwareDecoding.defaultValue;
                                });
                              },
                              title: context.loc.settings.video.mpvHWDEC,
                              itemTitleBuilder: (e) => e?.locName ?? '',
                            ),
                          ],
                          SettingsOptionsList<VideoCacheMode>(
                            value: videoCacheMode,
                            items: VideoCacheMode.values,
                            onChanged: (VideoCacheMode? newValue) {
                              setState(() {
                                videoCacheMode = newValue ?? VideoCacheMode.defaultValue;
                              });
                            },
                            title: context.loc.settings.video.videoCacheMode,
                            itemTitleBuilder: (e) => e?.locName ?? '',
                            subtitle: const Text(
                              '''Videos on some Boorus may not work correctly (i.e. endless loading) when using Stream video cache mode. In that case try using Cache mode. Otherwise player will retry with Cache mode automatically if video is in initial buffering state for 10+ seconds and video file size is less than 25mb''',
                            ),
                            trailingIcon: IconButton(
                              icon: const Icon(Symbols.help_rounded),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) {
                                    return SettingsDialog(
                                      title: Text(context.loc.settings.video.cacheModes.title),
                                      contentItems: [
                                        Text(context.loc.settings.video.cacheModes.streamMode),
                                        Text(context.loc.settings.video.cacheModes.cacheMode),
                                        Text(context.loc.settings.video.cacheModes.streamCacheMode),
                                        const Text(''),
                                        Text(context.loc.settings.video.cacheModes.cacheNote),
                                        const Text(''),
                                        if (SettingsHandler.isDesktopPlatform)
                                          Text(context.loc.settings.video.cacheModes.desktopWarning),
                                      ],
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      )
                    : LayoutBuilder(
                        // used to avoid animating width change
                        builder: (_, constraints) => SizedBox(width: constraints.maxWidth),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
