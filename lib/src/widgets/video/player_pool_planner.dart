/// How the video player pool juggles a fixed set of players (r64).
///
/// Players are a scarce resource: building one creates a decoder, a surface
/// and a texture, and destroying one tears all of that down. Doing both while
/// the user swipes cost 42 creates and 38 disposes in 25 seconds of swiping
/// and showed up as stutter. So the pool keeps its slots and re-points a free
/// one at the next video instead (mpv opens another file on the same player).
///
/// The decision is pure so it can be tested without a native player.
library;

enum PoolAction {
  /// The slot already holds this video: hand it back, buffer and all.
  reuse,

  /// Under capacity: build a player.
  create,

  /// At capacity: open this video on a free slot's existing player.
  rebind,
}

/// What the pool knows about one slot when it decides.
class PoolSlot {
  const PoolSlot({
    required this.url,
    required this.refCount,
    required this.lastUsedTick,
    this.hasError = false,
    this.options = '',
  });

  final String url;

  /// How many widgets are showing it. Above zero, the slot is untouchable.
  final int refCount;

  /// Bumped every time the slot is handed out; the smallest is the oldest.
  final int lastUsedTick;

  /// The player reported an error on its current file (dead session cookie,
  /// blocked host); it must be opened again rather than handed back.
  final bool hasError;

  /// The engine settings the player was built with (vo | hwdec | hardware
  /// acceleration). A slot now outlives a change to them, so one built with
  /// the old settings has to be rebuilt rather than re-pointed.
  final String options;

  bool get isFree => refCount <= 0;
}

class PoolPlan {
  const PoolPlan(this.action, {this.slot});

  final PoolAction action;

  /// The slot to reuse or re-point; null when a player is to be built.
  final int? slot;
}

class PlayerPoolPlanner {
  const PlayerPoolPlanner._();

  static PoolPlan plan({
    required List<PoolSlot> slots,
    required String url,
    required int capacity,
  }) {
    for (int i = 0; i < slots.length; i++) {
      if (slots[i].url != url) continue;
      if (!slots[i].hasError) return PoolPlan(PoolAction.reuse, slot: i);
      // Errored: open it again on the same player, if nobody is watching it.
      if (slots[i].isFree) return PoolPlan(PoolAction.rebind, slot: i);
    }

    if (slots.length < capacity) return const PoolPlan(PoolAction.create);

    final int? oldestFree = _oldestFree(slots);
    if (oldestFree != null) return PoolPlan(PoolAction.rebind, slot: oldestFree);

    // Every slot is on screen (preloaded neighbours, a split view): building
    // one more beats stealing a player someone is watching. [disposable]
    // names it for disposal once it frees up.
    return const PoolPlan(PoolAction.create);
  }

  /// Slots to dispose once the pool is over [capacity]: the oldest idle ones
  /// first. Slots being watched are never named.
  static List<int> disposable({
    required List<PoolSlot> slots,
    required int capacity,
  }) {
    final int over = slots.length - capacity;
    if (over <= 0) return const [];

    final List<int> free = [
      for (int i = 0; i < slots.length; i++)
        if (slots[i].isFree) i,
    ]..sort((a, b) => slots[a].lastUsedTick.compareTo(slots[b].lastUsedTick));

    return free.take(over).toList()..sort();
  }

  /// Free slots built with other engine settings than [options]: they are
  /// disposed instead of re-pointed, so a change in Settings → Video reaches
  /// the next video. Slots on screen are left alone.
  static List<int> staleOptions({
    required List<PoolSlot> slots,
    required String options,
  }) => [
    for (int i = 0; i < slots.length; i++)
      if (slots[i].isFree && slots[i].options != options) i,
  ];

  static int? _oldestFree(List<PoolSlot> slots) {
    int? best;
    int? bestTick;
    for (int i = 0; i < slots.length; i++) {
      if (!slots[i].isFree) continue;
      final int tick = slots[i].lastUsedTick;
      if (bestTick == null || tick < bestTick) {
        best = i;
        bestTick = tick;
      }
    }
    return best;
  }
}
