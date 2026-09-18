import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:get_it/get_it.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/database_handler.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/encoder_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/ftrl_model.dart';
import 'package:lolisnatcher/src/handlers/recommender/item_features.dart';
import 'package:lolisnatcher/src/handlers/recommender/pixel_tags.dart';
import 'package:lolisnatcher/src/handlers/recommender/rewards.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

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
}

/// The on-device recommender behind every recommendation surface.
///
/// One [FtrlModel] per world (booru, doujin), trained online from the
/// interactions the app reports here — every event is logged
/// (`Interaction`) so the model can be rebuilt from the log alone, and the
/// feature names are kept so what was learned reads back as tags and
/// artists. Surfaces ask [rerank] / [score] / [seedTerms]; sources of events
/// call [onEvent] / [onQuery] / [onExposed].
///
/// Two independent switches (Settings → Recommendations):
///   * `aiLearning`        — events are logged and train the model;
///   * `aiRecommendations` — the model orders and seeds the surfaces.
/// Learning may run while the classic ordering is shown, and a frozen model
/// keeps serving.
///
/// Nothing here ever leaves the device.
class RecommenderHandler {
  static RecommenderHandler get instance => GetIt.instance<RecommenderHandler>();

  static RecommenderHandler register() {
    if (!GetIt.instance.isRegistered<RecommenderHandler>()) {
      GetIt.instance.registerSingleton(RecommenderHandler());
    }
    return instance;
  }

  static void unregister() {
    if (GetIt.instance.isRegistered<RecommenderHandler>()) {
      instance._saveTimer?.cancel();
      GetIt.instance.unregister<RecommenderHandler>();
    }
  }

  /// The recommender when the app registered one; null in tests and tools
  /// that did not. Event sources and surfaces go through this, so they never
  /// depend on the recommender being there.
  static RecommenderHandler? get maybe => GetIt.instance.isRegistered<RecommenderHandler>() ? instance : null;

  static const String className = 'RecommenderHandler';

  /// Rows kept per world; older ones are pruned.
  static const int logCap = 20000;

  /// Every Nth slot of a reranked page goes to the most promising item the
  /// model has not seen (novelty ≥ [explorationNovelty]).
  static const int explorationEvery = 5;
  static const double explorationNovelty = 0.6;

  /// A model is 2 MB on disk; while the user browses it is written this
  /// often at most, and at once when the app goes to the background
  /// (`main.dart`) or [flush] is called.
  static const Duration saveInterval = Duration(seconds: 30);

  /// r74: the tags the image tagger reads from a post's thumbnail, for a
  /// strong reaction (Settings → Recommendations → Tag reactions with the
  /// picture). Replaced in tests.
  static Future<List<String>> Function(BooruItem item, BooruHandler? handler)? pixelTagsFor = _defaultPixelTagsFor;
  static const Duration pixelTimeout = Duration(seconds: 30);

  static void resetSeamsForTests() {
    pixelTagsFor = _defaultPixelTagsFor;
  }

  static Future<List<String>> _defaultPixelTagsFor(BooruItem item, BooruHandler? handler) => PixelTags.forItem(item, handler?.booru);

  final Map<RecommenderWorld, FtrlModel> _models = {};
  final Map<RecommenderWorld, Future<FtrlModel>> _loading = {};
  final Set<RecommenderWorld> _dirty = {};
  Timer? _saveTimer;
  int _sincePrune = 0;

  /// Per surface, the last batch it showed; an item of the previous batch
  /// that was drawn, never interacted with and is not shown again is a quiet
  /// no when the next batch comes.
  final Map<String, Map<String, ({RecommenderWorld world, String host, FeatureVector features})>> _exposed = {};
  final Set<String> _interacted = {};

  /// Items whose thumbnail was actually built this session. A surface hands
  /// over whole pages and strips of thirty; only what reached the screen
  /// can have been passed over.
  final Set<String> _rendered = {};

  /// r34: what the user marked "Not interested", per world — never
  /// recommended again; read back from the log with the world's model.
  final Map<RecommenderWorld, Set<String>> _dismissed = {};

  /// r34: per world, the running mean of the encoder vectors of what was
  /// liked (favourites, finishes, downloads…): "reads like what you liked"
  /// becomes a feature. Tied to the encoder model that produced it.
  final Map<RecommenderWorld, _Taste> _taste = {};
  static const double tasteRate = 0.1;

