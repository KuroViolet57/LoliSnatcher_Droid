part of '../media_kit_player_view.dart';

/// A pooled player slot. Refcounted: many widgets *could* share the same URL,
/// though in practice the PageView gives each item a unique URL.
///
/// r64: the slot outlives the video it holds - [url] changes when a free slot
/// is re-pointed at another file - so a swipe no longer destroys a decoder,
/// a surface and a texture just to build them again.
class _PooledPlayer {
  _PooledPlayer({
    required this.url,
    required this.player,
    required this.controller,
  });

  String url;

  /// The engine settings this player was built with (see [PoolSlot.options]).
  String options = '';
  final Player player;
  final VideoController controller;
  int refCount = 0;
  int lastUsedTick = 0;
  // Set per acquire() call so callers know whether they got a warm buffer.
  bool wasReused = false;
  // Set when the player reported an error (network block, expired session
  // cookie, ...). An errored entry is rebuilt with fresh headers on the next
  // acquire instead of being reused broken.
  bool hasError = false;
  // Cancelled on evict/reset/dispose — the pool owns the lifecycle.
  // ignore: cancel_subscriptions
  StreamSubscription<String>? errorSub;
  // r77: mpv's fatal messages (only error level reaches the error stream).
  StreamSubscription<PlayerLog>? logSub;

  /// r77: when a frame was last asked of this player (on
  /// [MediaKitPlayerView.monoNow]'s clock); mpv's screenshot messages right
  /// after it are not player errors.
  Duration? lastGrabAt;

  /// r77: fullscreen routes showing this player outside the widgets' counts;
  /// while any does, the slot counts as in use.
  int fullscreenHolds = 0;

  /// r77: built to replace a player that broke on this video.
  bool replaced = false;

  void cancelSubs() {
    errorSub?.cancel();
    logSub?.cancel();
  }
}

/// Global pool of player slots. Survives widget disposal so scrolling back to
/// a neighbour video resumes with its buffer intact instead of restarting the
/// download. Capacity = [SettingsHandler.mediaKitMaxPlayers].
///
/// r64: at capacity the oldest idle slot is re-pointed at the new video
/// ([PlayerPoolPlanner]) instead of being destroyed and rebuilt; only slots
/// ABOVE the capacity are disposed, and only once nobody is watching them.
class _MediaKitPlayerPool {
  _MediaKitPlayerPool._();
  static final _MediaKitPlayerPool instance = _MediaKitPlayerPool._();

  final List<_PooledPlayer> _slots = [];
  int _tick = 0;
  bool _initialized = false;

