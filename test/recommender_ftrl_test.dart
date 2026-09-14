import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/handlers/recommender/ftrl_model.dart';
import 'package:lolisnatcher/src/handlers/recommender/item_features.dart';

/// r33: the on-device learner. A hashed-feature logistic regression trained
/// online with FTRL-Proximal — it must learn a preference from a few dozen
/// events, keep untouched features at exactly zero, and survive a round trip
/// through its own bytes unchanged.
void main() {
  List<int> feats(List<String> names) => [for (final n in names) ItemFeatures.hash(n)];

  /// Sixty events: posts by alice are liked, posts by bob are skipped, each
  /// with a random general tag so the artist is the only stable signal.
  FtrlModel trained() {
    final FtrlModel m = FtrlModel();
    final Random r = Random(7);
    for (int i = 0; i < 60; i++) {
      final String noise = 'tag:noise_${r.nextInt(40)}';
      if (i.isEven) {
        m.update(feats(['type:artist:alice', 'tag:red_hair', noise]), positive: true, weight: 1);
      } else {
        m.update(feats(['type:artist:bob', 'tag:blue_hair', noise]), positive: false, weight: 1);
      }
    }
    return m;
  }

  group('FtrlModel', () {
    test('learns a preference: an unseen alice post scores above an unseen bob post', () {
      final FtrlModel m = trained();
      final double alice = m.predict(feats(['type:artist:alice', 'tag:glasses']));
      final double bob = m.predict(feats(['type:artist:bob', 'tag:glasses']));
      expect(alice, greaterThan(0.65));
      expect(bob, lessThan(0.35));
      expect(alice, greaterThan(bob));
      expect(m.updates, 60);
      expect(m.lastUpdate, isNotNull);
    });

    test('nothing learned is exactly nothing: untouched buckets weigh zero and an empty item is 0.5', () {
      final FtrlModel m = trained();
      expect(m.weight(ItemFeatures.hash('tag:never_seen')), 0);
      expect(m.predict(const []), 0.5);
      expect(m.nonZeroWeights, lessThanOrEqualTo(44), reason: 'two artists, two hair tags, at most forty noise tags');
      expect(FtrlModel().predict(feats(['type:artist:alice'])), 0.5, reason: 'a fresh model has no opinion');
    });

    test('a zero-weight update changes nothing', () {
      final FtrlModel m = FtrlModel();
      m.update(feats(['tag:x']), positive: true, weight: 0);
      expect(m.weight(ItemFeatures.hash('tag:x')), 0);
      expect(m.updates, 0);
    });

    test('bytes round-trip exactly; garbage is refused', () {
      final FtrlModel m = trained();
      final Uint8List bytes = m.toBytes();
      final FtrlModel back = FtrlModel.fromBytes(bytes)!;
      final List<int> probe = feats(['type:artist:alice', 'tag:blue_hair', 'tag:noise_3']);
      expect(back.predict(probe), m.predict(probe));
      expect(back.updates, m.updates);
      expect(back.lastUpdate, m.lastUpdate);
      expect(back.toBytes(), bytes);
      expect(FtrlModel.fromBytes(Uint8List.fromList(const [1, 2, 3])), isNull);
      expect(FtrlModel.fromBytes(Uint8List(0)), isNull);
    });

    test('the strongest weights name what was learned, liked and disliked apart', () {
      final FtrlModel m = trained();
      final List<({int hash, double weight})> liked = m.topWeights(2, positive: true);
      final List<({int hash, double weight})> disliked = m.topWeights(2, positive: false);
      expect(liked.map((e) => e.hash), contains(ItemFeatures.hash('type:artist:alice')));
      expect(liked.every((e) => e.weight > 0), isTrue);
      expect(disliked.map((e) => e.hash), contains(ItemFeatures.hash('type:artist:bob')));
      expect(disliked.every((e) => e.weight < 0), isTrue);
      expect(liked.first.weight, greaterThanOrEqualTo(liked.last.weight), reason: 'ordered');
    });

    test('novelty: how much of an item the model has never seen', () {
      final FtrlModel m = trained();
      expect(m.novelty(feats(['type:artist:alice', 'tag:red_hair'])), 0);
      expect(m.novelty(feats(['tag:brand_new', 'tag:also_new'])), 1);
      expect(m.novelty(feats(['type:artist:alice', 'tag:brand_new'])), 0.5);
      expect(m.novelty(const []), 1);
    });
  });
}
