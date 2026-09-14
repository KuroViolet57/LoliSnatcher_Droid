import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lolisnatcher/src/handlers/recommender/item_features.dart';

/// The on-device learner: a logistic regression over hashed features,
/// trained online with FTRL-Proximal (McMahan et al., 2013 — the estimator
/// behind large-scale click prediction).
///
/// Why this and not a network: it learns from the first event, an update
/// costs microseconds, the L1 term keeps every feature the user never
/// reacted to at exactly zero (so the model stays small and honest), and its
/// weights can be read back as "what was learned". One instance per world
/// (booru, doujin); the features come from [ItemFeatures].
class FtrlModel {
  FtrlModel({
    this.buckets = ItemFeatures.buckets,
    this.alpha = 0.3,
    this.beta = 1,
    this.l1 = 0.001,
    this.l2 = 0.0001,
  }) : _z = Float32List(buckets),
       _n = Float32List(buckets);

  final int buckets;

  /// Learning rate; a single user's few hundred events want a large one.
  final double alpha;
  final double beta;
  final double l1;
  final double l2;

  final Float32List _z;
  final Float32List _n;

  int updates = 0;
  DateTime? lastUpdate;

  /// The weight of feature [i], derived from its accumulators.
  double weight(int i) {
    final double z = _z[i];
    if (z.abs() <= l1) return 0;
    final double sign = z < 0 ? -1 : 1;
    return -(z - sign * l1) / ((beta + math.sqrt(_n[i])) / alpha + l2);
  }

  /// Probability that the user likes an item with [features]; 0.5 when the
  /// model knows nothing about it.
  double predict(List<int> features) {
    if (features.isEmpty) return 0.5;
    double logit = 0;
    for (final int i in _unique(features)) {
      logit += weight(i);
    }
    return 1 / (1 + math.exp(-logit));
  }

  /// One online step: [positive] is the label, [weight] how much to trust it.
  void update(List<int> features, {required bool positive, double weight = 1}) {
    if (weight <= 0 || features.isEmpty) return;
    final List<int> unique = _unique(features);
    final double p = predict(unique);
    final double g = (p - (positive ? 1 : 0)) * weight;
    final double g2 = g * g;
    for (final int i in unique) {
      final double w = this.weight(i);
      final double sigma = (math.sqrt(_n[i] + g2) - math.sqrt(_n[i])) / alpha;
      _z[i] += g - sigma * w;
      _n[i] += g2;
    }
    updates++;
    final DateTime now = DateTime.now();
    lastUpdate = DateTime.fromMillisecondsSinceEpoch(now.millisecondsSinceEpoch);
  }

  /// How many features carry any weight at all.
  int get nonZeroWeights {
    int count = 0;
    for (int i = 0; i < buckets; i++) {
      if (_z[i].abs() > l1) count++;
    }
    return count;
  }

  /// The share of [features] the model has never reacted to (0 = all known,
  /// 1 = all new). Recommendation surfaces use it to leave room for the
  /// unexplored.
  double novelty(List<int> features) {
    final List<int> unique = _unique(features);
    if (unique.isEmpty) return 1;
    int unseen = 0;
    for (final int i in unique) {
      if (_z[i].abs() <= l1) unseen++;
    }
    return unseen / unique.length;
  }

  /// The [k] strongest weights, liked (positive) or disliked, strongest first.
  List<({int hash, double weight})> topWeights(int k, {required bool positive}) {
    final List<({int hash, double weight})> out = [];
    for (int i = 0; i < buckets; i++) {
      if (_z[i].abs() <= l1) continue;
      final double w = weight(i);
      if (positive ? w > 0 : w < 0) out.add((hash: i, weight: w));
    }
    out.sort((a, b) => positive ? b.weight.compareTo(a.weight) : a.weight.compareTo(b.weight));
    return out.length > k ? out.sublist(0, k) : out;
  }

  static List<int> _unique(List<int> features) {
    if (features.length < 2) return features;
    final Set<int> seen = {};
    final List<int> out = [];
    for (final int f in features) {
      if (seen.add(f)) out.add(f);
    }
    return out;
  }

  // ── persistence ──

  static const int _magic = 0x4D52534C; // 'LSRM' little-endian
  static const int _version = 1;
  static const int _headerBytes = 4 + 4 + 4 + 4 + 8 + 8 * 4;

  Uint8List toBytes() {
    final ByteData header = ByteData(_headerBytes);
    header
      ..setUint32(0, _magic, Endian.little)
      ..setUint32(4, _version, Endian.little)
      ..setUint32(8, buckets, Endian.little)
      ..setUint32(12, updates, Endian.little)
      ..setInt64(16, lastUpdate?.millisecondsSinceEpoch ?? 0, Endian.little)
      ..setFloat64(24, alpha, Endian.little)
      ..setFloat64(32, beta, Endian.little)
      ..setFloat64(40, l1, Endian.little)
      ..setFloat64(48, l2, Endian.little);
    final Uint8List out = Uint8List(_headerBytes + buckets * 8);
    out.setRange(0, _headerBytes, header.buffer.asUint8List());
    if (Endian.host == Endian.little) {
      // The accumulators are little-endian floats already: two copies, not
      // half a million element writes (this runs on the UI isolate).
      out.setRange(_headerBytes, _headerBytes + buckets * 4, _z.buffer.asUint8List(_z.offsetInBytes, buckets * 4));
      out.setRange(_headerBytes + buckets * 4, _headerBytes + buckets * 8, _n.buffer.asUint8List(_n.offsetInBytes, buckets * 4));
      return out;
    }
    final ByteData body = ByteData.sublistView(out, _headerBytes);
    for (int i = 0; i < buckets; i++) {
      body.setFloat32(i * 4, _z[i], Endian.little);
      body.setFloat32((buckets + i) * 4, _n[i], Endian.little);
    }
    return out;
  }

  /// A model from [toBytes] output; null for anything else.
  static FtrlModel? fromBytes(Uint8List bytes) {
    if (bytes.length < _headerBytes) return null;
    final ByteData header = ByteData.sublistView(bytes, 0, _headerBytes);
    if (header.getUint32(0, Endian.little) != _magic) return null;
    if (header.getUint32(4, Endian.little) != _version) return null;
    final int buckets = header.getUint32(8, Endian.little);
    if (buckets <= 0 || bytes.length != _headerBytes + buckets * 8) return null;
    final FtrlModel model = FtrlModel(
      buckets: buckets,
      alpha: header.getFloat64(24, Endian.little),
      beta: header.getFloat64(32, Endian.little),
      l1: header.getFloat64(40, Endian.little),
      l2: header.getFloat64(48, Endian.little),
    );
    model.updates = header.getUint32(12, Endian.little);
    final int at = header.getInt64(16, Endian.little);
    model.lastUpdate = at == 0 ? null : DateTime.fromMillisecondsSinceEpoch(at);
    if (Endian.host == Endian.little) {
      // A copy aligned for a float view, whatever offset the file bytes came in at.
      final Uint8List body = Uint8List.fromList(Uint8List.sublistView(bytes, _headerBytes));
      final Float32List floats = Float32List.view(body.buffer, body.offsetInBytes, buckets * 2);
      model._z.setAll(0, floats.sublist(0, buckets));
      model._n.setAll(0, floats.sublist(buckets, buckets * 2));
      return model;
    }
    final ByteData body = ByteData.sublistView(bytes, _headerBytes);
    for (int i = 0; i < buckets; i++) {
      model._z[i] = body.getFloat32(i * 4, Endian.little);
      model._n[i] = body.getFloat32((buckets + i) * 4, Endian.little);
    }
    return model;
  }
}
