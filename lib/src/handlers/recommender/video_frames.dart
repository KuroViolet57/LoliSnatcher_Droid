import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:get_it/get_it.dart';
import 'package:image/image.dart' as img;
import 'package:media_kit/media_kit.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/image_tagger_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/look_model_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/model_work.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/widgets/video/media_kit_player_view.dart';

/// What the frame service needs from a player: the pooled media_kit player
/// in the app, a fake in tests.
abstract class FrameTarget {
  bool get disposed;
  bool get playing;
  bool get hasVideo;
  Future<void> command(List<String> args);
  Future<String> getProperty(String name);
}

typedef FrameLookup = ({FrameTarget target, bool Function() stillShowing})? Function(String url);

/// The pooled media_kit player as a [FrameTarget]. Commands go through
/// media_kit's normal `command()` (a correctly built argument list, sent with
/// `mpv_command_async`), never through its `screenshot()`, whose argument
/// list is too short for mpv (media_kit 1.2.6, issues #569/#1222/#1075).
class MediaKitFrameTarget implements FrameTarget {
  MediaKitFrameTarget(this.player);

  final Player player;

  NativePlayer? get _native {
    final PlatformPlayer? p = player.platform;
    return p is NativePlayer ? p : null;
  }

  @override
  bool get disposed => _native?.disposed ?? true;

  @override
  bool get playing => player.state.playing;

  @override
  bool get hasVideo => (player.state.width ?? 0) > 0;

  @override
  Future<void> command(List<String> args) {
    final NativePlayer? n = _native;
    if (n == null) throw StateError('not a native media_kit player');
    return n.command(args);
  }

  @override
  Future<String> getProperty(String name) {
    final NativePlayer? n = _native;
    if (n == null) throw StateError('not a native media_kit player');
    return n.getProperty(name);
  }
}

class _Kept {
  final List<Uint8List> frames = [];
  final List<Float32List> vectors = [];
  DateTime? lastAt;
  int failures = 0;
}

/// Frames from the playing video (r76).
///
/// While a video is the one on screen in the viewer, mpv is asked to write
/// the frame it shows to a file (`screenshot-to-file <path> video`: mpv
/// takes the frame on its own worker thread and writes a JPEG, then
/// replies). The first frame comes after [firstDelay], then one every
/// [gap] while the video plays, [maxFrames] at most. The frames replace the
/// preview picture: their average look vector is stored for the video
/// (For You, boards), the board openers use the frame on screen, and the
/// tagger reads them for reactions. A player being closed cannot be reached:
/// media_kit marks it disposed first and destroys it 5 s later, and a
/// disposed player refuses commands; a player the pool moved to another
/// video meanwhile has its frame thrown away.
class VideoFrames {
  static VideoFrames get instance => GetIt.instance<VideoFrames>();

  static VideoFrames register() {
    if (!GetIt.instance.isRegistered<VideoFrames>()) {
      GetIt.instance.registerSingleton(VideoFrames());
    }
    return instance;
  }

  static void unregister() {
    if (GetIt.instance.isRegistered<VideoFrames>()) {
      instance.detach();
      GetIt.instance.unregister<VideoFrames>();
    }
  }

  static VideoFrames? get maybe => GetIt.instance.isRegistered<VideoFrames>() ? instance : null;

  static const String className = 'VideoFrames';

  /// Frames are kept at this size on their long side.
  static const int maxSide = 512;

  /// How many videos' frames are kept in memory.
  static const int keepVideos = 24;

  /// A video whose player failed this many times is left alone.
  static const int maxFailures = 4;

  // Seams and knobs, replaced in tests.
  FrameLookup lookup = _mediaKitLookup;
  bool Function() lookWanted = _defaultLookWanted;
  bool Function() taggerWanted = _defaultTaggerWanted;
  Future<Float32List> Function(Uint8List jpeg) lookOf = _defaultLookOf;
  Future<void> Function(BooruItem item, Float32List v) storeLook = _defaultStoreLook;

  /// r77: a viewer is really on screen (no page, dialog or sheet over it) and
  /// the app is in the foreground.
  bool Function() onScreen = _defaultOnScreen;

  /// r77: no touch, scroll or page change for [ModelWork.quiet].
  bool Function() quiet = _defaultQuiet;
  Duration firstDelay = const Duration(milliseconds: 2500);
  Duration gap = const Duration(seconds: 6);
  Duration tick = const Duration(seconds: 1);
  Duration requestTimeout = const Duration(seconds: 3);
  int maxFrames = 5;
  Directory? frameDirOverride;

  final LinkedHashMap<String, _Kept> _kept = LinkedHashMap();
  final Set<String> _decoderLogged = {};
  void Function()? _unlisten;
  Timer? _timer;
  BooruItem? _current;
  DateTime _since = DateTime.now();
  Future<Uint8List?>? _inFlight;
  int _seq = 0;
  bool _embedWarned = false;

  SettingsHandler get _settings => SettingsHandler.instance;

  static String keyOf(BooruItem item) => item.postURL.isNotEmpty ? item.postURL : item.fileURL;

