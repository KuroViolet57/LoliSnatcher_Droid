import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/widgets/video/player_pool_planner.dart';

/// r64: video players are a scarce resource, so the pool stops destroying and
/// building them while you swipe. It keeps a fixed set of slots and re-points
/// a free one at the next video instead (mpv opens another file on the same
/// player, keeping its texture, surface and decoder setup).
void main() {
  PoolSlot slot(
    String url, {
    int refCount = 0,
    int tick = 0,
    bool hasError = false,
    String options = 'gpu|auto-safe|true',
  }) => PoolSlot(
    url: url,
    refCount: refCount,
    lastUsedTick: tick,
    hasError: hasError,
    options: options,
  );

  test('a slot already holding the video is reused, buffer and all', () {
    final PoolPlan plan = PlayerPoolPlanner.plan(
      slots: [slot('a', tick: 1), slot('b', tick: 2)],
      url: 'a',
      capacity: 4,
    );
    expect(plan.action, PoolAction.reuse);
    expect(plan.slot, 0);
  });

  test('under capacity, a new player is built', () {
    final PoolPlan plan = PlayerPoolPlanner.plan(
      slots: [slot('a', tick: 1)],
      url: 'b',
      capacity: 4,
    );
    expect(plan.action, PoolAction.create);
    expect(plan.slot, isNull);
  });

  test('at capacity, the longest-unused free slot is re-pointed instead of destroyed', () {
    final PoolPlan plan = PlayerPoolPlanner.plan(
      slots: [
        slot('a', tick: 7, refCount: 1), // on screen
        slot('b', tick: 2), // idle, oldest
        slot('c', tick: 5), // idle, newer
        slot('d', tick: 6, refCount: 1),
      ],
      url: 'e',
      capacity: 4,
    );
    expect(plan.action, PoolAction.rebind);
    expect(plan.slot, 1, reason: 'the oldest idle slot, not the one on screen');
  });

  test('r77: a slot that errored on this video is replaced by a new player, never re-opened or handed back', () {
    final PoolPlan plan = PlayerPoolPlanner.plan(
      slots: [slot('a', tick: 1, hasError: true), slot('b', tick: 2)],
      url: 'a',
      capacity: 4,
    );
    expect(plan.action, PoolAction.replace);
    expect(plan.slot, 0, reason: 'that slot is disposed and a fresh player opens the video with the headers we were just given');
  });

  test('r77: at capacity an errored idle slot is replaced, not re-pointed at another video', () {
    final PoolPlan plan = PlayerPoolPlanner.plan(
      slots: [slot('a', tick: 1, hasError: true), slot('b', tick: 2, refCount: 1)],
      url: 'c',
      capacity: 2,
    );
    expect(plan.action, PoolAction.replace);
    expect(plan.slot, 0);
  });

  test('r77: at capacity a healthy idle slot is still re-pointed', () {
    final PoolPlan plan = PlayerPoolPlanner.plan(
      slots: [slot('a', tick: 1), slot('b', tick: 2, refCount: 1)],
      url: 'c',
      capacity: 2,
    );
    expect(plan.action, PoolAction.rebind);
    expect(plan.slot, 0);
  });

  test('a slot that errored but is still on screen is left alone and a new one is built', () {
    final PoolPlan plan = PlayerPoolPlanner.plan(
      slots: [slot('a', tick: 1, refCount: 1, hasError: true)],
      url: 'a',
      capacity: 4,
    );
    expect(plan.action, PoolAction.create);
  });

  test('when every slot is on screen, a new player is built rather than stealing one', () {
    final PoolPlan plan = PlayerPoolPlanner.plan(
      slots: [
        slot('a', tick: 1, refCount: 1),
        slot('b', tick: 2, refCount: 2),
      ],
      url: 'c',
      capacity: 2,
    );
    expect(plan.action, PoolAction.create, reason: 'never re-point a player someone is watching');
  });

  test('slots above capacity are named for disposal once they are free', () {
    final List<PoolSlot> slots = [
      slot('a', tick: 9, refCount: 1),
      slot('b', tick: 3),
      slot('c', tick: 4),
      slot('d', tick: 5, refCount: 1),
    ];
    expect(PlayerPoolPlanner.disposable(slots: slots, capacity: 4), isEmpty);
    expect(
      PlayerPoolPlanner.disposable(slots: slots, capacity: 3),
      [1],
      reason: 'one too many: the oldest idle slot goes, the watched ones stay',
    );
    expect(
      PlayerPoolPlanner.disposable(slots: slots, capacity: 2),
      [1, 2],
      reason: 'oldest idle first',
    );
    expect(
      PlayerPoolPlanner.disposable(slots: slots, capacity: 1),
      [1, 2],
      reason: 'the two on screen are never disposed under it',
    );
  });

  group('players built with other engine settings', () {
    // A slot now outlives a change to Settings > Video (vo / hwdec / hardware
    // acceleration), because it is re-pointed instead of rebuilt. A free slot
    // built with the old settings has to go, or the change would never apply.
    test('free slots built with other settings are named for disposal', () {
      final List<PoolSlot> slots = [
        slot('a', tick: 1, options: 'gpu|auto-safe|true'),
        slot('b', tick: 2, options: 'libmpv|mediacodec|false'),
        slot('c', tick: 3, refCount: 1, options: 'libmpv|mediacodec|false'),
      ];

      expect(
        PlayerPoolPlanner.staleOptions(slots: slots, options: 'gpu|auto-safe|true'),
        [1],
        reason: 'the idle one with the old settings; the watched one is left alone',
      );
      expect(PlayerPoolPlanner.staleOptions(slots: slots, options: 'libmpv|mediacodec|false'), [0]);
    });

    test('nothing to do when every slot matches', () {
      expect(
        PlayerPoolPlanner.staleOptions(
          slots: [slot('a', tick: 1), slot('b', tick: 2)],
          options: 'gpu|auto-safe|true',
        ),
        isEmpty,
      );
    });
  });
}