  Future<_PooledPlayer> acquire({
    required String url,
    required Map<String, String> headers,
  }) async {
    if (!_initialized) {
      MediaKit.ensureInitialized();
      // r59: tells our copy of media_kit_video how big the surface may be.
      VideoSurfaceCap.install();
      _initialized = true;
    }

    final settings = SettingsHandler.instance;
    final String options = _optionsSignature(settings);
    _disposeStaleOptions(options);
    final PoolPlan plan = PlayerPoolPlanner.plan(
      slots: _slotStates(),
      url: url,
      capacity: settings.mediaKitMaxPlayers,
    );

    if (plan.action == PoolAction.reuse) {
      final _PooledPlayer entry = _slots[plan.slot!];
      entry.refCount++;
      entry.lastUsedTick = ++_tick;
      entry.wasReused = true;
      PerfTrace.instance.event('video.reuse', url);
      return entry;
    }

    bool replacing = false;
    if (plan.action == PoolAction.replace) {
      // r77: the player that broke on this video is disposed; a new one opens
      // it with the headers just read (re-opening it on the broken player was
      // seen to leave the video without a picture).
      final _PooledPlayer old = _slots.removeAt(plan.slot!);
      PerfTrace.instance.event('video.replace', url);
      Logger.Inst().log('media_kit: replacing a broken player for $url', '_MediaKitPlayerPool', 'acquire', LogTypes.booruItemLoad);
      try {
        old.cancelSubs();
        unawaited(old.player.dispose());
      } catch (_) {}
      replacing = true;
    }

    if (plan.action == PoolAction.rebind) {
      // r64: the same player opens another file. Its decoder, surface and
      // texture stay; nothing is torn down mid-swipe. The playlist mode and
      // the mpv cache properties were set when the slot was built and hold.
      final _PooledPlayer entry = _slots[plan.slot!];
      entry.url = url;
      entry.hasError = false;
      entry.wasReused = false;
      entry.refCount = 1;
      entry.lastUsedTick = ++_tick;
      try {
        // A re-pointed player must start like a fresh one: the long-press
        // speed boost and the volume the last video was left at belong to
        // that video, not this one.
        await entry.player.setRate(1);
        await entry.player.setVolume(100);
        await entry.player.open(Media(url, httpHeaders: headers), play: false);
      } catch (e, s) {
        entry.hasError = true;
        Logger.Inst().log(
          'media_kit player rebind failed for $url: $e',
          '_MediaKitPlayerPool',
          'acquire',
          LogTypes.exception,
          s: s,
        );
      }
      PerfTrace.instance.event('video.rebind', url);
      return entry;
    }

    final player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 64 * 1024 * 1024,
        logLevel: MPVLogLevel.error,
      ),
    );
    final controller = VideoController(
      player,
      configuration: MediaKitEngineOptions.videoController(settings),
    );

    await player.open(Media(url, httpHeaders: headers), play: false);
    // PlaylistMode.single => mpv loop-file=yes: loops THIS file in place
    // without re-running the playlist. PlaylistMode.loop (loop-playlist=yes)
    // re-inits the demuxer at the loop point, which showed up as a 1-2s
    // buffering spinner and an occasional cache reset on every loop.
    await player.setPlaylistMode(PlaylistMode.single);

    // Tune libmpv cache so we don't underrun mid-clip on jittery CDNs and so
    // we keep enough back-buffer to seek-back without re-downloading. Disk
    // cache sits next to the app files dir when SettingsHandler.path is set.
    try {
      final platform = player.platform;
      if (platform is NativePlayer) {
        final String path = settings.path.trim();
        final String? cacheDir = path.isEmpty ? null : '${path}mpv_cache';
        for (final entry in MediaKitEngineOptions.nativeProperties(cacheDir: cacheDir).entries) {
          await platform.setProperty(entry.key, entry.value);
        }
      }
    } catch (e, s) {
      Logger.Inst().log(
        'mpv setProperty failed: $e',
        '_MediaKitPlayerPool',
        'acquire',
        LogTypes.exception,
        s: s,
      );
    }

    final entry = _PooledPlayer(url: url, player: player, controller: controller)
      ..refCount = 1
      ..lastUsedTick = ++_tick
      ..wasReused = false
      ..replaced = replacing
      ..options = options;
    // Cancelled on evict/reset/dispose — the pool owns the lifecycle.
    // ignore: cancel_subscriptions
    entry.errorSub = player.stream.error.listen((message) {
      // r77: a frame grab that came before mpv drew anything: not an error.
      if (MediaKitPlayerView.isScreenshotNoise(message, lastGrabAt: entry.lastGrabAt, now: MediaKitPlayerView.monoNow())) {
        Logger.Inst().log('look: mpv had no picture for a frame yet (${entry.url})', '_MediaKitPlayerPool', 'errorStream', LogTypes.booruHandlerInfo);
        return;
      }
      // Codec grumbles aren't fatal (playback usually continues) — don't
      // condemn the entry to a rebuild over them.
      if (!message.toLowerCase().contains('codec')) {
        entry.hasError = true;
      }
      // r77: the address this player shows now, not the one it was built for.
      Logger.Inst().log(
        'media_kit player error for ${entry.url}: $message',
        '_MediaKitPlayerPool',
        'errorStream',
        LogTypes.booruItemLoad,
      );
    });
    entry.logSub = player.stream.log.listen((PlayerLog l) {
      if (l.level != 'fatal') return;
      Logger.Inst().log('mpv fatal (${l.prefix}) for ${entry.url}: ${l.text.trim()}', '_MediaKitPlayerPool', 'log', LogTypes.booruItemLoad);
    });
    PerfTrace.instance.event('video.create', url);
    _slots.add(entry);
    _disposeOverflow();
    return entry;
  }

  List<PoolSlot> _slotStates() => [
    for (final _PooledPlayer e in _slots)
      PoolSlot(
        url: e.url,
        refCount: e.refCount,
        lastUsedTick: e.lastUsedTick,
        hasError: e.hasError,
        options: e.options,
      ),
  ];

  /// vo | hwdec | hardware acceleration, as the slot was built with.
  static String _optionsSignature(SettingsHandler settings) =>
      '${settings.altVideoPlayerVO.toJson()}|${settings.altVideoPlayerHWDEC.toJson()}|${settings.altVideoPlayerHwAccel}';

  /// Drops idle players built before the engine settings changed, so the new
  /// ones take effect on the next video instead of living on in a slot.
  void _disposeStaleOptions(String options) {
    final List<int> stale = PlayerPoolPlanner.staleOptions(slots: _slotStates(), options: options);
    for (final int i in stale.reversed) {
      final _PooledPlayer e = _slots.removeAt(i);
      try {
        e.cancelSubs();
        e.player.dispose();
      } catch (_) {}
    }
  }

  void markErrored(String url) {
    for (final _PooledPlayer e in _slots) {
      if (e.url == url) e.hasError = true;
    }
  }

  /// Drops every idle player and flags the in-use ones as errored, so all
  /// videos rebuild with freshly-read cookies on their next acquire. Used by
  /// the soft-refresh button after e.g. re-solving a Cloudflare challenge.
  void reset() {
    final List<_PooledPlayer> idle = _slots.where((e) => e.refCount <= 0).toList();
    for (final _PooledPlayer e in idle) {
      _slots.remove(e);
      try {
        e.cancelSubs();
        e.player.dispose();
      } catch (_) {}
    }
    for (final _PooledPlayer e in _slots) {
      e.hasError = true;
    }
  }

  /// r77: by identity, not by address - during a replace, or after an
  /// errored slot stayed on screen, two slots can hold the same address.
  void release(_PooledPlayer entry) {
    if (!_slots.contains(entry)) return;
    if (entry.refCount > 0) entry.refCount--;
    entry.lastUsedTick = ++_tick;
    if (entry.refCount == 0) {
      _logDropped(entry);
      // Idle but kept warm in the pool. Pause to free decode CPU; the buffer
      // is preserved by libmpv until the slot is re-pointed.
      try {
        entry.player.pause();
      } catch (_) {}
    }
    _disposeOverflow();
  }

  /// r77: fullscreen shows [player] outside the widgets' counts; while it
  /// does, its slot is in use - never replaced, re-pointed or disposed.
  void holdForFullscreen(Player player) {
    for (final _PooledPlayer e in _slots) {
      if (!identical(e.player, player)) continue;
      e.refCount++;
      e.fullscreenHolds++;
    }
  }

  void endFullscreenHold(Player player) {
    for (final _PooledPlayer e in List<_PooledPlayer>.of(_slots)) {
      if (!identical(e.player, player) || e.fullscreenHolds <= 0) continue;
      e.fullscreenHolds--;
      release(e);
    }
  }

  /// r77: how many frames mpv dropped while this video played, read when it
  /// is left - with the trace, it shows whether playback itself stuttered.
  void _logDropped(_PooledPlayer entry) {
    final platform = entry.player.platform;
    if (platform is! NativePlayer || entry.player.state.position <= Duration.zero) return;
    final String url = entry.url;
    unawaited(() async {
      try {
        final String output = await platform.getProperty('frame-drop-count');
        final String decoder = await platform.getProperty('decoder-frame-drop-count');
        final String? line = MediaKitPlayerView.droppedLine(output, decoder, url);
        if (line == null) return;
        PerfTrace.instance.event('video.drops', '$output/$decoder');
        Logger.Inst().log(line, '_MediaKitPlayerPool', 'release', LogTypes.booruItemLoad);
      } catch (_) {}
    }());
  }

  /// Only slots ABOVE the pool's size are destroyed (r64): inside it, a slot
  /// is re-pointed at the next video instead. A slot on screen is never
  /// touched, so shrinking the setting takes effect as videos are released.
  void _disposeOverflow() {
    final List<int> gone = PlayerPoolPlanner.disposable(
      slots: _slotStates(),
      capacity: SettingsHandler.instance.mediaKitMaxPlayers,
    );
    for (final int i in gone.reversed) {
      final _PooledPlayer e = _slots.removeAt(i);
      PerfTrace.instance.event('video.dispose', e.url);
      try {
        e.cancelSubs();
        e.player.dispose();
      } catch (_) {}
    }
  }
}

/// r76: which pooled player is showing a video right now, for reading its
/// frames (VideoFrames). Read-only: nothing here changes the pool or a
/// player. [stillShowing] tells afterwards whether that player still holds
/// the same video (the pool may re-point an idle player at another one).
class MediaKitFrameSource {
  const MediaKitFrameSource._();

  /// r77: a frame is about to be asked of [player]; its screenshot messages
  /// in the next few seconds are its answer, not a player error.
  static void noteGrab(Player player) {
    for (final _PooledPlayer e in _MediaKitPlayerPool.instance._slots) {
      if (identical(e.player, player)) e.lastGrabAt = MediaKitPlayerView.monoNow();
    }
  }

  static ({Player player, bool Function() stillShowing})? showing(String url) {
    for (final _PooledPlayer e in _MediaKitPlayerPool.instance._slots) {
      // r77: an idle pooled player (refCount 0) is paused off screen.
      if (e.url != url || e.hasError || e.refCount <= 0) continue;
      return (
        player: e.player,
        stillShowing: () => e.url == url && !e.hasError && _MediaKitPlayerPool.instance._slots.contains(e),
      );
    }
    return null;
  }
}