  EncoderHandler? get _encoder {
    final EncoderHandler? e = EncoderHandler.maybe;
    return e != null && e.enabled ? e : null;
  }

  SettingsHandler get _settings => SettingsHandler.instance;
  DBHandler get _db => _settings.dbHandler;

  bool get learningEnabled => _settings.dbEnabled && _settings.aiLearning;
  bool get recommendationsEnabled => _settings.aiRecommendations;

  static String keyOf(BooruItem item) => item.postURL.isNotEmpty ? item.postURL : item.fileURL;

  static String _hostOf(BooruItem item) => Uri.tryParse(item.postURL)?.host ?? '';

  String fileFor(RecommenderWorld world) =>
      '${_settings.path}recommender${Platform.pathSeparator}${world.name}.bin';

  // ── the models ──

  /// The world's model: from its file, else rebuilt from the log, else fresh.
  Future<FtrlModel> modelFor(RecommenderWorld world) {
    final FtrlModel? loaded = _models[world];
    if (loaded != null) return Future.value(loaded);
    // A block body on purpose: `remove` returns the future being awaited,
    // and whenComplete would wait for it — on itself.
    return _loading[world] ??= _load(world).whenComplete(() {
      _loading.remove(world);
    });
  }

  Future<FtrlModel> _load(RecommenderWorld world) async {
    FtrlModel? model;
    try {
      final File file = File(fileFor(world));
      if (await file.exists()) {
        model = FtrlModel.fromBytes(await file.readAsBytes());
        if (model == null) {
          Logger.Inst().log('${world.name} model file unreadable; rebuilding from the log', className, '_load', LogTypes.booruHandlerInfo);
        }
      }
    } catch (e, s) {
      Logger.Inst().log('reading the ${world.name} model failed: $e', className, '_load', LogTypes.exception, s: s);
    }
    if (model != null && model.buckets != ItemFeatures.buckets) {
      // Hashes are masked to the app's bucket count; a file with another
      // would be indexed out of range on the first prediction.
      Logger.Inst().log('${world.name} model has ${model.buckets} buckets, the app ${ItemFeatures.buckets}; rebuilding from the log', className, '_load', LogTypes.booruHandlerInfo);
      model = null;
    }
    if (model == null) {
      model = FtrlModel();
      await _replay(world, model);
    }
    await _loadDismissed(world);
    _taste[world] ??= _Taste.read(File(tasteFileFor(world)));
    return _models[world] = model;
  }

  String tasteFileFor(RecommenderWorld world) =>
      '${_settings.path}recommender${Platform.pathSeparator}${world.name}.taste.json';

  Future<void> _loadDismissed(RecommenderWorld world) async {
    if (!_settings.dbEnabled) return;
    try {
      final Set<String> keys = _dismissed[world] ??= {};
      keys.addAll(await _db.interactionKeys(world.name, InteractionKind.notInterested.name));
    } catch (e, s) {
      Logger.Inst().log('reading dismissals failed: $e', className, '_loadDismissed', LogTypes.exception, s: s);
    }
  }

  Future<void> _replay(RecommenderWorld world, FtrlModel model) async {
    if (!_settings.dbEnabled) return;
    try {
      final List<InteractionRow> rows = await _db.recentInteractions(world.name, limit: logCap);
      for (final InteractionRow row in rows.reversed) {
        final InteractionKind? kind = row.kind;
        if (kind == null) continue;
        final Reward? reward = rewardFor(kind, value: row.value);
        if (reward == null) continue;
        model.update(row.features, positive: reward.positive, weight: reward.weight);
      }
      if (rows.isNotEmpty) _markDirty(world);
    } catch (e, s) {
      Logger.Inst().log('replaying the ${world.name} log failed: $e', className, '_replay', LogTypes.exception, s: s);
    }
  }

  void _markDirty(RecommenderWorld world) {
    _dirty.add(world);
    _saveTimer ??= Timer(saveInterval, () {
      _saveTimer = null;
      unawaited(flush());
    });
  }

