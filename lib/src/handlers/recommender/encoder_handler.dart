import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';

import 'package:lolisnatcher/src/boorus/doujin/doujin_tag_namespaces.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/item_features.dart';
import 'package:lolisnatcher/src/handlers/recommender/onnx_embedding_runner.dart';
import 'package:lolisnatcher/src/handlers/recommender/wordpiece_tokenizer.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// A sentence encoder the user can download from Hugging Face (r34).
///
/// Presets are ONNX exports with a BERT WordPiece vocabulary; any other repo
/// with the same layout (`onnx/model_quantized.onnx`, `vocab.txt`,
/// `tokenizer_config.json`, `config.json`) works too. The encoder reads an
/// item's title and tags into one vector; the learner takes the vector's
/// components as features, so it can learn that two things it never saw
/// together read alike. The transformer is frozen — it understands
/// language; the learner on top is what learns the user.
class EncoderPreset {
  const EncoderPreset({
    required this.id,
    required this.repo,
    required this.label,
    required this.description,
    required this.bytes,
    required this.dim,
    required this.lowerCase,
    required this.tokenTypeIds,
  });

  final String id;
  final String repo;
  final String label;
  final String description;

  /// The model file's size.
  final int bytes;
  final int dim;
  final bool lowerCase;
  final bool tokenTypeIds;

  static const EncoderPreset english = EncoderPreset(
    id: 'english',
    repo: 'Xenova/all-MiniLM-L6-v2',
    label: 'English (small)',
    description: 'all-MiniLM-L6-v2, 8-bit: 23 MB, 384 dimensions. Fast; English tags and titles; ideographs one at a time.',
    bytes: 22972370,
    dim: 384,
    lowerCase: true,
    tokenTypeIds: true,
  );

  static const EncoderPreset multilingual = EncoderPreset(
    id: 'multilingual',
    repo: 'Xenova/distiluse-base-multilingual-cased-v2',
    label: 'Multilingual',
    description: 'distiluse-base-multilingual-cased-v2, 8-bit: 135 MB, 768 dimensions. English, Chinese, Japanese and 47 other languages: Japanese and Chinese titles read as words, not characters; slower.',
    bytes: 135317281,
    dim: 768,
    lowerCase: false,
    tokenTypeIds: false,
  );

  static const List<EncoderPreset> values = [english, multilingual];

  static EncoderPreset? byId(String id) {
    for (final EncoderPreset p in values) {
      if (p.id == id) return p;
    }
    return null;
  }
}

enum EncoderState { none, downloading, ready, error }

@immutable
class EncoderStatus {
  const EncoderStatus({
    required this.state,
    this.progress = 0,
    this.message = '',
    this.repo = '',
    this.dim = 0,
    this.bytes = 0,
    this.downloadedAt,
  });

  static const EncoderStatus none = EncoderStatus(state: EncoderState.none);

  final EncoderState state;
  final double progress;
  final String message;
  final String repo;
  final int dim;
  final int bytes;
  final DateTime? downloadedAt;
}

/// Runs the model: token ids and mask `[batch][length]` in, token
/// embeddings `[batch * length * dim]` out (or pooled `[batch * dim]`).
abstract class EmbeddingRunner {
  int get dim;
  bool get wantsTokenTypeIds;
  Future<Float32List> run(List<List<int>> ids, List<List<int>> mask);
  Future<void> close();
}

typedef EncoderFetcher = Future<void> Function(String url, File to, {void Function(int received, int total)? onProgress, CancelToken? cancelToken});
typedef RunnerFactory = EmbeddingRunner Function(String modelPath, {required bool wantsTokenTypeIds});

class EncoderHandler {
  static EncoderHandler get instance => GetIt.instance<EncoderHandler>();

  static EncoderHandler register() {
    if (!GetIt.instance.isRegistered<EncoderHandler>()) {
      GetIt.instance.registerSingleton(EncoderHandler());
    }
    return instance;
  }

  static void unregister() {
    if (GetIt.instance.isRegistered<EncoderHandler>()) {
      GetIt.instance.unregister<EncoderHandler>();
    }
  }

  static EncoderHandler? get maybe => GetIt.instance.isRegistered<EncoderHandler>() ? instance : null;

  static const String className = 'EncoderHandler';

  /// The model file inside a Hugging Face repo.
  static const String modelFileName = 'onnx/model_quantized.onnx';
  static const List<String> _sideFiles = ['vocab.txt', 'tokenizer_config.json', 'config.json'];
  static const int _batch = 8;
  static const int _maxLength = 96;
  static const int _memoryCap = 4000;

