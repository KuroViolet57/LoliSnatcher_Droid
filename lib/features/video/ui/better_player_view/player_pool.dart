part of '../better_player_view.dart';

/// Global LRU registry of live [BetterPlayerController]s across every
/// [BetterPlayerView] currently on screen.
///
/// Android only provides a handful of hardware video decoders to any one app
/// process; once exhausted, MediaCodec refuses to attach a new decoder and
/// the next video either fails to start or — worse — the native layer aborts
/// the whole process (a hard crash Dart can't catch). The pool keeps the live
/// decoder count strictly bounded.
///
/// Crucial ordering: we evict BEFORE the caller allocates its new controller
/// (see [makeRoomFor]), so we never briefly hold `_maxAlive + 1` decoders.
/// The earlier version evicted *after* registering the freshly-built
/// controller, which meant a momentary 3-decoder spike — and that 3rd
/// hardware decoder allocation is exactly what triggered the native abort
/// when scrolling quickly through videos.
class _BetterPlayerPool {
  // 1 = only the visible video ever holds a hardware decoder. Safest against
  // MediaCodec exhaustion; scroll-back re-inits from the (fast) byte cache.
  static const int _maxAlive = 1;
  static final List<_BetterPlayerViewState> _lru = [];

  /// Evict down so there's room for one more controller. Call this BEFORE
  /// constructing a new BetterPlayerController.
  static void makeRoomFor(_BetterPlayerViewState s) {
    _lru.remove(s);
    while (_lru.length >= _maxAlive) {
      final old = _lru.removeAt(0);
      old._forceDisposeFromPool();
    }
  }

  static void register(_BetterPlayerViewState s) {
    _lru.remove(s);
    _lru.add(s);
  }

  static void unregister(_BetterPlayerViewState s) {
    _lru.remove(s);
  }

  /// Whether a live controller other than [s]'s belongs to the page on screen.
  static bool holdsViewedOtherThan(_BetterPlayerViewState s) =>
      _lru.any((o) => !identical(o, s) && o.mounted && o.widget.isViewed);

  static void touch(_BetterPlayerViewState s) {
    if (!_lru.contains(s)) return;
    _lru.remove(s);
    _lru.add(s);
  }

  /// Soft-refresh: tear down every live controller so videos re-init with
  /// freshly-read cookies (e.g. after re-solving a Cloudflare challenge).
  static void resetAll() {
    for (final s in [..._lru]) {
      s._forceDisposeFromPool();
    }
    _lru.clear();
  }
}

/// Process-wide serialization gate for ExoPlayer decoder lifecycle.
///
/// ExoPlayer's `release()` is async on the native side — `dispose()` returns
/// to Dart immediately while MediaCodec is still tearing the decoder down.
/// During a fast scroll, multiple `_init`s can run concurrently, so a new
/// decoder gets allocated while a previous one is mid-release. That overlap
/// is what aborts the process (a hard native crash Dart can't catch).
///
/// Every create/teardown sequence runs through [run], which chains operations
/// so only ONE is ever in flight across the whole app. No interleaving →
/// no concurrent allocate-while-releasing → no abort.
class _DecoderGate {
  static Future<void> _tail = Future<void>.value();

  static Future<void> run(Future<void> Function() action) {
    final completer = Completer<void>();
    final prev = _tail;
    _tail = completer.future;
    prev.whenComplete(() async {
      try {
        await action();
      } finally {
        completer.complete();
      }
    });
    return completer.future;
  }
}
