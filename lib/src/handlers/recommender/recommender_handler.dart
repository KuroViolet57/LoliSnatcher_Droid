import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:get_it/get_it.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/database_handler.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/ftrl_model.dart';
import 'package:lolisnatcher/src/handlers/recommender/item_features.dart';
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
  });

  final RecommenderWorld world;

  /// Logged interactions.
  final int events;

  /// Training steps the model has taken (the log replayed counts too).
  final int updates;
  final DateTime? lastUpdate;
  final List<({String name, double weight})> liked;
  final List<({String name, double weight})> disliked;
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
    return _models[world] = model;
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
      } catch (e, s) {
        Logger.Inst().log('saving the ${world.name} model failed: $e', className, 'flush', LogTypes.exception, s: s);
        _dirty.add(world);
      }
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
    final FeatureVector features = ItemFeatures.of(item, world, handler: handler, namespaces: namespaces);
    if (features.isEmpty) return;
    await _learn(world, key, _hostOf(item), kind, value, features, reward);
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
    for (final BooruItem item in items) {
      final String key = keyOf(item);
      if (key.isEmpty) continue;
      final RecommenderWorld world = ItemFeatures.worldOf(item);
      current[key] = (world: world, host: _hostOf(item), features: ItemFeatures.of(item, world, handler: handler));
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
        await _db.addInteraction(world: world.name, itemKey: key, host: host, kind: kind.name, value: value, features: features.hashes);
        await _db.addFeatureNames(world.name, {for (int i = 0; i < features.hashes.length; i++) features.hashes[i]: features.names[i]});
        if (++_sincePrune >= 200) {
          _sincePrune = 0;
          await _db.pruneInteractions(keep: logCap);
        }
      } catch (e, s) {
        Logger.Inst().log('logging an interaction failed: $e', className, '_learn', LogTypes.exception, s: s);
      }
    }
    model.update(features.hashes, positive: reward.positive, weight: reward.weight);
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
    return model.predict(ItemFeatures.of(item, w, handler: handler, namespaces: namespaces).hashes);
  }

  /// A synchronous scorer over the world's model for callers that rank in
  /// a loop (the doujin Recommended strip); null when recommendations are
  /// off or nothing was learned.
  Future<double Function(BooruItem)?> scorer(RecommenderWorld world, {BooruHandler? handler}) async {
    if (!recommendationsEnabled) return null;
    final FtrlModel model = await modelFor(world);
    if (model.updates == 0) return null;
    return (BooruItem item) => model.predict(ItemFeatures.of(item, world, handler: handler).hashes);
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
    return model.predict(ItemFeatures.ofDoujinParts(namespacedTags: namespacedTags, title: title, host: host, pages: pages).hashes);
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
    final List<({BooruItem item, double combined, double novelty, int index})> scored = [];
    for (int i = 0; i < n; i++) {
      final List<int> features = ItemFeatures.of(items[i], w, handler: handler).hashes;
      final double p = model.predict(features);
      final double position = 1 - i / (n - 1);
      scored.add((item: items[i], combined: mix * p + (1 - mix) * position, novelty: model.novelty(features), index: i));
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
    return RecommenderReport(
      world: world,
      events: events,
      updates: model.updates,
      lastUpdate: model.lastUpdate,
      liked: named(liked),
      disliked: named(disliked),
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
    try {
      await _db.clearInteractions(world.name);
      await _db.clearFeatureNames(world.name);
    } catch (e, s) {
      Logger.Inst().log('clearing the ${world.name} log failed: $e', className, 'reset', LogTypes.exception, s: s);
    }
    try {
      final File file = File(fileFor(world));
      if (await file.exists()) await file.delete();
    } catch (_) {}
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
  }
}
