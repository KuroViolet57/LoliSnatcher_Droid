import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:image/image.dart' as img;

import 'package:lolisnatcher/src/handlers/recommender/onnx_tag_runner.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/perf_trace.dart';

/// An image tagger the user can download from Hugging Face (r74).
///
/// The presets are the WD v3 taggers (SmilingWolf): ONNX exports that read
/// booru tags straight from the pixels — 8,106 general tags, 2,751
/// characters and a rating, in the danbooru spelling. Any repo with the
/// same layout (`model.onnx` + `selected_tags.csv`) works. The picture is
/// prepared the way the author's reference code does: transparency onto
/// white, padded to a square with white, resized to the model's size,
/// float32 0-255, BGR, a batch of one. Boards read their reference image
/// through it; a strong reaction can read its thumbnail (a switch).
class TaggerPreset {
  const TaggerPreset({
    required this.id,
    required this.repo,
    required this.label,
    required this.description,
    required this.bytes,
    this.inputSize = ImageTaggerHandler.defaultInputSize,
  });

  final String id;
  final String repo;
  final String label;
  final String description;

  /// The model file's size.
  final int bytes;
  final int inputSize;

  static const TaggerPreset wdVit = TaggerPreset(
    id: 'wd-vit',
    repo: 'SmilingWolf/wd-vit-tagger-v3',
    label: 'WD ViT v3',
    description: "wd-vit-tagger-v3: 379 MB, 10,861 tags (general booru tags, characters, a rating). The smallest of the three and the author's reference.",
    bytes: 378536310,
  );

  static const TaggerPreset wdConvNext = TaggerPreset(
    id: 'wd-convnext',
    repo: 'SmilingWolf/wd-convnext-tagger-v3',
    label: 'WD ConvNeXt v3',
    description: 'wd-convnext-tagger-v3: 395 MB, the same tags. A convolutional net, often the fastest of the three on a phone.',
    bytes: 394990732,
  );

  static const TaggerPreset wdSwinV2 = TaggerPreset(
    id: 'wd-swinv2',
    repo: 'SmilingWolf/wd-swinv2-tagger-v3',
    label: 'WD SwinV2 v3',
    description: 'wd-swinv2-tagger-v3: 467 MB, the same tags. The most accurate of the three, and the slowest.',
    bytes: 467460978,
  );

  static const List<TaggerPreset> values = [wdVit, wdConvNext, wdSwinV2];

  static TaggerPreset? byId(String id) {
    for (final TaggerPreset p in values) {
      if (p.id == id) return p;
    }
    return null;
  }
}

enum TaggerState { none, downloading, ready, error }

@immutable
class TaggerStatus {
  const TaggerStatus({
    required this.state,
    this.progress = 0,
    this.message = '',
    this.repo = '',
    this.bytes = 0,
    this.tagCount = 0,
    this.inputSize = 0,
    this.downloadedAt,
  });

  static const TaggerStatus none = TaggerStatus(state: TaggerState.none);

  final TaggerState state;
  final double progress;
  final String message;
  final String repo;
  final int bytes;
  final int tagCount;
  final int inputSize;
  final DateTime? downloadedAt;
}

/// A tag read from the picture, with the model's confidence.
typedef PixelTag = ({String tag, double confidence, bool character});

/// What the model read in one picture.
class TaggerResult {
  const TaggerResult({
    required this.general,
    required this.characters,
    required this.rating,
    required this.ratingConfidence,
    this.decodeMs = 0,
    this.modelMs = 0,
    this.provider = '',
  });

  /// General tags above the threshold, strongest first, capped.
  final List<PixelTag> general;

  /// Characters above their (higher) threshold, strongest first.
  final List<PixelTag> characters;

  /// general / sensitive / questionable / explicit, by the highest score.
  final String rating;
  final double ratingConfidence;
  final int decodeMs;
  final int modelMs;
  final String provider;

  /// Characters first, then the general tags.
  List<PixelTag> get all => [...characters, ...general];

  int get count => general.length + characters.length;

  int get totalMs => decodeMs + modelMs;
}