  /// Follows the viewer's current item. Through `addListener`, the way GetX's
  /// own widgets listen: GetX 5's `stream` stops feeding new listeners once
  /// its last stream listener cancels (its `onCancel` removes the feed).
  void attach() {
    _unlisten?.call();
    final current = ViewerHandler.instance.current;
    _unlisten = current.addListener(() => _onCurrent(current.value));
    _onCurrent(current.value);
  }

  void detach() {
    _unlisten?.call();
    _unlisten = null;
    _timer?.cancel();
    _timer = null;
    _current = null;
  }

  /// A video, not a doujin item, not hidden by the blacklist.
  bool qualifies(BooruItem item) =>
      item.fileURL.isNotEmpty && item.mediaType.value.isVideo && !DoujinDataHandler.isDoujinItem(item) && !item.isHidden;

  /// The switch is on and something reads the frames.
  bool get wanted => _settings.videoFrames && (lookWanted() || taggerWanted());

  /// The frames kept for [item], oldest first (512 px JPEGs).
  List<Uint8List> framesOf(BooruItem item) => List<Uint8List>.of(_kept[keyOf(item)]?.frames ?? const <Uint8List>[]);

  void _onCurrent(BooruItem? item) {
    _timer?.cancel();
    _timer = null;
    _current = item;
    _since = DateTime.now();
    if (item == null || !qualifies(item)) return;
    _timer = Timer.periodic(tick, (_) => unawaited(_tick(item)));
  }

  Future<void> _tick(BooruItem item) async {
    if (!identical(_current, item)) return;
    if (_inFlight != null || !wanted) return;
    final _Kept? k = _kept[keyOf(item)];
    if ((k?.frames.length ?? 0) >= maxFrames || (k?.failures ?? 0) >= maxFailures) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    final DateTime now = DateTime.now();
    if (now.difference(_since) < firstDelay) return;
    // r77: never under another page or with the app in the background, and not
    // while the user is touching or scrolling (a grab costs about a second of
    // mpv's time). frameNow, which the user asked for, skips these checks.
    if (!onScreen() || !quiet()) return;
    final DateTime? last = k?.lastAt;
    if (last != null && now.difference(last) < gap) return;
    final found = lookup(item.fileURL);
    // Not bound yet (the viewer's start delay): the next tick looks again.
    if (found == null) return;
    // Paused: the same picture again would teach nothing.
    if ((k?.frames.isNotEmpty ?? false) && !found.target.playing) return;
    await _take(item, found);
  }

  /// A fresh frame when the player shows [item], else the newest kept one;
  /// null with the switch off, for a non-video, or when there is neither.
  Future<Uint8List?> frameNow(BooruItem item) async {
    if (!_settings.videoFrames || !qualifies(item)) return null;
    final Future<Uint8List?>? pending = _inFlight;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
    final found = lookup(item.fileURL);
    if (found != null) {
      final Uint8List? fresh = await _take(item, found);
      if (fresh != null) return fresh;
    }
    final List<Uint8List> kept = _kept[keyOf(item)]?.frames ?? const <Uint8List>[];
    return kept.isEmpty ? null : kept.last;
  }

  Future<Uint8List?> _take(BooruItem item, ({FrameTarget target, bool Function() stillShowing}) found) {
    final Future<Uint8List?> f = _takeNow(item, found);
    _inFlight = f;
    return f.whenComplete(() {
      if (identical(_inFlight, f)) _inFlight = null;
    });
  }

  _Kept _keep(String key) {
    final _Kept k = _kept.remove(key) ?? _Kept();
    _kept[key] = k;
    while (_kept.length > keepVideos) {
      _kept.remove(_kept.keys.first);
    }
    return k;
  }

  Directory get _dir => frameDirOverride ?? Directory('${Directory.systemTemp.path}${Platform.pathSeparator}lolisnatcher_frames');

