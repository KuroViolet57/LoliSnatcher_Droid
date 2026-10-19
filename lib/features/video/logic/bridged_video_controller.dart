import 'package:flutter/painting.dart';
import 'package:video_player/video_player.dart';

/// A [VideoPlayerController] whose commands go to another decoder.
///
/// LoliControls and Chewie talk to a video_player controller. This subclass
/// keeps that conversation and does not call the video_player platform, so
/// Media3 and mpvlib can sit under the same buttons.
class BridgedVideoController extends VideoPlayerController {
  BridgedVideoController({
    required String url,
    required this.onCommand,
  }) : super.networkUrl(Uri.parse(url));

  final Future<Object?> Function(String name, Map<String, Object?> args) onCommand;

  bool _opened = false;
  bool _nativeDisposed = false;

  @override
  Future<void> initialize() async {
    if (value.isInitialized) return;
    final Object? raw = await onCommand('open', {'url': dataSource});
    if (raw is! Map) {
      value = value.copyWith(errorDescription: 'The video engine returned nothing');
      return;
    }
    final int durationMs = (raw['durationMs'] as num?)?.toInt() ?? 0;
    final double width = (raw['width'] as num?)?.toDouble() ?? 0;
    final double height = (raw['height'] as num?)?.toDouble() ?? 0;
    _opened = true;
    value = value.copyWith(
      isInitialized: true,
      duration: Duration(milliseconds: durationMs < 0 ? 0 : durationMs),
      size: Size(width, height),
      isBuffering: false,
    );
  }

  /// Later native updates (position, a duration that was not ready at open).
  void applyNative(Map<Object?, Object?> event) {
    if (!value.isInitialized) return;
    final Object? error = event['error'];
    if (error is String && error.isNotEmpty) {
      value = value.copyWith(errorDescription: error, isPlaying: false, isBuffering: false);
      return;
    }
    final int durationMs = (event['durationMs'] as num?)?.toInt() ?? value.duration.inMilliseconds;
    final int positionMs = (event['positionMs'] as num?)?.toInt() ?? value.position.inMilliseconds;
    final double width = (event['width'] as num?)?.toDouble() ?? value.size.width;
    final double height = (event['height'] as num?)?.toDouble() ?? value.size.height;
    final int? bufferedMs = (event['bufferedMs'] as num?)?.toInt();
    value = value.copyWith(
      duration: Duration(milliseconds: durationMs < 0 ? 0 : durationMs),
      position: Duration(milliseconds: positionMs < 0 ? 0 : positionMs),
      size: Size(width, height),
      buffered: bufferedMs == null
          ? null
          : <DurationRange>[
              DurationRange(Duration.zero, Duration(milliseconds: bufferedMs < 0 ? 0 : bufferedMs)),
            ],
      isBuffering: event['buffering'] as bool? ?? value.isBuffering,
      isPlaying: event['playing'] as bool? ?? value.isPlaying,
      isCompleted: event['ended'] as bool? ?? false,
    );
  }

  @override
  Future<void> play() async {
    if (!value.isInitialized) return;
    if (value.duration > Duration.zero && value.position >= value.duration) {
      await seekTo(Duration.zero);
    }
    value = value.copyWith(isPlaying: true, isCompleted: false);
    await _send('play');
  }

  @override
  Future<void> pause() async {
    if (!value.isInitialized) return;
    value = value.copyWith(isPlaying: false);
    await _send('pause');
  }

  @override
  Future<void> seekTo(Duration position) async {
    if (!value.isInitialized) return;
    final Duration clamped = position < Duration.zero
        ? Duration.zero
        : (value.duration > Duration.zero && position > value.duration)
        ? value.duration
        : position;
    value = value.copyWith(position: clamped, isCompleted: false);
    await _send('seek', {'positionMs': clamped.inMilliseconds});
  }

  @override
  Future<void> setVolume(double volume) async {
    final double clamped = volume.clamp(0.0, 1.0);
    value = value.copyWith(volume: clamped);
    if (!_opened) return;
    await _send('setVolume', {'volume': clamped});
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    if (speed <= 0) {
      throw ArgumentError.value(speed, 'speed', 'Playback speed must be greater than 0');
    }
    value = value.copyWith(playbackSpeed: speed);
    if (!_opened) return;
    await _send('setSpeed', {'speed': speed});
  }

  @override
  Future<void> setLooping(bool looping) async {
    value = value.copyWith(isLooping: looping);
    if (!_opened) return;
    await _send('setLooping', {'loop': looping});
  }

  Future<void> _send(String name, [Map<String, Object?> args = const {}]) {
    return onCommand(name, args);
  }

  @override
  Future<void> dispose() async {
    _opened = false;
    if (!_nativeDisposed) {
      _nativeDisposed = true;
      try {
        await onCommand('dispose', {});
      } catch (_) {}
    }
    await super.dispose();
  }
}