  /// Stored vectors are pruned every [pruneEvery] writes to the newest
  /// [pruneKeep] — here, not on the learner's tick, so a switched-off
  /// learner does not let the table grow without bound (review).
  static const int defaultPruneEvery = 200;
  static const int defaultPruneKeep = 6000;
  @visibleForTesting
  static int pruneEvery = defaultPruneEvery;
  @visibleForTesting
  static int pruneKeep = defaultPruneKeep;
  int _putsSincePrune = 0;

  /// Text vectors are stored under this prefix, by a hash of the text.
  static const String _textKeyPrefix = 'text:';

  final ValueNotifier<EncoderStatus> status = ValueNotifier(EncoderStatus.none);

  /// Test seams: how files come down, how the model runs.
  EncoderFetcher fetcher = _dioFetch;
  RunnerFactory runnerFactory = _onnxRunner;

  SettingsHandler get _settings => SettingsHandler.instance;

  WordPieceTokenizer? _tokenizer;
  EmbeddingRunner? _runner;
  String _slug = '';
  int _dim = 0;
  int _maxLen = _maxLength;
  bool _lowerCase = true;
  bool _tokenTypeIds = true;
  CancelToken? _downloading;
  Future<void>? _loading;

  /// Vectors by item key (`k:`) and by text (`t:`), most recent last.
  final LinkedHashMap<String, Float32List> _memory = LinkedHashMap();

  static String fileUrl(String repo, String file) => 'https://huggingface.co/$repo/resolve/main/$file';

  /// The repo behind a setting value: a preset id, or a repo id as typed.
  static String repoOf(String setting) => EncoderPreset.byId(setting)?.repo ?? setting.trim();

  static String slugOf(String repo) => repo.trim().toLowerCase().replaceAll('/', '__').replaceAll(RegExp(r'[^a-z0-9._\-]'), '-');

  String dirFor(String setting) => '${_settings.path}encoder${Platform.pathSeparator}${slugOf(repoOf(setting))}${Platform.pathSeparator}';

  /// The encoder is downloaded and the switch is on.
  bool get enabled => _settings.aiEncoder && status.value.state == EncoderState.ready;

  /// Names the model in feature names and cache rows.
  String get modelId => _slug;

  int get dim => _dim;

  // ── files ──

  /// Reads the manifest of the configured model; ready when its files are there.
  Future<void> refresh() async {
    final String setting = _settings.encoderModel;
    if (setting.trim().isEmpty) {
      _apply(EncoderStatus.none, slug: '');
      return;
    }
    final String dir = dirFor(setting);
    final File manifest = File('${dir}manifest.json');
    final File model = File('${dir}model.onnx');
    final File vocab = File('${dir}vocab.txt');
    if (!manifest.existsSync() || !model.existsSync() || !vocab.existsSync()) {
      _apply(const EncoderStatus(state: EncoderState.none, message: 'The model files are missing; download again.'), slug: '');
      return;
    }
    try {
      final Map<String, dynamic> m = jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
      _dim = (m['dim'] as num?)?.toInt() ?? 0;
      _lowerCase = m['lowerCase'] as bool? ?? true;
      _tokenTypeIds = m['tokenTypeIds'] as bool? ?? true;
      _maxLen = math.min(_maxLength, (m['maxLength'] as num?)?.toInt() ?? _maxLength);
      _apply(
        EncoderStatus(
          state: EncoderState.ready,
          repo: m['repo'] as String? ?? repoOf(setting),
          dim: _dim,
          bytes: (m['bytes'] as num?)?.toInt() ?? model.lengthSync(),
          downloadedAt: DateTime.tryParse(m['downloadedAt'] as String? ?? ''),
        ),
        slug: slugOf(m['repo'] as String? ?? repoOf(setting)),
      );
    } catch (e, s) {
      Logger.Inst().log('encoder manifest unreadable: $e', className, 'refresh', LogTypes.exception, s: s);
      _apply(EncoderStatus(state: EncoderState.error, message: 'The model manifest is unreadable: $e'), slug: '');
    }
  }

  void _apply(EncoderStatus s, {required String slug}) {
    if (slug != _slug) {
      _memory.clear();
      _tokenizer = null;
      final EmbeddingRunner? old = _runner;
      _runner = null;
      _loading = null;
      if (old != null) old.close().catchError((_) {});
    }
    _slug = slug;
    status.value = s;
  }

