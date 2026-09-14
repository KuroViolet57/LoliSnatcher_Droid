import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/handlers/recommender/rewards.dart';

/// r33: what each interaction teaches the learner — a label and how much to
/// trust it. A finished book or a favourite is worth several fleeting views;
/// a flick past is a quiet no; a glance in between says nothing.
void main() {
  group('rewardFor', () {
    test('explicit likes weigh most', () {
      expect(rewardFor(InteractionKind.favourite), const Reward(positive: true, weight: 3));
      expect(rewardFor(InteractionKind.collect), const Reward(positive: true, weight: 3));
      expect(rewardFor(InteractionKind.finish), const Reward(positive: true, weight: 3));
      expect(rewardFor(InteractionKind.snatch), const Reward(positive: true, weight: 2));
      expect(rewardFor(InteractionKind.follow), const Reward(positive: true, weight: 2));
      expect(rewardFor(InteractionKind.star), const Reward(positive: true, weight: 2));
    });

    test('explicit dislikes weigh as much', () {
      expect(rewardFor(InteractionKind.unfavourite), const Reward(positive: false, weight: 3));
      expect(rewardFor(InteractionKind.blacklist), const Reward(positive: false, weight: 3));
      expect(rewardFor(InteractionKind.forget), const Reward(positive: false, weight: 2));
    });

    test('a view is graded by how long it lasted', () {
      expect(rewardFor(InteractionKind.view, value: 12), const Reward(positive: true, weight: 1));
      expect(rewardFor(InteractionKind.view, value: 8), const Reward(positive: true, weight: 1));
      expect(rewardFor(InteractionKind.view, value: 4), const Reward(positive: true, weight: 0.5));
      expect(rewardFor(InteractionKind.view, value: 2), isNull, reason: 'a glance says nothing');
      expect(rewardFor(InteractionKind.view, value: 1), const Reward(positive: false, weight: 1), reason: 'a flick past');
      expect(rewardFor(InteractionKind.skip), const Reward(positive: false, weight: 1));
    });

    test('reading is graded by how far it went', () {
      expect(rewardFor(InteractionKind.read, value: 1), const Reward(positive: true, weight: 2));
      expect(rewardFor(InteractionKind.read, value: 0.5), const Reward(positive: true, weight: 2));
      expect(rewardFor(InteractionKind.read, value: 0.3), isNull);
    });

    test('searching, previewing and opening are mild interest', () {
      expect(rewardFor(InteractionKind.search), const Reward(positive: true, weight: 0.5));
      expect(rewardFor(InteractionKind.tagPreview), const Reward(positive: true, weight: 0.5));
      expect(rewardFor(InteractionKind.open), const Reward(positive: true, weight: 0.5));
    });

    test('being shown teaches nothing by itself; being shown and passed over is a quiet no', () {
      expect(rewardFor(InteractionKind.expose), isNull);
      expect(rewardFor(InteractionKind.exposeLapsed), const Reward(positive: false, weight: 0.3));
    });

    test('kinds round-trip through their stored names', () {
      for (final InteractionKind kind in InteractionKind.values) {
        expect(InteractionKind.fromName(kind.name), kind);
      }
      expect(InteractionKind.fromName('not-a-kind'), isNull);
    });
  });
}
