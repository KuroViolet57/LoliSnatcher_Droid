import 'package:media_kit/media_kit.dart';

/// Which media_kit player is showing a video right now, for reading its
/// frames (VideoFrames). The pool lives in the ui layer
/// (MediaKitPlayerView); it sets [VideoFramePlayers.source] when it is
/// created. Before that no player exists, so the default answers "nothing
/// showing", as an empty pool does.
abstract interface class VideoFramePlayerSource {
  /// A frame is about to be asked of [player]; its screenshot messages in the
  /// next few seconds are its answer, not a player error.
  void noteGrab(Player player);

  /// The player showing [url], and whether it still holds it later.
  ({Player player, bool Function() stillShowing})? showing(String url);
}

abstract final class VideoFramePlayers {
  static VideoFramePlayerSource source = const _NoPlayers();
}

class _NoPlayers implements VideoFramePlayerSource {
  const _NoPlayers();

  @override
  void noteGrab(Player player) {}

  @override
  ({Player player, bool Function() stillShowing})? showing(String url) => null;
}
