import 'package:flutter/foundation.dart';

/// What the recommender is told about, and what each event teaches it.
///
/// One event = one item, one kind, sometimes a value (seconds on screen,
/// fraction of a book read). [rewardFor] turns that into a training label and
/// a weight: how sure the signal is. Explicit acts (a favourite, a finished
/// book, a blacklisted tag) weigh several times a passing view; a glance
/// in between teaches nothing at all.
enum InteractionKind {
  /// The item was on screen in a viewer; value = seconds.
  view,

  /// Flicked past in under 1.5 s.
  skip,
  favourite,
  unfavourite,
  collect,
  snatch,

  /// A search; the "item" is the searched terms.
  search,

  /// A tag preview opened; the "item" is the tag.
  tagPreview,

  /// A doujin detail page opened.
  open,

  /// Pages read; value = fraction of the book reached.
  read,

  /// The last page reached.
  finish,
  follow,
  star,
  blacklist,

  /// "Forget this" on a learned feature.
  forget,

  /// Shown by a recommendation surface; value carries nothing, the surface
  /// name travels beside it. Teaches nothing on its own.
  expose,

  /// Shown and passed over: the surface moved on and the item was never
  /// opened.
  exposeLapsed;

  static InteractionKind? fromName(String name) {
    for (final InteractionKind kind in values) {
      if (kind.name == name) return kind;
    }
    return null;
  }
}

/// One row of the recommender's log, as the database hands it back.
class InteractionRow {
  const InteractionRow({
    required this.id,
    required this.world,
    required this.itemKey,
    required this.host,
    required this.kind,
    required this.value,
    required this.at,
    required this.features,
  });

  final int id;
  final String world;
  final String itemKey;
  final String host;

  /// Null for a kind this build no longer knows.
  final InteractionKind? kind;
  final double value;
  final int at;
  final List<int> features;
}

@immutable
class Reward {
  const Reward({required this.positive, required this.weight});

  final bool positive;
  final double weight;

  @override
  bool operator ==(Object other) => other is Reward && other.positive == positive && other.weight == weight;

  @override
  int get hashCode => Object.hash(positive, weight);

  @override
  String toString() => 'Reward(${positive ? '+' : '-'}, w=$weight)';
}

/// The label and weight [kind] teaches, or null when it teaches nothing.
Reward? rewardFor(InteractionKind kind, {double value = 0}) {
  switch (kind) {
    case InteractionKind.favourite:
    case InteractionKind.collect:
    case InteractionKind.finish:
      return const Reward(positive: true, weight: 3);
    case InteractionKind.snatch:
    case InteractionKind.follow:
    case InteractionKind.star:
      return const Reward(positive: true, weight: 2);
    case InteractionKind.unfavourite:
    case InteractionKind.blacklist:
      return const Reward(positive: false, weight: 3);
    case InteractionKind.forget:
      return const Reward(positive: false, weight: 2);
    case InteractionKind.view:
      if (value >= 8) return const Reward(positive: true, weight: 1);
      if (value >= 3) return const Reward(positive: true, weight: 0.5);
      if (value >= 1.5) return null;
      return const Reward(positive: false, weight: 1);
    case InteractionKind.skip:
      return const Reward(positive: false, weight: 1);
    case InteractionKind.read:
      return value >= 0.5 ? const Reward(positive: true, weight: 2) : null;
    case InteractionKind.search:
    case InteractionKind.tagPreview:
    case InteractionKind.open:
      return const Reward(positive: true, weight: 0.5);
    case InteractionKind.expose:
      return null;
    case InteractionKind.exposeLapsed:
      return const Reward(positive: false, weight: 0.3);
  }
}
