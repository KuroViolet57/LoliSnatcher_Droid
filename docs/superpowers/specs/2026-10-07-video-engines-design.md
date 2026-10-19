# Media3 and mpvlib engines, same controls

Date: 2026-10-07. One-shot. The user asked for this ahead of the previous backlog.

## Why, and principles

Settings → Video can already pick media_kit or better_player. Those draw their own buttons. better_player drops long-press fast-forward. The user wants two more engines to A/B, and the layer on top of the picture to stay the one they already use.

- Same buttons, same double-tap skip, same long-press fast-forward, same viewer toolbar, same details bottom sheet.
- Media3 is a real ExoPlayer 1.11 surface, not a rename of the better_player toggle.
- mpvlib Vulkan and mpvlib OpenGL are the two v1.1.1 builds from https://github.com/Riteshp2001/mpvlibAndroid . FongMi is not included.
- The default Chewie path, media_kit, better_player, and the media_kit screen-size cap stay.

## What the user sees

Navigation: Settings → Video → Video engine.

Choices:

| Choice | What plays | When it applies |
|---|---|---|
| Off | Today's order: media_kit if that switch is on, else better_player if that switch is on, else Chewie | Immediately. Restart the viewer. |
| Media3 ExoPlayer | androidx.media3 1.11.0, same LoliControls | Android, immediately. Restart the viewer. |
| mpvlib Vulkan | mpvlib-1.1.1.aar native libraries, `vo=gpu`, `gpu-api=vulkan` | Android, after the app is restarted. |
| mpvlib OpenGL | mpvlib-no-vulkan-1.1.1.aar, `vo=gpu`, `gpu-api=opengl` | Android, after the app is restarted. |

The dropdown help says the new choice wins over the media_kit and better_player switches, that desktop ignores it, and that mpvlib needs a full restart because only one `libmpv.so` can be loaded. If the running process loaded a different mpvlib build, the video area says to restart instead of silently using Chewie.

The buttons are `LoliControls`: tap, double-tap skip, long-press 2× to 4×, scrubber, speed, mute, fullscreen. The gallery toolbar and the details sheet are untouched. Pinch zoom still wraps the picture. Neighbour preload is ignored for mpvlib, because that library is one player per process.

No new look controls. The engine choice is the setting. Existing video toggles (autoplay, mute, long-press) still apply, because the controls widget is unchanged.

Guide: `docs/FEATURES.md` rows for the video engine and for LoliControls. In-app text is the dropdown subtitle on Settings → Video.

## Platform limits, with sources

- mpvlib v1.1.1 (2026-10-01), MIT. Vulkan archive SHA-256 `2c0b77bcbee2796fefde61f5abf9d90e1c5f36e1b6a3cf4925ce8e222454c818`. OpenGL archive SHA-256 `86dd920a6ddd936db4caced7ca436917781b5e82ab8d67ebff549c79ca835ed8`. Min API 24. ABIs include arm64-v8a. The app ships arm64 only.
- `MPVLib` on the library branch loads `libmpv.so` and `libplayer.so` in a static block and does not catch failure. Both archives use those names. `media_kit_libs_android_video` 1.3.8 also calls `System.loadLibrary("mpv")` when plugins register, and it catches the error.
- Only one `libmpv.so` can be loaded in a process. The app reads `filesDir/mpvlib-variant` (`off`, `vulkan`, or `opengl`) in a ContentProvider, before plugins. `vulkan` or `opengl` copies that build's arm64 libraries out of assets and `System.load`s them first, so media_kit's load fails into its catch. `off` leaves media_kit's library as it is today. Switching either way needs a new process.
- The two archives are not Gradle `implementation` dependencies. A build task downloads them, checks the hashes, and extracts arm64 libraries into assets. The Java API is the tag's Kotlin (`is.xyz.mpv`), with the static `loadLibrary` removed so the provider owns the load.
- Media3 1.11.0 is the version better_player 1.4.1 already requests. The app module depends on `media3-exoplayer`, HLS, and DASH. The picture is a Flutter texture, so pinch zoom still transforms it. Device volume is not changed. Player volume stays the 0–1 value LoliControls already uses.
- video_player stays 2.11.1 and Chewie stays 1.13.x. Those pins are the Flutter 3.42 ceiling.

## Data

New settings key `videoEngineChoice`, string, one of `off`, `media3`, `mpvlibVulkan`, `mpvlibOpengl`. Default `off`. Unknown values become `off` on load. `settings.json` is copied whole by backup, so the key is included. An old backup without the key stays on `off`. The native variant file is rewritten whenever settings are saved or loaded. A missing method channel (tests, desktop) is ignored.

## Logic, and app/UI

`doubleTapSkip` is the skip rule LoliControls already uses, called from that widget.

`viewerVideoEngine` picks the widget:

- Not Android: Chewie, even if the new choice is set.
- Android and choice is Media3 or either mpvlib: `VideoViewer`, which swaps only the decoder surface.
- Android and choice is off: media_kit, else better_player, else Chewie. Same as today.

`VideoViewer` keeps LoliControls, PhotoView, pause, mute, and the fullscreen flag. For Media3 and mpvlib it drives a `BridgedVideoController` so seek, play, pause, speed, and volume hit the native player and never the video_player platform. The Chewie widget is not mounted for those engines, because it would ask video_player for a texture. Fullscreen still pushes a black route with the same texture and the same LoliControls.

mpvlib OpenGL and Vulkan share that bridge. The native side sets `gpu-api` to match the build that was loaded.

Logs: `video-engine:` lines for the choice, the loaded native variant, open, and native errors.

## What is not changed

Default Chewie behaviour when the choice is off. media_kit and better_player switches and their own overlays. The screen-size cap. Desktop. FongMi. video_player, Chewie, and google_fonts pins. versionCode 5211. No install and no playback from this session.

## Tests

`test/video_engine_choice_test.dart` locks the skip amounts, the engine precedence, the variant file text, and that the viewer still references LoliControls for the new engines. Native playback is a phone check.

## Assumption register

| ID | Assumption | How it could be wrong | Result | Status |
|---|---|---|---|---|
| A1 | Tag v1.1.1 Kotlin JNI matches the AAR | The branch tip is one commit ahead of the tag | Vendor the tag, not the tip | verified: tag and no-vulkan MPVLib.kt match, and both AARs have the same MPVLib.class. The static loadLibrary block is removed |
| A2 | arm64 extracts and a NEEDED-libs order loads | A library name differs, or a system lib is in the list | Build task writes order.txt from llvm-readobj and skips system libs | verified: 10 arm64 libraries each. Vulkan libmpv needs libvulkan.so; the OpenGL build does not |
| A3 | SurfaceTexture works for ExoPlayer and this mpv | Black frame, or mpv wants a SurfaceView | Texture keeps zoom. Phone checklist item if the frame stays black | guessed |
| A4 | ContentProvider runs before media_kit's loadLibrary | A plugin loads earlier | Provider initOrder is the earliest app code | guessed |
| A5 | `gpu-api=vulkan` and `gpu-api=opengl` match the two builds | The build uses a different context name and the picture fails | The loaded library is still the A/B. Phone checklist names the property | guessed |

## Coverage

The user asked for Media3, both mpvlib builds, and the same overlay. All three are in this spec. FongMi is out because it was not requested. No parent roadmap item is dropped. The previous backlog stays where it was.

## Delivery

Side-by-side APK token 145 after the commit. Not installed. Not marked tested.