  /// Writes every changed model to disk now.
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final List<RecommenderWorld> worlds = _dirty.toList();
    _dirty.clear();
    for (final RecommenderWorld world in worlds) {
      final FtrlModel? model = _models[world];
      if (model == null) continue;
      try {
        final File file = File(fileFor(world));
        await file.parent.create(recursive: true);
        await file.writeAsBytes(model.toBytes(), flush: true);
        final _Taste? taste = _taste[world];
        if (taste != null && taste.count > 0) await File(tasteFileFor(world)).writeAsString(taste.toJson());
      } catch (e, s) {
        Logger.Inst().log('saving the ${world.name} model failed: $e', className, 'flush', LogTypes.exception, s: s);
        _dirty.add(world);
      }
    }
  }

  /// [item]'s features for [world], with the encoder's vector when there is
  /// one ([embedding] already fetched, or looked up in the encoder's memory).
  FeatureVector _featuresFor(
    BooruItem item,
    RecommenderWorld world, {
    BooruHandler? handler,
    Map<String, String>? namespaces,
    Float32List? embedding,
    bool fromMemory = false,
    List<String> extraTags = const [],
  }) {
    final FeatureVector base = ItemFeatures.of(item, world, handler: handler, namespaces: namespaces, extraTags: extraTags);
    final EncoderHandler? encoder = _encoder;
    if (encoder == null) return base;
    final Float32List? vector = embedding ?? (fromMemory ? encoder.cached(item) : null);
    if (vector == null) return base;
    return ItemFeatures.withEmbedding(base, vector, model: encoder.modelId, taste: _taste[world]?.vectorFor(encoder.modelId));
  }

  Future<List<Float32List?>> _embeddings(List<BooruItem> items, {BooruHandler? handler}) async {
    final EncoderHandler? encoder = _encoder;
    if (encoder == null) return List.filled(items.length, null);
    try {
      return await encoder.embedItems(items, handler: handler);
    } catch (e, s) {
      Logger.Inst().log('embedding for the recommender failed: $e', className, '_embeddings', LogTypes.exception, s: s);
      return List.filled(items.length, null);
    }
  }

  // ── events in ──

  /// An interaction with [item]. Logged and learned at once when learning is
  /// on; a kind that teaches nothing (see [rewardFor]) is neither.
  Future<void> onEvent(
    BooruItem item,
    InteractionKind kind, {
    double value = 0,
    BooruHandler? handler,
    Map<String, String>? namespaces,
  }) async {
    final String key = keyOf(item);
    if (key.isNotEmpty) _interacted.add(key);
    if (!learningEnabled) return;
    final Reward? reward = rewardFor(kind, value: value);
    if (reward == null) return;
    final RecommenderWorld world = ItemFeatures.worldOf(item);
    await modelFor(world);
    final Float32List? embedding = (await _embeddings([item], handler: handler)).first;
    final List<String> pixel = await _pixelTags(item, world, reward, kind, handler: handler);
    final FeatureVector features = _featuresFor(item, world, handler: handler, namespaces: namespaces, embedding: embedding, extraTags: pixel);
    if (features.isEmpty) return;
    await _learn(world, key, _hostOf(item), kind, value, features, reward);
    if (embedding != null && reward.positive && reward.weight >= 2) {
      final EncoderHandler? encoder = _encoder;
      if (encoder != null) {
        (_taste[world] ??= _Taste.empty()).learn(embedding, model: encoder.modelId, rate: tasteRate);
        _markDirty(world);
      }
    }
  }

  /// r74: a strong reaction (weight 2 or more) on a booru post also learns
  /// what the picture shows — never a view or a flick, never a doujin. A
  /// tagger that fails or takes too long leaves the site's tags alone.
  Future<List<String>> _pixelTags(BooruItem item, RecommenderWorld world, Reward reward, InteractionKind kind, {BooruHandler? handler}) async {
    final Future<List<String>> Function(BooruItem item, BooruHandler? handler)? tagger = pixelTagsFor;
    if (tagger == null || !_settings.taggerOnReactions || world != RecommenderWorld.booru || reward.weight < 2) return const [];
    try {
      final List<String> tags = await tagger(item, handler).timeout(pixelTimeout);
      final Set<String> own = {for (final t in item.tagsList) t.fullString.toLowerCase()};
      final int fresh = tags.where((t) => !own.contains(t.toLowerCase())).length;
      Logger.Inst().log('tagger: reaction ${kind.name}, ${tags.length} tags from the picture, $fresh new', className, '_pixelTags', LogTypes.booruHandlerInfo);
      return tags;
    } catch (e) {
      Logger.Inst().log('tagger: reaction ${kind.name} not tagged: $e', className, '_pixelTags', LogTypes.booruHandlerInfo);
      return const [];
    }
  }

  /// "Not interested" (r35): a loud no, and [item] is never recommended
  /// again (see [withoutDismissed]). It is an order, not a passive signal:
  /// it is written to the log even while learning is off, so it survives a
  /// restart either way; the model learns from it only when learning is on.
  Future<void> dismiss(BooruItem item, {BooruHandler? handler}) async {
    final String key = keyOf(item);
    final RecommenderWorld world = ItemFeatures.worldOf(item);
    if (key.isNotEmpty) (_dismissed[world] ??= {}).add(key);
    if (learningEnabled) {
      await onEvent(item, InteractionKind.notInterested, handler: handler);
      return;
    }
    if (!_settings.dbEnabled || key.isEmpty) return;
    try {
      final FeatureVector features = ItemFeatures.of(item, world, handler: handler);
      await _db.addInteraction(world: world.name, itemKey: key, host: _hostOf(item), kind: InteractionKind.notInterested.name, value: 0, features: features.hashes);
    } catch (e, s) {
      Logger.Inst().log('recording a dismissal failed: $e', className, 'dismiss', LogTypes.exception, s: s);
    }
  }

  bool isDismissed(BooruItem item) => _dismissed[ItemFeatures.worldOf(item)]?.contains(keyOf(item)) ?? false;

  /// [items] without what the user marked "Not interested". Loads the
  /// worlds' dismissals first: the first page after a start asks before any
  /// model was loaded (review).
  Future<List<BooruItem>> withoutDismissed(List<BooruItem> items) async {
    if (items.isEmpty) return items;
    for (final RecommenderWorld world in {for (final BooruItem i in items) ItemFeatures.worldOf(i)}) {
      if (!_models.containsKey(world)) await modelFor(world);
    }
    return [for (final BooruItem i in items) if (!isDismissed(i)) i];
  }

  /// [scoreDoujinParts] for many remembered galleries at once: their texts
  /// go to the encoder in one batched call instead of one call each.
  Future<List<double>> scoreDoujinPartsMany(List<({List<String> namespacedTags, String title, String host, int? pages})> entries) async {
    if (entries.isEmpty) return const [];
    if (!recommendationsEnabled) return List.filled(entries.length, 0.5);
    final FtrlModel model = await modelFor(RecommenderWorld.doujin);
    if (model.updates == 0) return List.filled(entries.length, 0.5);
    final EncoderHandler? encoder = _encoder;
    List<Float32List?> vectors = List.filled(entries.length, null);
    if (encoder != null) {
      try {
        vectors = await encoder.embedTexts([for (final e in entries) EncoderHandler.textOfDoujinParts(namespacedTags: e.namespacedTags, title: e.title)]);
      } catch (_) {}
    }
    final List<double> out = [];
    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      FeatureVector f = ItemFeatures.ofDoujinParts(namespacedTags: e.namespacedTags, title: e.title, host: e.host, pages: e.pages);
      final Float32List? v = vectors[i];
      if (encoder != null && v != null) {
        f = ItemFeatures.withEmbedding(f, v, model: encoder.modelId, taste: _taste[RecommenderWorld.doujin]?.vectorFor(encoder.modelId));
      }
      out.add(model.predict(f.hashes, values: f.values));
    }
    return out;
  }

  /// A search or a tag preview on [booru]: learned as its terms.
  Future<void> onQuery(String query, Booru? booru, InteractionKind kind) =>
      onQueryInWorld(query, ItemFeatures.worldOfBooru(booru), kind, host: DoujinDataHandler.hostOf(booru));

  /// [onQuery] for a caller that knows the world but holds no source (a
  /// starred doujin tag, the doujin-global blacklist).
  Future<void> onQueryInWorld(String query, RecommenderWorld world, InteractionKind kind, {String host = ''}) async {
    if (!learningEnabled) return;
    final Reward? reward = rewardFor(kind);
    if (reward == null) return;
    final FeatureVector features = ItemFeatures.ofQuery(query, world);
    if (features.isEmpty) return;
    await _learn(world, 'query:${query.trim()}', host, kind, 0, features, reward);
  }

  /// A recommendation surface handed [items] to the screen. The previous
  /// batch of the same surface is judged now: what was drawn, never
  /// interacted with and is not shown again was passed over. That is learned
  /// but not logged — the log is what the user did, and a rebuild from it
  /// must not be drowned in what they scrolled past.
  Future<void> onExposed(List<BooruItem> items, String surface, {BooruHandler? handler}) async {
    if (!learningEnabled) return;
    final Map<String, ({RecommenderWorld world, String host, FeatureVector features})>? previous = _exposed[surface];
    final Map<String, ({RecommenderWorld world, String host, FeatureVector features})> current = {};
    final List<Float32List?> embeddings = await _embeddings(items, handler: handler);
    for (int i = 0; i < items.length; i++) {
      final BooruItem item = items[i];
      final String key = keyOf(item);
      if (key.isEmpty) continue;
      final RecommenderWorld world = ItemFeatures.worldOf(item);
      current[key] = (world: world, host: _hostOf(item), features: _featuresFor(item, world, handler: handler, embedding: embeddings[i]));
    }
    _exposed[surface] = current;
    if (previous == null) return;
    final Reward reward = rewardFor(InteractionKind.exposeLapsed)!;
    for (final entry in previous.entries) {
      if (!_rendered.contains(entry.key)) continue;
      if (_interacted.contains(entry.key) || current.containsKey(entry.key)) continue;
      if (entry.value.features.isEmpty) continue;
      await _learn(entry.value.world, entry.key, entry.value.host, InteractionKind.exposeLapsed, 0, entry.value.features, reward, log: false);
    }
  }

  /// [item]'s thumbnail was built: it reached the screen (or its edge).
  void onRendered(BooruItem item) {
    final String key = keyOf(item);
    if (key.isNotEmpty) _rendered.add(key);
  }

  /// "Forget this": a learned feature pushed down, by name.
  Future<void> forgetFeature(RecommenderWorld world, String name) async {
    if (!_settings.dbEnabled) return;
    final Reward reward = rewardFor(InteractionKind.forget)!;
    await _learn(
      world,
      'feature:$name',
      '',
      InteractionKind.forget,
      0,
      FeatureVector([ItemFeatures.hash(name)], [name]),
      reward,
    );
  }

  Future<void> _learn(
    RecommenderWorld world,
    String key,
    String host,
    InteractionKind kind,
    double value,
    FeatureVector features,
    Reward reward, {
    bool log = true,
  }) async {
    // The model first: a first load replays the log, and a row written before
    // that would be learned twice — once by the replay, once below.
    final FtrlModel model = await modelFor(world);
    if (log) {
      try {
        // The encoder's components are not logged: they belong to one model
        // and a replay learns them again from the item text if it wants to.
        final List<int> hashes = features.loggedHashes;
        final List<String> names = features.loggedNames;
        await _db.addInteraction(world: world.name, itemKey: key, host: host, kind: kind.name, value: value, features: hashes);
        await _db.addFeatureNames(world.name, {for (int i = 0; i < hashes.length; i++) hashes[i]: names[i]});
        if (++_sincePrune >= 200) {
          _sincePrune = 0;
          await _db.pruneInteractions(keep: logCap);
          await _db.pruneEmbeddings();
        }
      } catch (e, s) {
        Logger.Inst().log('logging an interaction failed: $e', className, '_learn', LogTypes.exception, s: s);
      }
    }
    model.update(features.hashes, positive: reward.positive, weight: reward.weight, values: features.values);
    _markDirty(world);
  }

  // ── recommendations out ──

  /// How much the user would like [item], 0..1; 0.5 when recommendations are
  /// off or nothing was learned yet.
  Future<double> score(BooruItem item, {RecommenderWorld? world, BooruHandler? handler, Map<String, String>? namespaces}) async {
    if (!recommendationsEnabled) return 0.5;
    final RecommenderWorld w = world ?? ItemFeatures.worldOf(item);
    final FtrlModel model = await modelFor(w);
    if (model.updates == 0) return 0.5;
    final Float32List? embedding = (await _embeddings([item], handler: handler)).first;
    final FeatureVector f = _featuresFor(item, w, handler: handler, namespaces: namespaces, embedding: embedding);
    return model.predict(f.hashes, values: f.values);
  }

  /// A synchronous scorer over the world's model for callers that rank in
  /// a loop (the doujin Recommended strip); null when recommendations are
  /// off or nothing was learned. [items] are embedded first when given, so
  /// the encoder's vectors are at hand inside the loop.
  Future<double Function(BooruItem)?> scorer(RecommenderWorld world, {BooruHandler? handler, List<BooruItem>? items}) async {
    if (!recommendationsEnabled) return null;
    final FtrlModel model = await modelFor(world);
    if (model.updates == 0) return null;
    if (items != null) await _embeddings(items, handler: handler);
    return (BooruItem item) {
      final FeatureVector f = _featuresFor(item, world, handler: handler, fromMemory: true);
      return model.predict(f.hashes, values: f.values);
    };
  }

  /// [scorer] for a source that ranks raw rows before they are items
  /// (nhentai's recommendation builder): scores namespaced tag lists.
  Future<double Function({required List<String> namespacedTags, String title, String host, int? pages})?> doujinPartsScorer() async {
    if (!recommendationsEnabled) return null;
    final FtrlModel model = await modelFor(RecommenderWorld.doujin);
    if (model.updates == 0) return null;
    return ({required List<String> namespacedTags, String title = '', String host = '', int? pages}) =>
        model.predict(ItemFeatures.ofDoujinParts(namespacedTags: namespacedTags, title: title, host: host, pages: pages).hashes);
  }

  /// The score of a remembered gallery (namespaced tags, no item).
  Future<double> scoreDoujinParts({required List<String> namespacedTags, String title = '', String host = '', int? pages}) async {
    if (!recommendationsEnabled) return 0.5;
    final FtrlModel model = await modelFor(RecommenderWorld.doujin);
    if (model.updates == 0) return 0.5;
    FeatureVector f = ItemFeatures.ofDoujinParts(namespacedTags: namespacedTags, title: title, host: host, pages: pages);
    final EncoderHandler? encoder = _encoder;
    if (encoder != null) {
      try {
        final Float32List? v = await encoder.embedText(EncoderHandler.textOfDoujinParts(namespacedTags: namespacedTags, title: title));
        if (v != null) f = ItemFeatures.withEmbedding(f, v, model: encoder.modelId, taste: _taste[RecommenderWorld.doujin]?.vectorFor(encoder.modelId));
      } catch (_) {}
    }
    return model.predict(f.hashes, values: f.values);
  }

  /// [items] ordered for the user: [mix] of the model's score against the
  /// order they came in (a blend's own facet order still counts), with every
  /// [explorationEvery]th slot given to the best item the model has not
  /// seen. The input order when recommendations are off or nothing is learned.
  Future<List<BooruItem>> rerank(
    List<BooruItem> items, {
    RecommenderWorld? world,
    BooruHandler? handler,
    double mix = 0.7,
    bool explore = true,
  }) async {
    if (!recommendationsEnabled || items.length < 2) return items;
    final RecommenderWorld w = world ?? ItemFeatures.worldOf(items.first);
    final FtrlModel model = await modelFor(w);
    if (model.updates == 0) return items;
    final int n = items.length;
    final List<Float32List?> embeddings = await _embeddings(items, handler: handler);
    final List<({BooruItem item, double combined, double novelty, int index})> scored = [];
    for (int i = 0; i < n; i++) {
      final FeatureVector f = _featuresFor(items[i], w, handler: handler, embedding: embeddings[i]);
      final double p = model.predict(f.hashes, values: f.values);
      final double position = 1 - i / (n - 1);
      // Novelty is judged on what the item is, not on the encoder's components.
      scored.add((item: items[i], combined: mix * p + (1 - mix) * position, novelty: model.novelty(f.loggedHashes), index: i));
    }
    scored.sort((a, b) {
      final int byScore = b.combined.compareTo(a.combined);
      return byScore != 0 ? byScore : a.index.compareTo(b.index);
    });
    if (!explore) return [for (final s in scored) s.item];
    final List<BooruItem> out = [];
    final List<({BooruItem item, double combined, double novelty, int index})> remaining = List.of(scored);
    while (remaining.isNotEmpty) {
      if ((out.length + 1) % explorationEvery == 0) {
        final int novel = remaining.indexWhere((s) => s.novelty >= explorationNovelty);
        if (novel > 0) {
          out.add(remaining.removeAt(novel).item);
          continue;
        }
      }
      out.add(remaining.removeAt(0).item);
    }
    return out;
  }

  /// Terms retrieval can ask a site for, from the strongest liked features:
  /// `zun` from `type:artist:zun`, `parody:genshin_impact` from
  /// `ns:parody:genshin_impact`. [prefix] narrows to one feature kind. Empty
  /// when recommendations are off or nothing is learned.
  Future<List<String>> seedTerms(RecommenderWorld world, {String? prefix, int limit = 24}) async {
    if (!recommendationsEnabled) return const [];
    final FtrlModel model = await modelFor(world);
    if (model.updates == 0) return const [];
    final List<({int hash, double weight})> top = model.topWeights(200, positive: true);
    final Map<int, String> names = await _names(world, [for (final t in top) t.hash]);
    final Set<String> out = {};
    for (final t in top) {
      final String? name = names[t.hash];
      if (name == null) continue;
      if (prefix != null && !name.startsWith(prefix)) continue;
      if (!ItemFeatures.isSeedable(name)) continue;
      out.add(ItemFeatures.seedTerm(name));
      if (out.length >= limit) break;
    }
    return out.toList();
  }

  Future<RecommenderReport> report(RecommenderWorld world, {int count = 10}) async {
    final FtrlModel model = await modelFor(world);
    int events = 0;
    try {
      events = await _db.countInteractions(world.name);
    } catch (_) {}
    final List<({int hash, double weight})> liked = model.topWeights(count, positive: true);
    final List<({int hash, double weight})> disliked = model.topWeights(count, positive: false);
    final Map<int, String> names = await _names(world, [for (final t in [...liked, ...disliked]) t.hash]);
    List<({String name, double weight})> named(List<({int hash, double weight})> rows) => [
      for (final r in rows)
        if (names[r.hash] case final String name) (name: name, weight: r.weight),
    ];
    int encoderFeatures = 0;
    final EncoderHandler? encoder = EncoderHandler.maybe;
    if (encoder != null && encoder.modelId.isNotEmpty && encoder.dim > 0) {
      for (final int h in ItemFeatures.embeddingHashes(encoder.modelId, encoder.dim)) {
        if (model.weight(h) != 0) encoderFeatures++;
      }
    }
    return RecommenderReport(
      world: world,
      events: events,
      updates: model.updates,
      lastUpdate: model.lastUpdate,
      liked: named(liked),
      disliked: named(disliked),
      encoderFeatures: encoderFeatures,
      tasteCount: _taste[world]?.count ?? 0,
    );
  }

  Future<Map<int, String>> _names(RecommenderWorld world, List<int> hashes) async {
    try {
      return await _db.featureNames(world.name, hashes);
    } catch (_) {
      return const {};
    }
  }

  /// Forgets everything the world learned: the log, the names, the weights,
  /// the file.
  Future<void> reset(RecommenderWorld world) async {
    // A load in flight would finish after the fresh model was put in place
    // and bring the old weights back.
    final Future<FtrlModel>? loading = _loading[world];
    if (loading != null) {
      try {
        await loading;
      } catch (_) {}
    }
    _saveTimer?.cancel();
    _saveTimer = null;
    _dirty.remove(world);
    _models[world] = FtrlModel();
    _exposed.clear();
    _dismissed[world]?.clear();
    _taste[world] = _Taste.empty();
    try {
      await _db.clearInteractions(world.name);
      await _db.clearFeatureNames(world.name);
    } catch (e, s) {
      Logger.Inst().log('clearing the ${world.name} log failed: $e', className, 'reset', LogTypes.exception, s: s);
    }
    for (final String path in [fileFor(world), tasteFileFor(world)]) {
      try {
        final File file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  @visibleForTesting
  void resetForTests() {
    _saveTimer?.cancel();
    _saveTimer = null;
    _models.clear();
    _loading.clear();
    _dirty.clear();
    _exposed.clear();
    _interacted.clear();
    _rendered.clear();
    _dismissed.clear();
    _taste.clear();
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