  /// Downloads [setting] (a preset id or a repo id) and makes it the model.
  Future<bool> download(String setting) async {
    if (_downloading != null) return false;
    final String repo = repoOf(setting);
    if (repo.isEmpty || !repo.contains('/')) {
      status.value = const EncoderStatus(state: EncoderState.error, message: 'A Hugging Face repo id looks like owner/model.');
      return false;
    }
    final EncoderPreset? preset = EncoderPreset.byId(setting);
    final String dir = dirFor(setting);
    final String tmp = '${_settings.path}encoder${Platform.pathSeparator}.download-${slugOf(repo)}${Platform.pathSeparator}';
    final CancelToken cancel = _downloading = CancelToken();
    status.value = EncoderStatus(state: EncoderState.downloading, repo: repo, bytes: preset?.bytes ?? 0);
    try {
      final Directory tmpDir = Directory(tmp);
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
      tmpDir.createSync(recursive: true);
      final File model = File('${tmp}model.onnx');
      double shown = -1;
      await fetcher(
        fileUrl(repo, modelFileName),
        model,
        cancelToken: cancel,
        onProgress: (int received, int total) {
          final int expected = total > 0 ? total : (preset?.bytes ?? 0);
          final double progress = expected > 0 ? (received / expected).clamp(0, 1).toDouble() : 0;
          // Dio reports every chunk; the page is told every half percent.
          if (progress < 1 && progress - shown < 0.005) return;
          shown = progress;
          status.value = EncoderStatus(state: EncoderState.downloading, repo: repo, bytes: expected, progress: progress);
        },
      );
      for (final String name in _sideFiles) {
        await fetcher(fileUrl(repo, name), File('$tmp$name'), cancelToken: cancel);
      }
      final Map<String, dynamic> config = _json(File('${tmp}config.json'));
      final Map<String, dynamic> tokenizerConfig = _json(File('${tmp}tokenizer_config.json'));
      final int dim = (config['hidden_size'] as num?)?.toInt() ?? (config['dim'] as num?)?.toInt() ?? preset?.dim ?? 384;
      final bool lowerCase = tokenizerConfig['do_lower_case'] as bool? ?? preset?.lowerCase ?? true;
      final bool tokenTypeIds = preset?.tokenTypeIds ?? (config['model_type']?.toString() != 'distilbert');
      final int maxLength = math.min(_maxLength, (tokenizerConfig['model_max_length'] as num?)?.toInt() ?? _maxLength);
      final int bytes = model.lengthSync();
      File('${tmp}manifest.json').writeAsStringSync(
        jsonEncode({
          'repo': repo,
          'setting': setting,
          'dim': dim,
          'bytes': bytes,
          'lowerCase': lowerCase,
          'tokenTypeIds': tokenTypeIds,
          'maxLength': maxLength,
          'downloadedAt': DateTime.now().toIso8601String(),
        }),
      );
      // The running session, tokenizer and caches belong to the files about
      // to be replaced — even when the repo is the same (review).
      await close();
      _apply(status.value, slug: '');
      final Directory target = Directory(dir);
      if (target.existsSync()) target.deleteSync(recursive: true);
      tmpDir.renameSync(target.path.substring(0, target.path.length - 1));
      _settings.encoderModel = setting;
      unawaited(_settings.saveSettings(restate: false));
      await refresh();
      return status.value.state == EncoderState.ready;
    } catch (e, s) {
      final String why = e is DioException ? (e.message ?? e.error?.toString() ?? e.type.name) : '$e';
      Logger.Inst().log('encoder download of $repo failed: $e', className, 'download', LogTypes.exception, s: s);
      try {
        final Directory tmpDir = Directory(tmp);
        if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
      } catch (_) {}
      status.value = EncoderStatus(state: EncoderState.error, repo: repo, message: cancel.isCancelled ? 'Download cancelled.' : why);
      return false;
    } finally {
      _downloading = null;
    }
  }

  void cancelDownload() => _downloading?.cancel('cancelled by the user');

  /// Removes the model's files and the setting.
  Future<void> delete() async {
    final String setting = _settings.encoderModel;
    await close();
    if (setting.trim().isNotEmpty) {
      try {
        final Directory dir = Directory(dirFor(setting));
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      } catch (e, s) {
        Logger.Inst().log('deleting the encoder failed: $e', className, 'delete', LogTypes.exception, s: s);
      }
      try {
        await _settings.dbHandler.clearEmbeddings(_slug);
      } catch (_) {}
    }
    _settings.encoderModel = '';
    unawaited(_settings.saveSettings(restate: false));
    _apply(EncoderStatus.none, slug: '');
  }

