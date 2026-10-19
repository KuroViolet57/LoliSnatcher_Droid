# Our copy of media_kit 1.2.6 (token 153)

media_kit 1.2.6 from pub.dev (the newest release, 2025-12-13), without `example/`, `test/` and
`screenshots/`, plus the changes below. `pubspec.yaml` points at it:

```yaml
dependency_overrides:
  media_kit:
    path: third_party/media_kit
```

## The changes

1. **The JavaVM goes to the chosen libmpv** (marked `LoliSnatcher patch (token 153)`).
   `AndroidHelper.ensureInitialized` opened `libmpv.so` by name to call `mpv_lavc_set_java_vm`.
   The app now ships a second libmpv, `libmpvls.so` (mpv 0.41, see
   `third_party/libmpv-android/README.md`), and picks it with
   `MediaKit.ensureInitialized(libmpv: 'libmpvls.so')`; without this change that library never got
   the JavaVM and could not use MediaCodec.
   - `lib/src/player/native/utils/android_helper.dart`: `libmpvName()`, `ensureInitialized({libmpv})`.
   - `lib/src/player/native/player/real.dart`: `nativeEnsureInitialized` passes `libmpv` on.
   With no library given, both behave exactly like the published package.
2. **Upstream's memory-leak fix** [media-kit#1446](https://github.com/media-kit/media-kit/pull/1446)
   (commit c533e446 on `main`, not released yet), the `real.dart` part only:
   `_getPropertyString`, `_setProperty` and `_command` free their native memory on every path,
   and a request that could not be sent is removed from the pending map.
3. **A call without a library keeps the one already chosen** (`LoliSnatcher patch (token 153)`
   in `lib/src/player/native/core/native_library.dart`). media_kit_video's decoder query
   (`queryDecoders`, run for every Android video controller) calls `NativeLibrary.ensureInitialized()`
   with no argument; media_kit then re-resolved to the first default name, `libmpv.so`, and
   handles made by `libmpvls.so` went to the classic library: SIGSEGV in `libmpv.so`
   `mpv_get_property` on the Thor (first 153 build, 2026-10-12). `debugSetResolved` and
   `debugDefaultNames` are test seams (`test/media_kit_engine_test.dart`).

## To undo

1. Delete the three lines under `dependency_overrides` in `pubspec.yaml`.
2. Delete this folder.
3. Set the media_kit libmpv build back to Classic first (Settings -> Video), or the new library will
   load without MediaCodec.

## To move to a newer media_kit

Copy the new version over this folder and re-apply change 1 (search for `LoliSnatcher patch`).
Drop change 2 once the release contains #1446.