/// One row of `selected_tags.csv`: the tag and its category (0 general,
/// 4 character, 9 rating; anything else is read as general).
class TagRow {
  const TagRow(this.name, this.category);

  final String name;
  final int category;
}

/// Runs the model over one picture: the tensor `[1, size, size, 3]` in,
/// one probability per row of the tag list out.
abstract class TagRunner {
  String get provider;
  Future<Float32List> run(Float32List nhwc, int size);
  Future<void> close();
}

typedef TaggerFetcher = Future<void> Function(String url, File to, {void Function(int received, int total)? onProgress, CancelToken? cancelToken});
typedef TagRunnerFactory = TagRunner Function(String modelPath, int threads);

/// r79: who is waiting for a picture's tags. The session's thread count is
/// fixed when it opens (the ONNX plugin has no per-run setting), so the
/// purpose of the call that opens it decides.
enum TaggerUse {
  /// Try it, a board's reference picture, the board editor: someone waits.
  waiting,

  /// A reaction's tags, in the background (ModelWork).
  background,
}

Float32List _prepareEntry((Uint8List, int) args) => ImageTaggerHandler.prepareTensor(args.$1, args.$2);

class ImageTaggerHandler {
  static ImageTaggerHandler get instance => GetIt.instance<ImageTaggerHandler>();

  static ImageTaggerHandler register() {
    if (!GetIt.instance.isRegistered<ImageTaggerHandler>()) {
      GetIt.instance.registerSingleton(ImageTaggerHandler());
    }
    return instance;
  }

  static void unregister() {
    if (GetIt.instance.isRegistered<ImageTaggerHandler>()) {
      GetIt.instance.unregister<ImageTaggerHandler>();
    }
  }

  static ImageTaggerHandler? get maybe => GetIt.instance.isRegistered<ImageTaggerHandler>() ? instance : null;

  static const String className = 'ImageTaggerHandler';

  static const String modelFileName = 'model.onnx';
  static const String tagsFileName = 'selected_tags.csv';
  static const String configFileName = 'config.json';

  /// The author's thresholds: a general tag counts from 0.35, a character
  /// from 0.85; two dozen general tags at most.
  static const double defaultGeneralThreshold = 0.35;
  static const double defaultCharacterThreshold = 0.85;
  static const int defaultMaxGeneral = 24;
  static const int defaultInputSize = 448;
  static const Duration defaultIdleClose = Duration(seconds: 120);

  /// r79: measured on the S24 Ultra, the model part of a picture took
  /// 1.1-1.9 s at 4 threads (19 Sep) and 1.8-4.0 s at 2 (20 Sep). The looks
  /// model and the text encoder showed no such gain, and stay at 1.
  static const int waitingThreads = 4;
  static const int backgroundThreads = 2;

  /// The session (several hundred MB of RAM) is closed this long after the
  /// last picture; the next one opens it again.
  Duration idleClose = defaultIdleClose;

  final ValueNotifier<TaggerStatus> status = ValueNotifier(TaggerStatus.none);

  /// Test seams: how files come down, how the model runs.
  TaggerFetcher fetcher = _dioFetch;
  TagRunnerFactory runnerFactory = _onnxRunner;

  SettingsHandler get _settings => SettingsHandler.instance;

  List<TagRow>? _rows;
  TagRunner? _runner;
  Future<void>? _loading;
  Timer? _idle;

  /// r79: runs using the session right now. The idle close waits for them:
  /// r78's timer could close the session under a run, the run failed, and a
  /// failed run switches the tagger off until a restart.
  int _inFlight = 0;
  String _slug = '';
  int _inputSize = defaultInputSize;
  CancelToken? _downloading;

  static String fileUrl(String repo, String file) => 'https://huggingface.co/$repo/resolve/main/$file';

  /// The repo behind a setting value: a preset id, or a repo id as typed.
  static String repoOf(String setting) => TaggerPreset.byId(setting)?.repo ?? setting.trim();

  static String slugOf(String repo) => repo.trim().toLowerCase().replaceAll('/', '__').replaceAll(RegExp(r'[^a-z0-9._\-]'), '-');

