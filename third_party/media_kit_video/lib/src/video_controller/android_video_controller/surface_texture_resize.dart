/// LoliSnatcher patch (token 154, guard from the review of 2026-10-14):
/// whether a resize must re-run `widListener()` so mpv gets the new
/// `android-surface-size`.
///
/// Only a SurfaceTexture keeps its surface (and `wid`) across a resize; the
/// SurfaceProducer path hands out a new `wid`, which runs `widListener` by
/// itself. The first attach (`wid` null or 0) is the plugin's own. A player
/// disposed while `SetSurfaceSize` was in flight (a pool slot dropped) must
/// get no more mpv calls: `NativePlayer.setProperty` would throw
/// "[Player] has been disposed" as an unhandled async error.
bool reapplySurfaceSizeAfterResize({
  required bool surfaceProducer,
  required int? widBefore,
  required bool disposed,
}) =>
    !surfaceProducer && widBefore != null && widBefore != 0 && !disposed;