  Future<void> close() async {
    final EmbeddingRunner? r = _runner;
    _runner = null;
    _loading = null;
    if (r != null) {
      try {
        await r.close();
      } catch (_) {}
    }
  }

  static Map<String, dynamic> _json(File f) {
    try {
      final dynamic v = jsonDecode(f.readAsStringSync());
      return v is Map<String, dynamic> ? v : const {};
    } catch (_) {
      return const {};
    }
  }

  // ── text ──

  /// What the encoder reads for an item: the title (doujins), then the
  /// names (artist, parody, character) and tags as words.
  static String textOf(BooruItem item, RecommenderWorld world, {BooruHandler? handler}) {
    final List<String> first = [];
    final List<String> rest = [];
    for (final Tag tag in item.tagsList) {
      final String raw = tag.fullString;
      final int colon = raw.indexOf(':');
      final String prefix = colon > 0 ? raw.substring(0, colon).toLowerCase() : '';
      // A namespace the doujin sites use is dropped from the words; any
      // other colon is part of the tag.
      final bool namespaced = prefix.isNotEmpty && ItemFeatures.doujinNamespaces.contains(prefix);
      final String ns = namespaced ? prefix : '';
      if (ns == 'language' || ns == 'category' || ns == 'type') continue;
      final String name = _words(normalizeDoujinTagName(namespaced ? raw.substring(colon + 1) : raw));
      if (name.isEmpty) continue;
      final bool leads = tag.tagType == TagType.artist ||
          tag.tagType == TagType.copyright ||
          tag.tagType == TagType.character ||
          ns == 'artist' ||
          ns == 'group' ||
          ns == 'parody' ||
          ns == 'series' ||
          ns == 'character';
      (leads ? first : rest).add(name);
    }
    final List<String> tags = [...first, ...rest].take(32).toList();
    final String title = world == RecommenderWorld.doujin
        ? (item.description ?? '').split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '').trim()
        : '';
    return _compose(title, tags);
  }

  static String textOfDoujinParts({required List<String> namespacedTags, String title = ''}) {
    final List<String> first = [];
    final List<String> rest = [];
    for (final String raw in namespacedTags) {
      final int colon = raw.indexOf(':');
      final String ns = colon > 0 ? raw.substring(0, colon).toLowerCase() : '';
      if (ns == 'language' || ns == 'category' || ns == 'type') continue;
      final String name = _words(normalizeDoujinTagName(colon > 0 ? raw.substring(colon + 1) : raw));
      if (name.isEmpty) continue;
      (const {'artist', 'group', 'parody', 'series', 'character'}.contains(ns) ? first : rest).add(name);
    }
    return _compose(title.trim(), [...first, ...rest].take(32).toList());
  }

  static String _words(String s) => s.replaceAll('_', ' ').trim();

  static String _compose(String title, List<String> tags) {
    final String t = tags.join(', ');
    if (title.isEmpty) return t;
    if (t.isEmpty) return title;
    return '$title. $t';
  }

  // ── vectors ──

  Future<void> _ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final String dir = dirFor(_settings.encoderModel);
      final String vocab = await File('${dir}vocab.txt').readAsString();
      _tokenizer = WordPieceTokenizer.fromVocabText(vocab, lowerCase: _lowerCase);
      _runner = runnerFactory('${dir}model.onnx', wantsTokenTypeIds: _tokenTypeIds);
    } catch (e) {
      _loading = null;
      rethrow;
    }
  }

  /// The model could not be run: said on the settings page, and not tried
  /// again until a [refresh] (a restart, a new download) — never "Ready"
  /// while every page silently fails (review).
  void _fail(Object e) {
    Logger.Inst().log('encoder failed: $e', className, '_fail', LogTypes.exception);
    _loading = null;
    final EmbeddingRunner? r = _runner;
    _runner = null;
    if (r != null) r.close().catchError((_) {});
    status.value = EncoderStatus(
      state: EncoderState.error,
      repo: status.value.repo,
      dim: status.value.dim,
      bytes: status.value.bytes,
      downloadedAt: status.value.downloadedAt,
      message: 'The model could not be run: $e',
    );
  }

  /// The width of the vectors the model really returns; the manifest's
  /// number came from `config.json`, which a custom repo may spell
  /// differently (review). `null` when the output does not divide.
  int? _dimFromOutput(int flatLength, int batch, int length) {
    if (batch <= 0 || length <= 0) return null;
    if (flatLength % (batch * length) == 0) return flatLength ~/ (batch * length);
    if (flatLength % batch == 0) return flatLength ~/ batch;
    return null;
  }

  static String textKey(String text) {
    // FNV-1a over the text (32-bit) with its length: short, stable, one row
    // per text.
    final List<int> bytes = utf8.encode(text);
    int h = 0x811c9dc5;
    for (final int b in bytes) {
      h ^= b;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return '$_textKeyPrefix${h.toRadixString(16)}-${bytes.length}';
  }

  Future<void> _store(Map<String, Float32List> fresh) async {
    if (fresh.isEmpty || !_settings.dbEnabled) return;
    try {
      await _settings.dbHandler.putEmbeddings(_slug, fresh);
      _putsSincePrune += fresh.length;
      if (_putsSincePrune >= pruneEvery) {
        _putsSincePrune = 0;
        await _settings.dbHandler.pruneEmbeddings(keep: pruneKeep);
      }
    } catch (e, s) {
      Logger.Inst().log('storing embeddings failed: $e', className, '_store', LogTypes.exception, s: s);
    }
  }

  Float32List? _remember(String key, Float32List? v) {
    if (v == null) return null;
    _memory.remove(key);
    _memory[key] = v;
    while (_memory.length > _memoryCap) {
      _memory.remove(_memory.keys.first);
    }
    return v;
  }

  Float32List? _recall(String key) {
    final Float32List? v = _memory.remove(key);
    if (v != null) _memory[key] = v;
    return v;
  }

  /// The vector of one text; null when the encoder is off or fails.
  Future<Float32List?> embedText(String text) async => (await embedTexts([text])).first;

  Future<List<Float32List?>> embedTexts(List<String> texts) async {
    final List<Float32List?> out = List.filled(texts.length, null);
    if (!enabled || texts.isEmpty) return out;
    final List<int> missing = [];
    for (int i = 0; i < texts.length; i++) {
      out[i] = _recall('t:${texts[i]}');
      if (out[i] == null) missing.add(i);
    }
    if (missing.isEmpty) return out;
    // Text vectors are stored like item vectors: a history read on every
    // start is embedded once, not once per start (review).
    if (_settings.dbEnabled) {
      try {
        final Map<String, Float32List> stored = await _settings.dbHandler.getEmbeddings(_slug, [for (final int i in missing) textKey(texts[i])]);
        missing.removeWhere((int i) {
          final Float32List? v = stored[textKey(texts[i])];
          if (v == null) return false;
          out[i] = _remember('t:${texts[i]}', v);
          return true;
        });
      } catch (e, s) {
        Logger.Inst().log('reading text embeddings failed: $e', className, 'embedTexts', LogTypes.exception, s: s);
      }
    }
    if (missing.isEmpty) return out;
    final Map<String, Float32List> fresh = {};
    try {
      await _ensureLoaded();
      final WordPieceTokenizer tokenizer = _tokenizer!;
      final EmbeddingRunner runner = _runner!;
      for (int start = 0; start < missing.length; start += _batch) {
        final List<int> chunk = missing.sublist(start, math.min(start + _batch, missing.length));
        final List<TokenizedText> encoded = [for (final int i in chunk) tokenizer.encode(texts[i], maxLength: _maxLen)];
        final int length = encoded.map((e) => e.ids.length).reduce(math.max);
        final List<List<int>> ids = [
          for (final TokenizedText e in encoded) [...e.ids, ...List.filled(length - e.ids.length, tokenizer.padId)],
        ];
        final List<List<int>> mask = [
          for (final TokenizedText e in encoded) [...e.mask, ...List.filled(length - e.mask.length, 0)],
        ];
        final Float32List flat = await runner.run(ids, mask);
        final int dim = _dimFromOutput(flat.length, chunk.length, length) ?? runner.dim;
        if (dim != _dim) {
          Logger.Inst().log('encoder returns $dim-wide vectors (the manifest said $_dim)', className, 'embedTexts', LogTypes.booruHandlerInfo);
          _dim = dim;
          if (status.value.state == EncoderState.ready) status.value = EncoderStatus(state: EncoderState.ready, repo: status.value.repo, dim: dim, bytes: status.value.bytes, downloadedAt: status.value.downloadedAt);
        }
        for (int b = 0; b < chunk.length; b++) {
          final Float32List v = _pool(flat, b, chunk.length, length, mask[b], dim);
          out[chunk[b]] = _remember('t:${texts[chunk[b]]}', v);
          fresh[textKey(texts[chunk[b]])] = v;
        }
      }
    } catch (e) {
      _fail(e);
    }
    await _store(fresh);
    return out;
  }

  /// Mean of the token vectors under the mask, unit length. A model that
  /// hands back one vector per text already is taken as is.
  static Float32List _pool(Float32List flat, int b, int batch, int length, List<int> mask, int dim) {
    final Float32List out = Float32List(dim);
    if (flat.length == batch * dim) {
      out.setAll(0, flat.sublist(b * dim, (b + 1) * dim));
    } else {
      int n = 0;
      for (int t = 0; t < length; t++) {
        if (mask[t] == 0) continue;
        final int base = (b * length + t) * dim;
        if (base + dim > flat.length) break;
        for (int d = 0; d < dim; d++) {
          out[d] += flat[base + d];
        }
        n++;
      }
      if (n > 0) {
        for (int d = 0; d < dim; d++) {
          out[d] /= n;
        }
      }
    }
    double norm = 0;
    for (int d = 0; d < dim; d++) {
      norm += out[d] * out[d];
    }
    norm = math.sqrt(norm);
    if (norm > 0) {
      for (int d = 0; d < dim; d++) {
        out[d] /= norm;
      }
    }
    return out;
  }

  static String keyOf(BooruItem item) => item.postURL.isNotEmpty ? item.postURL : item.fileURL;

  /// The items' vectors, from memory, the database, or the model — in that
  /// order; null where the encoder is off or the item has nothing to read.
  Future<List<Float32List?>> embedItems(List<BooruItem> items, {BooruHandler? handler}) async {
    final List<Float32List?> out = List.filled(items.length, null);
    if (!enabled || items.isEmpty) return out;
    final List<int> missing = [];
    for (int i = 0; i < items.length; i++) {
      out[i] = _recall('k:${keyOf(items[i])}');
      if (out[i] == null) missing.add(i);
    }
    if (missing.isEmpty) return out;
    if (_settings.dbEnabled) {
      try {
        final Map<String, Float32List> stored = await _settings.dbHandler.getEmbeddings(_slug, [for (final int i in missing) keyOf(items[i])]);
        missing.removeWhere((int i) {
          final Float32List? v = stored[keyOf(items[i])];
          if (v == null || v.isEmpty) return false;
          out[i] = _remember('k:${keyOf(items[i])}', v);
          return true;
        });
      } catch (e, s) {
        Logger.Inst().log('reading embeddings failed: $e', className, 'embedItems', LogTypes.exception, s: s);
      }
    }
    if (missing.isEmpty) return out;
    final List<String> texts = [for (final int i in missing) textOf(items[i], ItemFeatures.worldOf(items[i]), handler: handler)];
    final List<int> readable = [for (int j = 0; j < missing.length; j++) if (texts[j].isNotEmpty) j];
    if (readable.isEmpty) return out;
    final List<Float32List?> vectors = await embedTexts([for (final int j in readable) texts[j]]);
    final Map<String, Float32List> fresh = {};
    for (int k = 0; k < readable.length; k++) {
      final Float32List? v = vectors[k];
      if (v == null) continue;
      final int i = missing[readable[k]];
      out[i] = _remember('k:${keyOf(items[i])}', v);
      fresh[keyOf(items[i])] = v;
    }
    await _store(fresh);
    return out;
  }

  /// An item's vector when it is already in memory (a scorer in a loop).
  Float32List? cached(BooruItem item) => _recall('k:${keyOf(item)}');

  // ── defaults ──

  static Future<void> _dioFetch(String url, File to, {void Function(int received, int total)? onProgress, CancelToken? cancelToken}) async {
    to.parent.createSync(recursive: true);
    await Dio().download(
      url,
      to.path,
      cancelToken: cancelToken,
      onReceiveProgress: onProgress,
      options: Options(
        followRedirects: true,
        maxRedirects: 10,
        receiveTimeout: const Duration(minutes: 30),
        headers: const {'User-Agent': 'LoliSnatcher (recommender encoder download)'},
      ),
    );
  }

  static EmbeddingRunner _onnxRunner(String modelPath, {required bool wantsTokenTypeIds}) =>
      OnnxEmbeddingRunner(modelPath, dim: EncoderHandler.maybe?._dim ?? 0, wantsTokenTypeIds: wantsTokenTypeIds);
}