  String dirFor(String setting) => '${_settings.path}tagger${Platform.pathSeparator}${slugOf(repoOf(setting))}${Platform.pathSeparator}';

  bool get isReady => status.value.state == TaggerState.ready;

  /// The tagger is downloaded and the switch is on.
  bool get enabled => _settings.aiImageTagger && isReady;

  /// Names the model (a board's cached tags belong to one model).
  String get modelId => _slug;

  int get inputSize => _inputSize;

  // ── files ──

  /// Reads the manifest of the configured model; ready when its files are there.
  Future<void> refresh() async {
    final String setting = _settings.imageTaggerModel;
    if (setting.trim().isEmpty) {
      _apply(TaggerStatus.none, slug: '');
      return;
    }
    final String dir = dirFor(setting);
    final File manifest = File('${dir}manifest.json');
    final File model = File('$dir$modelFileName');
    final File tags = File('$dir$tagsFileName');
    if (!manifest.existsSync() || !model.existsSync() || !tags.existsSync()) {
      _apply(const TaggerStatus(state: TaggerState.none, message: 'The model files are missing; download again.'), slug: '');
      return;
    }
    try {
      final Map<String, dynamic> m = jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
      _inputSize = (m['inputSize'] as num?)?.toInt() ?? defaultInputSize;
      final String repo = m['repo'] as String? ?? repoOf(setting);
      _apply(
        TaggerStatus(
          state: TaggerState.ready,
          repo: repo,
          bytes: (m['bytes'] as num?)?.toInt() ?? model.lengthSync(),
          tagCount: (m['tagCount'] as num?)?.toInt() ?? 0,
          inputSize: _inputSize,
          downloadedAt: DateTime.tryParse(m['downloadedAt'] as String? ?? ''),
        ),
        slug: slugOf(repo),
      );
    } catch (e, s) {
      Logger.Inst().log('tagger manifest unreadable: $e', className, 'refresh', LogTypes.exception, s: s);
      _apply(TaggerStatus(state: TaggerState.error, message: 'The model manifest is unreadable: $e'), slug: '');
    }
  }

  void _apply(TaggerStatus s, {required String slug}) {
    if (slug != _slug) {
      _rows = null;
      _dropRunner();
    }
    _slug = slug;
    status.value = s;
  }

