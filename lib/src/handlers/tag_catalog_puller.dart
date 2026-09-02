import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/handlers/booru_tag_store.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// Progress of one pull, as the chips and the picker show it.
class TagCatalogPullState {
  const TagCatalogPullState({
    this.running = false,
    this.shard = 0,
    this.shards,
    this.stored = 0,
    this.error,
    this.done = false,
  });

  final bool running;
  final int shard;

  /// Total shards when known; null = indeterminate.
  final int? shards;
  final int stored;
  final String? error;

  /// The walk reached the end (not merely stopped).
  final bool done;

  double? get progress => (shards == null || shards == 0) ? null : (shard / shards!).clamp(0, 1);

  TagCatalogPullState copyWith({bool? running, int? shard, int? shards, int? stored, String? error, bool? done}) =>
      TagCatalogPullState(
        running: running ?? this.running,
        shard: shard ?? this.shard,
        shards: shards ?? this.shards,
        stored: stored ?? this.stored,
        error: error,
        done: done ?? this.done,
      );
}

/// Walks a source's tag index in the background, a shard at a time, into
/// [BooruTagStore] — the tag browser's pull loop moved out of its widget so
/// closing the picker does not abandon a hitomi walk 30 requests in.
///
/// One job per source host at a time; a second namespace tapped while a job
/// runs waits its turn. Resumable: an interrupted or failed walk keeps what
/// it stored and continues from the next shard on the next pull.
class TagCatalogPuller {
  TagCatalogPuller._();

  static final TagCatalogPuller instance = TagCatalogPuller._();

  final Map<String, ValueNotifier<TagCatalogPullState>> _states = {};
  final Map<String, int> _resume = {};
  final Set<String> _cancelled = {};
  final Set<String> _busyHosts = {};

  /// Test hook: where shards are written.
  Future<int> Function(Booru booru, List<BooruTagEntry> entries) recordFn = BooruTagStore.record;

  static String hostOf(Booru booru) => BooruTagStore.keyFor(booru);

  static String keyFor(Booru booru, TagCatalogSource catalog, String namespace) =>
      '${hostOf(booru)}/${catalog.sharedShards ? '*' : namespace}';

  ValueNotifier<TagCatalogPullState> stateFor(Booru booru, TagCatalogSource catalog, String namespace) =>
      _states.putIfAbsent(keyFor(booru, catalog, namespace), () => ValueNotifier(const TagCatalogPullState()));

  bool isRunning(Booru booru, TagCatalogSource catalog, String namespace) =>
      stateFor(booru, catalog, namespace).value.running;

  /// Forget the resume point so the next pull starts from shard 0.
  void resetResume(Booru booru, TagCatalogSource catalog, String namespace) =>
      _resume.remove(keyFor(booru, catalog, namespace));

  void cancel(Booru booru, TagCatalogSource catalog, String namespace) =>
      _cancelled.add(keyFor(booru, catalog, namespace));

  Future<void> pull(Booru booru, TagCatalogSource catalog, String namespace) async {
    final String key = keyFor(booru, catalog, namespace);
    final ValueNotifier<TagCatalogPullState> state = stateFor(booru, catalog, namespace);
    if (state.value.running) return;
    _cancelled.remove(key);

    final String host = hostOf(booru);
    // Wait for the host's current job; the site sees one walk at a time.
    while (_busyHosts.contains(host)) {
      if (_cancelled.contains(key)) return;
      await Future.delayed(const Duration(milliseconds: 200));
    }
    _busyHosts.add(host);

    final String shardNamespace = catalog.sharedShards ? '' : namespace;
    final int? total = catalog.sharedShards ? catalog.sharedShardCount : catalog.namespaceFor(namespace)?.shards;
    int shard = _resume[key] ?? 0;
    // maxShards bounds ONE pull; the next pull continues from the resume point.
    final int? perPull = catalog.sharedShards ? null : catalog.namespaceFor(namespace)?.maxShards;
    final int? cap = perPull == null ? null : shard + perPull;
    int stored = 0;
    bool finished = false;
    state.value = TagCatalogPullState(running: true, shard: shard, shards: total, stored: 0);
    _log('pull ${key.replaceAll('*', 'all')} from shard $shard');

    try {
      while (!_cancelled.contains(key)) {
        if (total != null && shard >= total) {
          finished = true;
          break;
        }
        if (cap != null && shard >= cap) break;
        final List<BooruTagEntry>? got = await catalog.shardAt(shardNamespace, shard);
        if (got == null) {
          finished = true;
          break;
        }
        if (got.isNotEmpty) stored += await recordFn(booru, got);
        shard++;
        _resume[key] = shard;
        state.value = state.value.copyWith(shard: shard, stored: stored);
        if (catalog.shardDelay > Duration.zero) await Future.delayed(catalog.shardDelay);
      }
      if (finished) _resume.remove(key);
      state.value = state.value.copyWith(running: false, done: finished, stored: stored);
      _log('pull ${key.replaceAll('*', 'all')}: ${finished ? 'complete' : 'stopped'} at shard $shard, stored $stored');
    } catch (e, s) {
      // What was stored is saved and useful: a stop, not a failure.
      Logger.Inst().log('pull $key stopped: $e', 'TagCatalogPuller', 'pull', LogTypes.exception, s: s);
      state.value = state.value.copyWith(running: false, stored: stored, error: e.toString());
    } finally {
      _busyHosts.remove(host);
      _cancelled.remove(key);
    }
  }

  void _log(String message) => Logger.Inst().log('tag catalog: $message', 'TagCatalogPuller', 'pull', LogTypes.booruHandlerInfo);
}