  Future<Uint8List?> _takeNow(BooruItem item, ({FrameTarget target, bool Function() stillShowing}) found) async {
    final String key = keyOf(item);
    final _Kept k = _keep(key);
    final FrameTarget t = found.target;
    if (t.disposed || !t.hasVideo) return null;
    if (_settings.altVideoPlayerVO.isMediacodecEmbed) {
      if (!_embedWarned) {
        _embedWarned = true;
        _log('look: no frames with the "mediacodec_embed" video output (mpv cannot read that picture back); the preview picture is used');
      }
      return null;
    }
    if (_decoderLogged.add(key)) await _logDecoder(t, item);
    final Directory dir = _dir;
    try {
      dir.createSync(recursive: true);
      _sweep(dir);
    } catch (_) {}
    final String path = '${dir.path}${Platform.pathSeparator}f${DateTime.now().microsecondsSinceEpoch}_${_seq++}.jpg';
    final Stopwatch sw = Stopwatch()..start();
    k.lastAt = DateTime.now();
    try {
      await t.command(['screenshot-to-file', path, 'video']).timeout(requestTimeout);
    } on TimeoutException {
      _failed(k, 'frame request timed out');
      _delete(path);
      return null;
    } catch (e) {
      _failed(k, 'the player gave no frame ($e)');
      _delete(path);
      return null;
    }
    if (!found.stillShowing()) {
      _failed(k, 'frame dropped, the player moved on');
      _delete(path);
      return null;
    }
    final File file = File(path);
    if (!file.existsSync() || file.lengthSync() == 0) {
      _failed(k, 'the player gave no frame (no file written)');
      _delete(path);
      return null;
    }
    final Uint8List raw = file.readAsBytesSync();
    _delete(path);
    final Uint8List? small = await compute(shrinkJpeg, (raw, maxSide));
    if (small == null) {
      _failed(k, 'the frame could not be read');
      return null;
    }
    k.failures = 0;
    final bool keep = k.frames.length < maxFrames;
    if (keep) k.frames.add(small);
    _log('look: frame ${k.frames.length}/$maxFrames of ${_name(item)} in ${sw.elapsedMilliseconds} ms (${raw.length ~/ 1024} KB from mpv)');
    if (keep && lookWanted()) {
      // r77: the looks model reads the frame as a background step, at a quiet
      // moment - and "Find posts like this" gets its frame without waiting
      // for that run.
      final List<Float32List> vectors = k.vectors;
      unawaited(
        ModelWork.instance.run('frame look', (bool lite) async {
          if (lite || item.isHidden) return;
          try {
            vectors.add(await lookOf(small));
            await storeLook(item, LookModelHandler.meanOf(vectors));
          } catch (e) {
            _log('look: the looks model could not read a frame: $e');
          }
        }),
      );
    }
    return small;
  }

  void _failed(_Kept k, String why) {
    k.failures++;
    _log('look: $why');
  }

  static void _delete(String path) {
    try {
      final File f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  /// Files a timed-out request wrote late.
  static void _sweep(Directory dir) {
    final DateTime cutoff = DateTime.now().subtract(const Duration(minutes: 1));
    for (final FileSystemEntity e in dir.listSync()) {
      try {
        if (e is File && e.lastModifiedSync().isBefore(cutoff)) e.deleteSync();
      } catch (_) {}
    }
  }

  Future<void> _logDecoder(FrameTarget t, BooruItem item) async {
    Future<String> read(String name) async {
      try {
        return await t.getProperty(name);
      } catch (_) {
        return '';
      }
    }

    final String hw = await read('hwdec-current');
    final String vo = await read('current-vo');
    final String codec = await read('video-codec');
    _log('video: ${decoderLine(hw, vo, codec)} (${_name(item)})');
  }

  /// "decoder no (software) · output gpu · codec h264".
  static String decoderLine(String hw, String vo, String codec) {
    final String h = hw.trim();
    final String decoder = h.isEmpty || h == 'no' ? 'no (software)' : h;
    return 'decoder $decoder · output ${vo.trim().isEmpty ? '?' : vo.trim()} · codec ${codec.trim().isEmpty ? '?' : codec.trim()}';
  }

  static String _name(BooruItem item) {
    final String url = item.postURL.isNotEmpty ? item.postURL : item.fileURL;
    return url.length > 80 ? '…${url.substring(url.length - 79)}' : url;
  }

  static void _log(String message) => Logger.Inst().log(message, className, 'frames', LogTypes.booruHandlerInfo);

  /// A frame shrunk to [args.$2] px on its long side (JPEG); a small one
  /// comes back as it is; null when it is not a picture.
  static Uint8List? shrinkJpeg((Uint8List, int) args) {
    final (Uint8List bytes, int limit) = args;
    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      return null;
    }
    if (decoded == null) return null;
    final int longSide = math.max(decoded.width, decoded.height);
    if (longSide <= limit) return bytes;
    final double scale = limit / longSide;
    final img.Image small = img.copyResize(
      decoded,
      width: math.max(1, (decoded.width * scale).round()),
      height: math.max(1, (decoded.height * scale).round()),
      interpolation: img.Interpolation.average,
    );
    return img.encodeJpg(small, quality: 88);
  }

  // ── defaults ──

  static ({FrameTarget target, bool Function() stillShowing})? _mediaKitLookup(String url) {
    final found = MediaKitFrameSource.showing(url);
    if (found == null) return null;
    return (target: MediaKitFrameTarget(found.player), stillShowing: found.stillShowing);
  }

  static bool _defaultLookWanted() => LookModelHandler.maybe?.enabled ?? false;

  static bool _defaultOnScreen() {
    final AppLifecycleState? s = WidgetsBinding.instance.lifecycleState;
    return ViewerHandler.instance.viewerOnScreen && (s == null || s == AppLifecycleState.resumed);
  }

  static bool _defaultQuiet() => ActivityClock.instance.quietFor(ModelWork.instance.quiet);

  static bool _defaultTaggerWanted() => (ImageTaggerHandler.maybe?.enabled ?? false) && SettingsHandler.instance.taggerOnReactions;

  static Future<Float32List> _defaultLookOf(Uint8List jpeg) => LookModelHandler.instance.imageVector(jpeg);

  static Future<void> _defaultStoreLook(BooruItem item, Float32List v) => LookModelHandler.instance.putItemVector(item, v);
}
