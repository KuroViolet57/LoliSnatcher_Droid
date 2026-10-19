part of '../recommender_handler.dart';

/// What a world's model has learned, for the settings page.
class RecommenderReport {
  const RecommenderReport({
    required this.world,
    required this.events,
    required this.updates,
    required this.lastUpdate,
    required this.liked,
    required this.disliked,
    this.encoderFeatures = 0,
    this.tasteCount = 0,
    this.lookTasteCount = 0,
  });

  final RecommenderWorld world;

  /// Logged interactions.
  final int events;

  /// Training steps the model has taken (the log replayed counts too).
  final int updates;
  final DateTime? lastUpdate;
  final List<({String name, double weight})> liked;
  final List<({String name, double weight})> disliked;

  /// r34: how many of the encoder's vector components carry a weight (0
  /// without an encoder), and how many liked items shaped the taste centroid.
  final int encoderFeatures;
  final int tasteCount;

  /// r75: how many liked posts shaped the visual taste centroid.
  final int lookTasteCount;
}

/// r75: why a post stands where it does — what pulled it up and down, in
/// plain words, by weight.
class Explanation {
  const Explanation({required this.positive, required this.negative});

  static const Explanation empty = Explanation(positive: [], negative: []);

  final List<({String label, double weight})> positive;
  final List<({String label, double weight})> negative;

  bool get isEmpty => positive.isEmpty && negative.isEmpty;

  /// "because you liked: a, b; despite: c".
  String get sentence {
    final List<String> parts = [];
    if (positive.isNotEmpty) parts.add('because you liked: ${positive.map((p) => p.label).join(', ')}');
    if (negative.isNotEmpty) parts.add('despite: ${negative.map((p) => p.label).join(', ')}');
    return parts.join('; ');
  }

  /// A feature name as a person would say it.
  static String labelOf(String name) {
    String words(String s) => s.replaceAll('_', ' ');
    String split(String rest, String sep, String joiner) {
      final int i = rest.indexOf(sep);
      return i < 0 ? words(rest) : '${words(rest.substring(0, i))}$joiner${words(rest.substring(i + 1))}';
    }

    if (name.startsWith('emb:') || name.startsWith('taste:')) return 'how it reads';
    if (name.startsWith('look:') || name.startsWith('ltaste:')) return 'how it looks';
    if (name.startsWith('tag:')) return words(name.substring(4));
    if (name.startsWith('type:')) return split(name.substring(5), ':', ' ');
    if (name.startsWith('pair:')) return split(name.substring(5), '|', ' with ');
    if (name.startsWith('ns:')) return split(name.substring(3), ':', ' ');
    if (name.startsWith('site:')) return 'from ${name.substring(5)}';
    if (name.startsWith('media:')) return name.substring(6);
    if (name.startsWith('score:')) return 'score ${name.substring(6)}';
    if (name.startsWith('pages:')) return '${name.substring(6)} pages';
    if (name.startsWith('title:')) return 'the title (${words(name.substring(6))})';
    return words(name);
  }
}

/// The running mean of the encoder vectors of what a world's user liked.
class _Taste {
  _Taste({required this.model, required this.count, required this.vector});

  factory _Taste.empty() => _Taste(model: '', count: 0, vector: Float32List(0));

  static _Taste read(File file) {
    try {
      if (!file.existsSync()) return _Taste.empty();
      final Map<String, dynamic> m = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final List<double> v = [for (final x in m['vector'] as List) (x as num).toDouble()];
      return _Taste(model: m['model'] as String? ?? '', count: (m['count'] as num?)?.toInt() ?? 0, vector: Float32List.fromList(v));
    } catch (_) {
      return _Taste.empty();
    }
  }

  String model;
  int count;
  Float32List vector;

  /// The centroid when it came from [forModel]; another model's is no use.
  Float32List? vectorFor(String forModel) => count > 0 && model == forModel ? vector : null;

  void learn(Float32List embedding, {required String model, required double rate}) {
    if (this.model != model || vector.length != embedding.length) {
      this.model = model;
      count = 0;
      vector = Float32List(embedding.length);
    }
    count++;
    final double r = count == 1 ? 1 : rate;
    for (int i = 0; i < vector.length; i++) {
      vector[i] += (embedding[i] - vector[i]) * r;
    }
  }

  String toJson() => jsonEncode({'model': model, 'count': count, 'vector': [for (final double x in vector) double.parse(x.toStringAsFixed(6))]});
}