  /// Downloads [setting] (a preset id or a repo id) and makes it the model.
  Future<bool> download(String setting) async {
    if (_downloading != null) return false;
    final String repo = repoOf(setting);
    if (repo.isEmpty || !repo.contains('/')) {
      status.value = const TaggerStatus(state: TaggerState.error, message: 'A Hugging Face repo id looks like owner/model.');
      return false;
    }
    final TaggerPreset? preset = TaggerPreset.byId(setting);
    final String dir = dirFor(setting);
    final String tmp = '${_settings.path}tagger${Platform.pathSeparator}.download-${slugOf(repo)}${Platform.pathSeparator}';
    final CancelToken cancel = _downloading = CancelToken();
    status.value = TaggerStatus(state: TaggerState.downloading, repo: repo, bytes: preset?.bytes ?? 0);
    try {
      final Directory tmpDir = Directory(tmp);
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
      tmpDir.createSync(recursive: true);
      final File model = File('$tmp$modelFileName');
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
          status.value = TaggerStatus(state: TaggerState.downloading, repo: repo, bytes: expected, progress: progress);
        },
      );
      final File tags = File('$tmp$tagsFileName');
      await fetcher(fileUrl(repo, tagsFileName), tags, cancelToken: cancel);
      final List<TagRow> rows = parseTagsCsv(tags.readAsStringSync());
      if (rows.length < 5) {
        throw const FormatException('selected_tags.csv is not a tag list (no name column, or too few rows).');
      }
      // config.json names the input size; a repo without one keeps the preset's.
      Map<String, dynamic> config = const {};
      final File configFile = File('$tmp$configFileName');
      try {
        await fetcher(fileUrl(repo, configFileName), configFile, cancelToken: cancel);
        config = _json(configFile);
      } catch (e) {
        if (cancel.isCancelled) rethrow;
        Logger.Inst().log('no config.json in $repo ($e); the preset size stands', className, 'download', LogTypes.booruHandlerInfo);
        try {
          if (configFile.existsSync()) configFile.deleteSync();
        } catch (_) {}
      }
      final int inputSize = _inputSizeOf(config) ?? preset?.inputSize ?? defaultInputSize;
      final int bytes = model.lengthSync();
      File('${tmp}manifest.json').writeAsStringSync(
        jsonEncode({
          'repo': repo,
          'setting': setting,
          'bytes': bytes,
          'inputSize': inputSize,
          'tagCount': rows.length,
          'downloadedAt': DateTime.now().toIso8601String(),
        }),
      );
      // The running session and the tag list belong to the files about to
      // be replaced — even when the repo is the same.
      await close();
      _apply(status.value, slug: '');
      final Directory target = Directory(dir);
      if (target.existsSync()) target.deleteSync(recursive: true);
      tmpDir.renameSync(target.path.substring(0, target.path.length - 1));
      _settings.imageTaggerModel = setting;
      unawaited(_saveSetting());
      await refresh();
      return isReady;
    } catch (e, s) {
      final String why = e is DioException
          ? (e.message ?? e.error?.toString() ?? e.type.name)
          : e is FormatException
          ? e.message
          : '$e';
      Logger.Inst().log('tagger download of $repo failed: $e', className, 'download', LogTypes.exception, s: s);
      try {
        final Directory tmpDir = Directory(tmp);
        if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
      } catch (_) {}
      status.value = TaggerStatus(state: TaggerState.error, repo: repo, message: cancel.isCancelled ? 'Download cancelled.' : why);
      return false;
    } finally {
      _downloading = null;
    }
  }

  void cancelDownload() => _downloading?.cancel('cancelled by the user');

  Future<void> delete() async {
    final String setting = _settings.imageTaggerModel;
    await close();
    if (setting.trim().isNotEmpty) {
      try {
        final Directory dir = Directory(dirFor(setting));
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      } catch (e, s) {
        Logger.Inst().log('deleting the tagger failed: $e', className, 'delete', LogTypes.exception, s: s);
      }
    }
    _settings.imageTaggerModel = '';
    unawaited(_saveSetting());
    _apply(TaggerStatus.none, slug: '');
  }

  /// The model choice into settings.json; a write that fails (a test's
  /// temp folder already gone) is not the download's failure.
  Future<void> _saveSetting() async {
    try {
      await _settings.saveSettings(restate: false);
    } catch (e) {
      Logger.Inst().log('tagger setting not saved: $e', className, '_saveSetting', LogTypes.booruHandlerInfo);
    }
  }

  /// Closes the session (the tag list stays); not a failure.
  Future<void> close() async {
    _idle?.cancel();
    _idle = null;
    final TagRunner? r = _runner;
    _runner = null;
    _loading = null;
    if (r != null) {
      try {
        await r.close();
      } catch (_) {}
    }
  }

  void _dropRunner() {
    _idle?.cancel();
    _idle = null;
    final TagRunner? r = _runner;
    _runner = null;
    _loading = null;
    if (r != null) r.close().catchError((_) {});
  }

  static int? _inputSizeOf(Map<String, dynamic> config) {
    final dynamic args = config['model_args'];
    if (args is Map && args['img_size'] is num) return (args['img_size'] as num).toInt();
    final dynamic cfg = config['pretrained_cfg'];
    if (cfg is Map && cfg['input_size'] is List) {
      final List<dynamic> size = cfg['input_size'] as List<dynamic>;
      if (size.length >= 3 && size[1] is num) return (size[1] as num).toInt();
    }
    return null;
  }

  static Map<String, dynamic> _json(File f) {
    try {
      final dynamic v = jsonDecode(f.readAsStringSync());
      return v is Map<String, dynamic> ? v : const {};
    } catch (_) {
      return const {};
    }
  }

  // ── pictures ──

  /// The tags of one picture (encoded bytes: jpg, png, webp, gif — the
  /// first frame). Decoding runs off the main isolate; the model runs in
  /// the runtime's own thread. A picture that cannot be decoded is a
  /// [FormatException]; a model that cannot run is shown on the settings
  /// page and not tried again until a [refresh].
  ///
  /// r79: [use] decides the session's threads when this call opens it; a
  /// session already open is used as it is - never a second copy.
  Future<TaggerResult> tag(Uint8List bytes, {TaggerUse use = TaggerUse.waiting}) async {
    if (!isReady) throw StateError('No image tagger downloaded (Settings → Recommendations → Image tagger).');
    // Counted from before the decode: the session is needed right after it,
    // and closing it meanwhile would only mean opening it again.
    _inFlight++;
    final Stopwatch sw = Stopwatch()..start();
    final Float32List tensor;
    try {
      tensor = await compute(_prepareEntry, (bytes, _inputSize));
    } catch (_) {
      _inFlight--;
      rethrow;
    }
    final int decodeMs = sw.elapsedMilliseconds;
    sw.reset();
    Float32List probs;
    try {
      await _ensureLoaded(use);
      probs = await _runner!.run(tensor, _inputSize);
    } catch (e) {
      _fail(e);
      rethrow;
    } finally {
      _inFlight--;
    }
    final int modelMs = sw.elapsedMilliseconds;
    final String provider = _runner?.provider ?? '';
    _touch();
    final TaggerResult r = interpret(probs, _rows ?? const [], decodeMs: decodeMs, modelMs: modelMs, provider: provider);
    PerfTrace.instance.event('model.tagger', 'decode $decodeMs ms, model $modelMs ms');
    Logger.Inst().log(
      'tagger: ${r.general.length} general, ${r.characters.length} characters, rating ${r.rating} ${r.ratingConfidence.toStringAsFixed(2)}; decode $decodeMs ms, model $modelMs ms ($provider, ${use.name})',
      className,
      'tag',
      LogTypes.booruHandlerInfo,
    );
    return r;
  }

  /// The model's answer read by category and threshold.
  static TaggerResult interpret(
    Float32List probs,
    List<TagRow> rows, {
    double generalThreshold = defaultGeneralThreshold,
    double characterThreshold = defaultCharacterThreshold,
    int maxGeneral = defaultMaxGeneral,
    int decodeMs = 0,
    int modelMs = 0,
    String provider = '',
  }) {
    final int n = math.min(probs.length, rows.length);
    String rating = '';
    double ratingP = -1;
    final List<PixelTag> general = [];
    final List<PixelTag> characters = [];
    for (int i = 0; i < n; i++) {
      final TagRow row = rows[i];
      final double p = probs[i];
      if (row.category == 9) {
        if (p > ratingP) {
          rating = row.name;
          ratingP = p;
        }
      } else if (row.category == 4) {
        if (p > characterThreshold) characters.add((tag: row.name, confidence: p, character: true));
      } else if (p > generalThreshold) {
        general.add((tag: row.name, confidence: p, character: false));
      }
    }
    general.sort((a, b) => b.confidence.compareTo(a.confidence));
    characters.sort((a, b) => b.confidence.compareTo(a.confidence));
    return TaggerResult(
      general: general.take(maxGeneral).toList(),
      characters: characters,
      rating: rating,
      ratingConfidence: ratingP < 0 ? 0 : ratingP,
      decodeMs: decodeMs,
      modelMs: modelMs,
      provider: provider,
    );
  }

  /// `selected_tags.csv`: columns by header name (`name`, `category`), in
  /// any order; quoted names; blank and short rows skipped; the names kept
  /// as they are (underscores, kaomoji).
  static List<TagRow> parseTagsCsv(String text) {
    final List<String> lines = const LineSplitter().convert(text);
    if (lines.isEmpty) return const [];
    final List<String> header = _splitCsv(lines.first).map((h) => h.trim().toLowerCase()).toList();
    final int nameAt = header.indexOf('name');
    final int categoryAt = header.indexOf('category');
    if (nameAt < 0) return const [];
    final List<TagRow> out = [];
    for (final String line in lines.skip(1)) {
      if (line.trim().isEmpty) continue;
      final List<String> cells = _splitCsv(line);
      if (cells.length < header.length) continue;
      final String name = cells[nameAt].trim();
      if (name.isEmpty) continue;
      final int category = categoryAt >= 0 ? (int.tryParse(cells[categoryAt].trim()) ?? 0) : 0;
      out.add(TagRow(name, category));
    }
    return out;
  }

  static List<String> _splitCsv(String line) {
    final List<String> out = [];
    final StringBuffer cell = StringBuffer();
    bool quoted = false;
    for (int i = 0; i < line.length; i++) {
      final String c = line[i];
      if (quoted) {
        if (c == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          cell.write(c);
        }
      } else if (c == '"') {
        quoted = true;
      } else if (c == ',') {
        out.add(cell.toString());
        cell.clear();
      } else {
        cell.write(c);
      }
    }
    out.add(cell.toString());
    return out;
  }

  /// The picture as the model wants it (the author's reference code):
  /// transparency onto white, the picture in a white square (padded from
  /// the top-left half, as PIL does with `(max - w) // 2`), resized to
  /// [size] with a cubic filter, float32 0-255 in BGR order, NHWC.
  static Float32List prepareTensor(Uint8List bytes, int size) {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (e) {
      // The decoders throw on bytes that are not a picture at all.
      throw FormatException('could not decode the image ($e)');
    }
    if (decoded == null) throw const FormatException('could not decode the image');
    final img.Image src = decoded.format == img.Format.uint8 ? decoded : decoded.convert(format: img.Format.uint8);
    final int w = src.width;
    final int h = src.height;
    final int maxDim = math.max(w, h);
    final img.Image square = img.Image(width: maxDim, height: maxDim, numChannels: 3);
    img.fill(square, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(square, src, dstX: (maxDim - w) ~/ 2, dstY: (maxDim - h) ~/ 2);
    final img.Image resized = maxDim == size ? square : img.copyResize(square, width: size, height: size, interpolation: img.Interpolation.cubic);
    final Float32List out = Float32List(size * size * 3);
    int i = 0;
    for (final img.Pixel p in resized) {
      out[i++] = p.b.toDouble();
      out[i++] = p.g.toDouble();
      out[i++] = p.r.toDouble();
    }
    return out;
  }

  Future<void> _ensureLoaded(TaggerUse use) => _loading ??= _load(use);

  Future<void> _load(TaggerUse use) async {
    try {
      final String dir = dirFor(_settings.imageTaggerModel);
      _rows ??= parseTagsCsv(await File('$dir$tagsFileName').readAsString());
      if (_rows!.isEmpty) throw const FormatException('the tag list is empty');
      _runner = runnerFactory('$dir$modelFileName', use == TaggerUse.waiting ? waitingThreads : backgroundThreads);
    } catch (e) {
      _loading = null;
      rethrow;
    }
  }

  /// The model could not be run: said on the settings page, and not tried
  /// again until a [refresh] (a restart, a new download).
  void _fail(Object e) {
    Logger.Inst().log('tagger failed: $e', className, '_fail', LogTypes.exception);
    _dropRunner();
    final TaggerStatus s = status.value;
    status.value = TaggerStatus(
      state: TaggerState.error,
      repo: s.repo,
      bytes: s.bytes,
      tagCount: s.tagCount,
      inputSize: s.inputSize,
      downloadedAt: s.downloadedAt,
      message: 'The model could not be run: $e',
    );
  }

  void _touch() {
    _idle?.cancel();
    _idle = Timer(idleClose, () {
      _idle = null;
      // r79: a run still using the session re-arms the timer when it ends.
      if (_runner == null || _inFlight > 0) return;
      Logger.Inst().log('tagger: session closed (idle)', className, '_touch', LogTypes.booruHandlerInfo);
      unawaited(close());
    });
  }

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
        headers: const {'User-Agent': 'LoliSnatcher (image tagger download)'},
      ),
    );
  }

  static TagRunner _onnxRunner(String modelPath, int threads) => OnnxTagRunner(modelPath, threads: threads);
}
