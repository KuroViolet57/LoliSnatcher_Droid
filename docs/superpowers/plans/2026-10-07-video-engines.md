# Media3 and mpvlib engines

Goal: Settings → Video can select Media3 ExoPlayer 1.11 or either mpvlibAndroid 1.1.1 build, and the viewer keeps LoliControls, the toolbar, and the details sheet.

Architecture: Pure skip and engine choice. VideoViewer swaps the decoder surface under the existing controls. Android loads at most one mpvlib `libmpv.so`, before plugins.

Spec: `docs/superpowers/specs/2026-10-07-video-engines-design.md`

## Global Constraints

- versionCode stays 5211. Side-by-side package `com.noaisu.loliSnatcher.v1`.
- Do not bump video_player, Chewie, google_fonts, or fvp.
- Do not drop media_kit, better_player, or `viewer.videoCapToScreen`.
- Do not vendor the FongMi AAR or either full AAR. arm64 libraries only, hash-checked.
- Do not call AudioManager or raise the device volume.
- Do not `implementation` both AARs. Class and `.so` names collide.
- Min SDK 24. Release minify stays on. Keep `is.xyz.mpv.**`.
- New key `videoEngineChoice` default `off` so an old `settings.json` does not change engines.
- One flutter command at a time, through `tool/flutterw.sh`.

## Review Focus

- Same event, every path: gallery page and post-files page both use `viewerVideoEngine`. A Media3 choice must not also build media_kit.
- State over time: variant file written on save and on load. Process restart is required both ways. A mismatch shows a restart message and does not open the other engine.
- Hostile input: unknown `videoEngineChoice` becomes `off`. Empty variant file is `off`.
- Near-miss: `VideoBackendMode.mpv` stays the media_kit video_player backend. It is not mpvlib.
- Concurrency: one mpvlib player. A newer open replaces the older native session. Media3 sessions are keyed by texture id.
- Failure: hash mismatch fails the build. Native open error sets the controller error. Missing method channel in tests is ignored.
- Platform: native load is not on the Flutter UI isolate. ExoPlayer is created on the main looper. R8 must keep the JNI class.
- A3, A4, A5 stay phone checks.

## Tasks

1. Failing test `test/video_engine_choice_test.dart` for skip amounts, precedence, and variant text.
2. Implement `doubleTapSkip`, `VideoEngineChoice`, and `viewerVideoEngine`. Point LoliControls at `doubleTapSkip`.
3. Settings key, dropdown, save/load variant write.
4. Bridged controller and VideoViewer surface swap, including fullscreen and the restart message.
5. Android Media3 texture player, mpvlib loader, hashed archive task, proguard keep.
6. FEATURES.md rows. Targeted tests. Commit. Side-by-side token 145. Do not install.

## Execution notes

Dart selection, LoliControls, the settings key, and the Android texture bridge are in. `test/video_engine_choice_test.dart` passed (3). `flutter analyze` on the touched Dart files reported no issues. `:app:compileReleaseKotlin` succeeded, including `prepareMpvlib`. Playback, the black-texture guess, provider ordering, and the gpu-api names stay phone checks. The side-by-side APK is token 145 and is not installed.
