import 'dart:math';
import 'dart:typed_data';

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

    test('real-valued features (r34, the encoder): the value scales both the step and the prediction; absent values are ones', () {
      final FtrlModel m = FtrlModel();
      final List<int> f = feats(['emb:0']);
      m.update(f, values: const [2], positive: true);
      final double strong = m.predict(f, values: const [2]);
      final double weak = m.predict(f, values: const [1]);
      final double none = m.predict(f);
      expect(strong, greaterThan(weak));
      expect(weak, closeTo(none, 1e-9), reason: 'no values = every feature present with value 1');
      expect(m.predict(f, values: const [0]), 0.5, reason: 'a zero value is not there');
      expect(m.predict(f, values: const [-2]), lessThan(0.5), reason: 'a negative value pulls the other way');
      // A component that saw the same direction in training moves the prediction; a fresh one does not.
      final FtrlModel d = FtrlModel();
      final List<int> emb = feats(['emb:0', 'emb:1']);
      for (int i = 0; i < 20; i++) {
        d.update(emb, values: const [1, -1], positive: true);
        d.update(emb, values: const [-1, 1], positive: false);
      }
      expect(d.predict(emb, values: const [1, -1]), greaterThan(0.8));
      expect(d.predict(emb, values: const [-1, 1]), lessThan(0.2));
      expect(d.predict(feats(['emb:2']), values: const [1]), 0.5);
    });

    test("the encoder's block is graded, not a switch (review): one favourite lifts a lookalike a little, leaves a stranger alone, and fifteen likes do not saturate", () {
      final Random r = Random(11);
      Float32List unit() {
        final Float32List v = Float32List(384);
        double n = 0;
        for (int i = 0; i < v.length; i++) {
          v[i] = r.nextDouble() * 2 - 1;
          n += v[i] * v[i];
        }
        n = sqrt(n);
        for (int i = 0; i < v.length; i++) {
          v[i] /= n;
        }
        return v;
      }

      Float32List blend(Float32List a, Float32List b, double wa) {
        final Float32List v = Float32List(a.length);
        double n = 0;
        for (int i = 0; i < v.length; i++) {
          v[i] = wa * a[i] + (1 - wa) * b[i];
          n += v[i] * v[i];
        }
        n = sqrt(n);
        for (int i = 0; i < v.length; i++) {
          v[i] /= n;
        }
        return v;
      }

      FeatureVector item(int tagSet, Float32List vector) => ItemFeatures.withEmbedding(
        FeatureVector([for (int i = 0; i < 40; i++) ItemFeatures.hash('tag:set${tagSet}_$i')], [for (int i = 0; i < 40; i++) 'tag:set${tagSet}_$i']),
        vector,
        model: 'm',
      );
      double p(FtrlModel m, FeatureVector f) => m.predict(f.hashes, values: f.values);

      final Float32List liked = unit();
      final Float32List stranger = unit();
      final Float32List halfway = blend(liked, stranger, 0.5);
      final FtrlModel m = FtrlModel();
      final FeatureVector first = item(0, liked);
      m.update(first.hashes, values: first.values, positive: true, weight: 3);
      final double lookalike = p(m, item(1, liked));
      final double unrelated = p(m, item(2, stranger));
      // ignore: avoid_print
      print('after one favourite: lookalike $lookalike, unrelated $unrelated');
      expect(lookalike, greaterThan(0.55), reason: 'reading alike counts');
      expect(lookalike, lessThan(0.9), reason: 'one favourite is not certainty');
      expect((unrelated - 0.5).abs(), lessThan(0.1), reason: 'a stranger is untouched');
      for (int k = 1; k <= 15; k++) {
        final FeatureVector f = item(10 + k, liked);
        m.update(f.hashes, values: f.values, positive: true, weight: 3);
      }
      final double sure = p(m, item(30, liked));
      final double half = p(m, item(31, halfway));
      final double still = p(m, item(32, stranger));
      // ignore: avoid_print
      print('after fifteen more: lookalike $sure, halfway $half, unrelated $still');
      expect(sure, greaterThan(0.75));
      expect(sure, lessThan(0.995), reason: 'fifteen likes are strong, not absolute');
      expect(half, greaterThan(0.55));
      expect(half, lessThan(sure), reason: 'graded by similarity');
      expect((still - 0.5).abs(), lessThan(0.15));
      // One "Not interested" near the liked direction dents it, it does not flip the whole neighbourhood.
      final FeatureVector no = item(40, halfway);
      m.update(no.hashes, values: no.values, positive: false, weight: 3);
      final double afterNo = p(m, item(41, liked));
      // ignore: avoid_print
      print('after one Not interested nearby: lookalike $afterNo');
      expect(afterNo, greaterThan(0.4), reason: 'sixteen likes outweigh one no');
      expect(afterNo, lessThan(sure));
    });
  });

  test('r75: setWeight puts a feature at an exact weight, fresh or after learning; nudge moves it by a step; both survive a save', () {
    final FtrlModel m = FtrlModel();
    final int h = ItemFeatures.hash('tag:beach');
    m.setWeight(h, 1.25);
    expect(m.weight(h), closeTo(1.25, 1e-6));
    m.setWeight(h, -0.75);
    expect(m.weight(h), closeTo(-0.75, 1e-6));
    m.setWeight(h, 0);
    expect(m.weight(h), 0);
    for (int i = 0; i < 20; i++) {
      m.update([h], positive: true);
    }
    final double learned = m.weight(h);
    expect(learned, greaterThan(0));
    m.nudge(h, -0.5);
    expect(m.weight(h), closeTo(learned - 0.5, 1e-6));
    m.setWeight(h, 2);
    expect(m.weight(h), closeTo(2, 1e-6));
    expect(FtrlModel.fromBytes(m.toBytes())!.weight(h), closeTo(2, 1e-6));
  });
}
