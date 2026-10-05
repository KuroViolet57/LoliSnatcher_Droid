import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:image/image.dart' as img;

import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/features/recommender/logic/model_tasks.dart';
import 'package:lolisnatcher/features/recommender/logic/ml/clip_tokenizer.dart';
import 'package:lolisnatcher/features/recommender/logic/ml/encoder_handler.dart';
import 'package:lolisnatcher/features/recommender/logic/ml/hf_repo.dart';
import 'package:lolisnatcher/features/recommender/logic/onnx/onnx_look_runner.dart';
import 'package:lolisnatcher/features/recommender/logic/ml/model_pictures.dart';
import 'package:lolisnatcher/features/recommender/logic/pixel_tags.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/logging/logger.dart';
import 'package:lolisnatcher/core/logging/perf_trace.dart';
import 'package:lolisnatcher/core/storage/database_handler.dart';

part 'look_model_handler/look_types.dart';


class LookModelHandler {
  static LookModelHandler get instance => GetIt.instance<LookModelHandler>();

  static LookModelHandler register() {
    if (!GetIt.instance.isRegistered<LookModelHandler>()) {
      GetIt.instance.registerSingleton(LookModelHandler());
    }
    return instance;
  }

  static void unregister() {
    if (GetIt.instance.isRegistered<LookModelHandler>()) {
      GetIt.instance.unregister<LookModelHandler>();
    }
  }

  static LookModelHandler? get maybe => GetIt.instance.isRegistered<LookModelHandler>() ? instance : null;

  static const String className = 'LookModelHandler';

  /// The files as kept locally, and where the presets fetch them from.
  static const String imageFileName = 'vision_model.onnx';
  static const String textFileName = 'text_model.onnx';
  static const String tokenizerFileName = 'tokenizer.json';
  static const String preprocessorFileName = 'preprocessor_config.json';
  static const String defaultImageRemote = 'onnx/vision_model_quantized.onnx';
  static const String defaultTextRemote = 'onnx/text_model_quantized.onnx';

  static const int defaultInputSize = 256;
  static const Duration defaultIdleClose = Duration(seconds: 120);
  static const int _memoryCap = 4000;

  /// The sessions are closed this long after the last vector.
  Duration idleClose = defaultIdleClose;

  final ValueNotifier<LookStatus> status = ValueNotifier(LookStatus.none);

  /// Test seams: how files come down, how the model runs, how a thumbnail is read.
  /// Preset downloads do not call [listing].
  LookFetcher fetcher = _dioFetch;
  LookRunnerFactory runnerFactory = _onnxRunner;
  ThumbnailFetcher thumbnailFetcher = _defaultThumbnail;
  Future<HfListing> Function(String repoId) listing = HfRepo.fetch;

  SettingsHandler get _settings => SettingsHandler.instance;

  LookRunner? _runner;
  ClipTokenizer? _tokenizer;
  Future<void>? _loading;
  Timer? _idle;
  String _slug = '';
  int _inputSize = defaultInputSize;
  int _dim = 0;
  List<double>? _mean;
  List<double>? _std;
  CancelToken? _downloading;

  /// Vectors by item key (`k:`) and by text (`t:`), most recent last.
  final LinkedHashMap<String, Float32List> _memory = LinkedHashMap();

  static String fileUrl(String repo, String file) => 'https://huggingface.co/$repo/resolve/main/$file';

  // ── r87: the NPU's picture half ──

  /// The full-precision picture half, kept next to the int8 one.
  static const String npuImageFileName = 'vision_model_npu.onnx';
  static const String npuImageRemote = 'onnx/vision_model.onnx';

  String get npuImagePath => '${dirFor(_settings.lookModel)}$npuImageFileName';

  bool get hasNpuFile {
    try {
      return _settings.lookModel.isNotEmpty && File(npuImagePath).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Its size for the chosen model, when known (the presets).
  int? get npuImageBytes => LookPreset.byId(_settings.lookModel)?.npuImageBytes;

  /// Fetches the full-precision picture half; true when it is there.
  /// A preset still asks for [npuImageRemote] on `main`. A custom repo uses
  /// the `npuRemote` and `revision` stored in its manifest. A folder import
  /// never calls Hugging Face.
  Future<bool> downloadNpuFile({void Function(double progress)? onProgress}) async {
    final String setting = _settings.lookModel;
    if (setting.isEmpty) return false;
    final File target = File(npuImagePath);
    if (target.existsSync() && target.lengthSync() > 0) return true;
    final File part = File('${target.path}.part');
    String remote = npuImageRemote;
    String revision = 'main';
    String source = '';
    String repo = repoOf(setting);
    try {
      final File manifest = File('${dirFor(setting)}manifest.json');
      if (manifest.existsSync()) {
        final Map<String, dynamic> stored = jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
        final String? named = stored['npuRemote'] as String?;
        if (named != null && named.isNotEmpty) remote = named;
        final String? namedRevision = stored['revision'] as String?;
        if (namedRevision != null && namedRevision.isNotEmpty) revision = namedRevision;
        source = stored['source'] as String? ?? '';
        if (LookPreset.byId(setting) == null) {
          final String listed = stored['repo'] as String? ?? repo;
          if (!listed.startsWith('folder:') && listed.contains('/')) repo = listed;
        }
      }
    } catch (e) {
      Logger.Inst().log('look: NPU manifest unreadable, the preset file name stands ($e)', className, 'downloadNpuFile', LogTypes.booruHandlerInfo);
    }
    if (source == 'folder' || setting.startsWith('files:')) {
      Logger.Inst().log('look: the imported folder has no full-precision picture half', className, 'downloadNpuFile', LogTypes.booruHandlerInfo);
      return false;
    }
    final String url = revision == 'main' && remote == npuImageRemote ? fileUrl(repo, remote) : HfRepo.resolveUrl(repo, revision, remote);
    try {
      await fetcher(
        url,
        part,
        onProgress: (int received, int total) {
          if (total > 0) onProgress?.call(received / total);
        },
      );
      if (target.existsSync()) target.deleteSync();
      part.renameSync(target.path);
      Logger.Inst().log('look: the full-precision picture half for the NPU is here (${target.lengthSync()} bytes)', className, 'downloadNpuFile', LogTypes.booruHandlerInfo);
      _dropRunner();
      return true;
    } catch (e) {
      Logger.Inst().log('look: the picture half for the NPU could not be fetched: $e', className, 'downloadNpuFile', LogTypes.exception);
      try {
        if (part.existsSync()) part.deleteSync();
      } catch (_) {}
      return false;
    }
  }

  static String repoOf(String setting) => LookPreset.byId(setting)?.repo ?? setting.trim();

  static String slugOf(String repo) => repo.trim().toLowerCase().replaceAll('/', '__').replaceAll(RegExp(r'[^a-z0-9._\-]'), '-');

  String dirFor(String setting) => '${_settings.path}look${Platform.pathSeparator}${slugOf(repoOf(setting))}${Platform.pathSeparator}';

  bool get isReady => status.value.state == LookState.ready;

  /// Downloaded and switched on.
  bool get enabled => _settings.aiLook && !_settings.aiModelsOff && isReady;

  /// Names the model in feature names and database rows.
  String get modelId => _slug;

  /// The database model key for item vectors.
  String get storeKey => 'look:$_slug';

  int get dim => _dim;
  int get inputSize => _inputSize;
  List<double>? get mean => _mean;
  List<double>? get std => _std;

  static String keyOf(BooruItem item) => EncoderHandler.keyOf(item);

  // ── files ──

  Future<void> refresh() async {
    final String setting = _settings.lookModel;
    if (setting.trim().isEmpty) {
      _apply(LookStatus.none, slug: '');
      return;
    }
    final String dir = dirFor(setting);
    final File manifest = File('${dir}manifest.json');
    final bool complete = manifest.existsSync() && [imageFileName, textFileName, tokenizerFileName].every((f) => File('$dir$f').existsSync());
    if (!complete) {
      _apply(const LookStatus(state: LookState.none, message: 'The model files are missing; download again.'), slug: '');
      return;
    }
    try {
      final Map<String, dynamic> m = jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
      _inputSize = (m['inputSize'] as num?)?.toInt() ?? defaultInputSize;
      _dim = (m['dim'] as num?)?.toInt() ?? 0;
      _mean = _doubles(m['mean']);
      _std = _doubles(m['std']);
      final String repo = m['repo'] as String? ?? repoOf(setting);
      _apply(
        LookStatus(
          state: LookState.ready,
          repo: repo,
          bytes: (m['bytes'] as num?)?.toInt() ?? 0,
          dim: _dim,
          inputSize: _inputSize,
          downloadedAt: DateTime.tryParse(m['downloadedAt'] as String? ?? ''),
        ),
        slug: slugOf(repo),
      );
    } catch (e, s) {
      Logger.Inst().log('looks manifest unreadable: $e', className, 'refresh', LogTypes.exception, s: s);
      _apply(LookStatus(state: LookState.error, message: 'The model manifest is unreadable: $e'), slug: '');
    }
  }

  static List<double>? _doubles(dynamic v) => v is List && v.isNotEmpty ? [for (final dynamic x in v) (x as num).toDouble()] : null;

  void _apply(LookStatus s, {required String slug}) {
    if (slug != _slug) {
      _memory.clear();
      _tokenizer = null;
      _dropRunner();
    }
    _slug = slug;
    status.value = s;
  }

  /// Downloads [setting] (a preset id or a repo id) and makes it the model.
  Future<bool> download(String setting) async {
    if (_downloading != null) return false;
    if (LookPreset.byId(setting) == null) return _downloadListed(setting);
    final String repo = repoOf(setting);
    if (repo.isEmpty || !repo.contains('/')) {
      status.value = const LookStatus(state: LookState.error, message: 'A Hugging Face repo id looks like owner/model.');
      return false;
    }
    final LookPreset? preset = LookPreset.byId(setting);
    final String dir = dirFor(setting);
    final String tmp = '${_settings.path}look${Platform.pathSeparator}.download-${slugOf(repo)}${Platform.pathSeparator}';
    final CancelToken cancel = _downloading = CancelToken();
    final int expectedTotal = preset?.bytes ?? 0;
    status.value = LookStatus(state: LookState.downloading, repo: repo, bytes: expectedTotal);
    try {
      final Directory tmpDir = Directory(tmp);
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
      tmpDir.createSync(recursive: true);
      // The two halves, progress across both.
      int done = 0;
      double shown = -1;
      for (final (String remote, String local, int expected) in [
        (preset?.imageFile ?? defaultImageRemote, imageFileName, preset?.imageBytes ?? 0),
        (preset?.textFile ?? defaultTextRemote, textFileName, preset?.textBytes ?? 0),
      ]) {
        final File to = File('$tmp$local');
        await fetcher(
          fileUrl(repo, remote),
          to,
          cancelToken: cancel,
          onProgress: (int received, int total) {
            final int all = expectedTotal > 0 ? expectedTotal : (total > 0 ? total : expected);
            final double progress = all > 0 ? ((done + received) / all).clamp(0, 1).toDouble() : 0;
            if (progress < 1 && progress - shown < 0.005) return;
            shown = progress;
            status.value = LookStatus(state: LookState.downloading, repo: repo, bytes: all, progress: progress);
          },
        );
        done += to.lengthSync();
      }
      final File tokenizerFile = File('$tmp$tokenizerFileName');
      await fetcher(fileUrl(repo, tokenizerFileName), tokenizerFile, cancelToken: cancel);
      try {
        ClipTokenizer.fromJsonText(tokenizerFile.readAsStringSync());
      } catch (e) {
        throw FormatException('tokenizer.json is not a CLIP tokenizer ($e).');
      }
      Map<String, dynamic> pre = const {};
      final File preFile = File('$tmp$preprocessorFileName');
      try {
        await fetcher(fileUrl(repo, preprocessorFileName), preFile, cancelToken: cancel);
        pre = _json(preFile);
      } catch (e) {
        if (cancel.isCancelled) rethrow;
        Logger.Inst().log('no preprocessor_config.json in $repo ($e); defaults stand', className, 'download', LogTypes.booruHandlerInfo);
      }
      final int inputSize = _inputSizeOf(pre) ?? defaultInputSize;
      final bool normalize = pre['do_normalize'] == true;
      final List<double>? mean = normalize ? _doubles(pre['image_mean']) : null;
      final List<double>? std = normalize ? _doubles(pre['image_std']) : null;
      final int bytes = File('$tmp$imageFileName').lengthSync() + File('$tmp$textFileName').lengthSync();
      File('${tmp}manifest.json').writeAsStringSync(
        jsonEncode({
          'repo': repo,
          'setting': setting,
          'bytes': bytes,
          'inputSize': inputSize,
          'mean': mean,
          'std': std,
          'dim': 0,
          'downloadedAt': DateTime.now().toIso8601String(),
        }),
      );
      await close();
      _apply(status.value, slug: '');
      final Directory target = Directory(dir);
      if (target.existsSync()) target.deleteSync(recursive: true);
      tmpDir.renameSync(target.path.substring(0, target.path.length - 1));
      _settings.lookModel = setting;
      unawaited(_saveSetting());
      await refresh();
      return isReady;
    } catch (e, s) {
      final String why = e is DioException
          ? (e.message ?? e.error?.toString() ?? e.type.name)
          : e is FormatException
          ? e.message
          : '$e';
      Logger.Inst().log('looks download of $repo failed: $e', className, 'download', LogTypes.exception, s: s);
      try {
        final Directory tmpDir = Directory(tmp);
        if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
      } catch (_) {}
      status.value = LookStatus(state: LookState.error, repo: repo, message: cancel.isCancelled ? 'Download cancelled.' : why);
      return false;
    } finally {
      _downloading = null;
    }
  }

  /// A repo id or a Hugging Face link. The file list decides which files to
  /// fetch. Presets do not come through here.
  Future<bool> _downloadListed(String setting) async {
    final CancelToken cancel = _downloading = CancelToken();
    try {
      final HfParseResult parsed = HfRepo.parse(setting);
      if (parsed.repo == null) {
        status.value = LookStatus(state: LookState.error, message: parsed.error ?? HfRepo.howTo);
        return false;
      }
      final String asked = parsed.repo!.id;
      status.value = LookStatus(state: LookState.downloading, repo: asked);
      final HfListing listed;
      try {
        listed = await listing(asked);
      } catch (e) {
        status.value = LookStatus(state: LookState.error, repo: asked, message: 'Could not read the file list ($e).');
        return false;
      }
      if (cancel.isCancelled) {
        status.value = const LookStatus(state: LookState.error, message: 'Download cancelled.');
        return false;
      }
      if (!listed.ok) {
        status.value = LookStatus(state: LookState.error, repo: asked, message: listed.error!);
        return false;
      }
      final HfPlan plan = HfRepo.choose(HfKind.look, listed.files);
      if (plan.error != null) {
        Logger.Inst().log('look: $asked listed ${listed.files.length} files, none usable: ${plan.error}', className, 'download', LogTypes.booruHandlerInfo);
        status.value = LookStatus(state: LookState.error, repo: listed.id.isEmpty ? asked : listed.id, message: plan.error!);
        return false;
      }
      final String repo = listed.id.isEmpty ? asked : listed.id;
      final String? fromLink = parsed.repo!.revision;
      final String revision = fromLink == null || fromLink == 'main' ? listed.revision : fromLink;
      Logger.Inst().log(
        'look: $repo @ $revision -> ${plan.files.map((HfPlannedFile f) => '${f.remote} as ${f.local}').join(', ')}'
        '${plan.npuRemote == null ? '' : ' (NPU later: ${plan.npuRemote})'}',
        className,
        'download',
        LogTypes.booruHandlerInfo,
      );
      return await _installLook(
        setting: repo,
        repoLabel: repo,
        plan: plan,
        source: 'huggingface',
        revision: revision,
        cancel: cancel,
        fetchOne: (HfPlannedFile file, File dest, void Function(int, int) onProgress) {
          return fetcher(HfRepo.resolveUrl(repo, revision, file.remote), dest, cancelToken: cancel, onProgress: onProgress);
        },
      );
    } finally {
      _downloading = null;
    }
  }

  /// Copies a folder of files the user already has. A full-precision picture
  /// half sitting next to the quantized one is kept for the NPU button.
  Future<bool> importLocal({required String label, required Map<String, String> files, required Future<void> Function(String relative, File dest) copy}) async {
    if (_downloading != null) return false;
    final CancelToken cancel = _downloading = CancelToken();
    try {
      final HfPlan chosen = HfRepo.choose(HfKind.look, files.keys.toList());
      final String name = label.trim().isEmpty ? HfRepo.labelFor(files.keys) : label.trim();
      if (chosen.error != null) {
        Logger.Inst().log('look: folder $name is not a looks model (${files.length} files): ${chosen.error}', className, 'importLocal', LogTypes.booruHandlerInfo);
        status.value = LookStatus(state: LookState.error, message: chosen.error!);
        return false;
      }
      final HfPlan plan = HfPlan(
        npuRemote: chosen.npuRemote,
        files: [
          ...chosen.files,
          if (chosen.npuRemote != null) HfPlannedFile(remote: chosen.npuRemote!, local: npuImageFileName, required: false),
        ],
      );
      Logger.Inst().log('look: importing folder $name (${plan.files.map((HfPlannedFile f) => f.remote).join(', ')})', className, 'importLocal', LogTypes.booruHandlerInfo);
      return await _installLook(
        setting: HfRepo.localSetting(name),
        repoLabel: 'folder:$name',
        plan: plan,
        source: 'folder',
        cancel: cancel,
        fetchOne: (HfPlannedFile file, File dest, void Function(int, int) onProgress) async {
          await copy(file.remote, dest);
          onProgress(dest.existsSync() ? dest.lengthSync() : 0, 0);
        },
      );
    } finally {
      _downloading = null;
    }
  }

  Future<bool> _installLook({
    required String setting,
    required String repoLabel,
    required HfPlan plan,
    required String source,
    required CancelToken cancel,
    required Future<void> Function(HfPlannedFile file, File dest, void Function(int received, int total) onProgress) fetchOne,
    String? revision,
  }) async {
    final String dir = dirFor(setting);
    final String tmp = '${_settings.path}look${Platform.pathSeparator}.download-${slugOf(repoLabel)}${Platform.pathSeparator}';
    status.value = LookStatus(state: LookState.downloading, repo: repoLabel);
    try {
      final Directory tmpDir = Directory(tmp);
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
      tmpDir.createSync(recursive: true);
      int done = 0;
      final int totalFiles = plan.files.length;
      for (final HfPlannedFile file in plan.files) {
        if (cancel.isCancelled) throw DioException(requestOptions: RequestOptions(), type: DioExceptionType.cancel);
        final File dest = File('$tmp${file.local}');
        try {
          await fetchOne(file, dest, (int received, int total) {
            final double progress = totalFiles == 0 ? 0 : ((done + (total > 0 ? received / total : 0)) / totalFiles).clamp(0, 1).toDouble();
            status.value = LookStatus(state: LookState.downloading, repo: repoLabel, bytes: total, progress: progress);
          });
        } catch (e) {
          if (cancel.isCancelled || (e is DioException && e.type == DioExceptionType.cancel)) rethrow;
          if (!file.required) {
            Logger.Inst().log('look: optional ${file.remote} skipped ($e)', className, 'download', LogTypes.booruHandlerInfo);
            try {
              if (dest.existsSync()) dest.deleteSync();
            } catch (_) {}
            done++;
            continue;
          }
          if (e is FormatException) rethrow;
          throw FormatException('Could not ${source == 'folder' ? 'copy' : 'download'} ${file.remote}: ${_why(e)}');
        }
        if (file.local == 'config.json' && dest.existsSync()) {
          final String type = (_json(dest)['model_type'] ?? '').toString().trim().toLowerCase();
          if (type.isNotEmpty && type != 'clip') {
            throw FormatException('This looks model is $type, and this app only runs CLIP. The picture half was not downloaded.');
          }
        }
        if (file.local == tokenizerFileName) {
          try {
            ClipTokenizer.fromJsonText(dest.readAsStringSync());
          } catch (e) {
            throw FormatException('tokenizer.json is not a CLIP tokenizer ($e).');
          }
        }
        done++;
      }
      Map<String, dynamic> pre = const {};
      final File preFile = File('$tmp$preprocessorFileName');
      if (preFile.existsSync()) pre = _json(preFile);
      final int inputSize = _inputSizeOf(pre) ?? defaultInputSize;
      final bool normalize = pre['do_normalize'] == true;
      final List<double>? mean = normalize ? _doubles(pre['image_mean']) : null;
      final List<double>? std = normalize ? _doubles(pre['image_std']) : null;
      final int bytes = File('$tmp$imageFileName').lengthSync() + File('$tmp$textFileName').lengthSync();
      final bool keepNpu = plan.npuRemote != null && (source != 'folder' || File('$tmp$npuImageFileName').existsSync());
      File('${tmp}manifest.json').writeAsStringSync(
        jsonEncode({
          'repo': repoLabel,
          'setting': setting,
          'bytes': bytes,
          'inputSize': inputSize,
          'mean': mean,
          'std': std,
          'dim': 0,
          'downloadedAt': DateTime.now().toIso8601String(),
          'source': source,
          'revision': ?revision,
          if (keepNpu) 'npuRemote': plan.npuRemote,
          'files': {for (final HfPlannedFile file in plan.files) if (File('$tmp${file.local}').existsSync()) file.local: file.remote},
        }),
      );
      await close();
      _apply(status.value, slug: '');
      final Directory target = Directory(dir);
      if (target.existsSync()) target.deleteSync(recursive: true);
      tmpDir.renameSync(target.path.substring(0, target.path.length - 1));
      _settings.lookModel = setting;
      unawaited(_saveSetting());
      await refresh();
      Logger.Inst().log('look: $source $repoLabel ready ($bytes bytes)', className, 'download', LogTypes.booruHandlerInfo);
      return isReady;
    } catch (e, s) {
      final String why = e is DioException
          ? (e.message ?? e.error?.toString() ?? e.type.name)
          : e is FormatException
          ? e.message
          : '$e';
      Logger.Inst().log('look $source of $repoLabel failed: $e', className, 'download', LogTypes.exception, s: s);
      try {
        final Directory tmpDir = Directory(tmp);
        if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
      } catch (_) {}
      status.value = LookStatus(state: LookState.error, repo: repoLabel, message: cancel.isCancelled ? 'Download cancelled.' : why);
      return false;
    }
  }

  static String _why(Object e) => e is DioException ? (e.message ?? e.error?.toString() ?? e.type.name) : '$e';

  void cancelDownload() => _downloading?.cancel('cancelled by the user');

  Future<void> delete() async {
    final String setting = _settings.lookModel;
    final String slug = _slug;
    await close();
    if (setting.trim().isNotEmpty) {
      try {
        final Directory dir = Directory(dirFor(setting));
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      } catch (e, s) {
        Logger.Inst().log('deleting the looks model failed: $e', className, 'delete', LogTypes.exception, s: s);
      }
      if (slug.isNotEmpty && _settings.dbEnabled) {
        try {
          await _settings.dbHandler.clearEmbeddings('look:$slug');
        } catch (_) {}
      }
    }
    _settings.lookModel = '';
    unawaited(_saveSetting());
    _apply(LookStatus.none, slug: '');
  }

  Future<void> _saveSetting() async {
    try {
      await _settings.saveSettings(restate: false);
    } catch (e) {
      Logger.Inst().log('looks setting not saved: $e', className, '_saveSetting', LogTypes.booruHandlerInfo);
    }
  }

  /// r80: the threads the open session was opened with (Settings → Models:
  /// the work that opens the model decides); null while it is closed.
  int? get openedThreads => _openThreads;
  int? _openThreads;

  /// r80: runs using the session right now, and a close asked for while
  /// one was running.
  int _inFlight = 0;
  bool _closeWhenIdle = false;

  /// r80: the thread counts changed (Settings → Models): the session is
  /// closed so the next use opens it with the new count - at once when
  /// nothing runs, else as soon as the running work is done. Never under a
  /// run: a run that fails switches the model off until a restart.
  void threadsChanged() {
    if (_runner == null && _loading == null) return;
    if (_inFlight > 0) {
      _closeWhenIdle = true;
      return;
    }
    unawaited(close());
  }

  /// A run ended; a close asked for meanwhile happens now.
  void _runEnded() {
    _inFlight--;
    if (_inFlight == 0 && _closeWhenIdle) {
      _closeWhenIdle = false;
      unawaited(close());
    } else if (_inFlight == 0 && _runner != null && _idle == null) {
      // r89 (review): the idle time ran out during the run (see _touch).
      _touch();
    }
  }

  /// Closes the sessions (the vectors in memory stay); not a failure.
  Future<void> close() async {
    _idle?.cancel();
    _idle = null;
    final LookRunner? r = _runner;
    _runner = null;
    _loading = null;
    _openThreads = null;
    _closeWhenIdle = false;
    if (r != null) {
      try {
        await r.close();
      } catch (_) {}
    }
  }

  void _dropRunner() {
    _idle?.cancel();
    _idle = null;
    final LookRunner? r = _runner;
    _runner = null;
    _loading = null;
    _openThreads = null;
    _closeWhenIdle = false;
    if (r != null) r.close().catchError((_) {});
  }

  static int? _inputSizeOf(Map<String, dynamic> pre) {
    final dynamic crop = pre['crop_size'];
    if (crop is Map && crop['height'] is num) return (crop['height'] as num).toInt();
    final dynamic size = pre['size'];
    if (size is Map) {
      if (size['shortest_edge'] is num) return (size['shortest_edge'] as num).toInt();
      if (size['height'] is num) return (size['height'] as num).toInt();
    }
    if (size is num) return size.toInt();
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

  // ── vectors ──

  /// One picture (encoded bytes) to a unit vector. r80: [use] decides the
  /// session's threads when this call opens it.
  Future<Float32List> imageVector(Uint8List bytes, {ModelUse use = ModelUse.waiting}) async {
    if (!isReady) throw StateError('No looks model downloaded (Settings → Recommendations → Looks model).');
    // r86: decoded by the phone at twice the model's size (or as before).
    final Float32List tensor = (await ModelPictures.forLooks(bytes, _inputSize, mean: _mean, std: _std)).tensor;
    Float32List out;
    _inFlight++;
    try {
      await _ensureLoaded(use);
      out = await _runner!.image(tensor, _inputSize);
    } catch (e) {
      _fail(e);
      rethrow;
    } finally {
      _runEnded();
    }
    _touch();
    normalizeInPlace(out);
    _dim = out.length;
    return out;
  }

  /// A sentence to a unit vector (null for an empty one); remembered.
  Future<Float32List?> textVector(String text, {ModelUse use = ModelUse.waiting}) async {
    final String t = text.trim();
    if (t.isEmpty) return null;
    if (!isReady) throw StateError('No looks model downloaded (Settings → Recommendations → Looks model).');
    final String key = 't:${EncoderHandler.textKey(t)}';
    final Float32List? hit = _recall(key);
    if (hit != null) return hit;
    Float32List out;
    _inFlight++;
    try {
      await _ensureLoaded(use);
      final ClipTokens tokens = _tokenizer!.encode(t);
      out = await _runner!.text(tokens.ids, tokens.mask);
    } catch (e) {
      _fail(e);
      rethrow;
    } finally {
      _runEnded();
    }
    _touch();
    normalizeInPlace(out);
    _dim = out.length;
    return _remember(key, out);
  }

  /// The items' vectors from memory, the database, or their thumbnails
  /// through the model — in that order; an item whose thumbnail cannot be
  /// read or embedded gets null and the others go on.
  Future<List<Float32List?>> imageVectors(List<BooruItem> items, {Booru? booru, ModelUse use = ModelUse.waiting}) async {
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
        final Map<String, Float32List> stored = await _settings.dbHandler.getEmbeddings(storeKey, [for (final int i in missing) keyOf(items[i])]);
        missing.removeWhere((int i) {
          final Float32List? v = stored[keyOf(items[i])];
          if (v == null || v.isEmpty) return false;
          out[i] = _remember('k:${keyOf(items[i])}', v);
          return true;
        });
      } catch (e, s) {
        Logger.Inst().log('reading look vectors failed: $e', className, 'imageVectors', LogTypes.exception, s: s);
      }
    }
    if (missing.isEmpty) return out;
    final Stopwatch sw = Stopwatch()..start();
    final Map<String, Float32List> fresh = {};
    int embedded = 0;
    for (final int i in missing) {
      if (items[i].thumbnailURL.isEmpty && items[i].sampleURL.isEmpty) continue;
      try {
        final Uint8List? bytes = await thumbnailFetcher(items[i], booru);
        if (bytes == null || bytes.isEmpty) continue;
        final Float32List v = await imageVector(bytes, use: use);
        out[i] = _remember('k:${keyOf(items[i])}', v);
        fresh[keyOf(items[i])] = v;
        embedded++;
      } catch (e) {
        Logger.Inst().log('look vector for ${keyOf(items[i])} failed: $e', className, 'imageVectors', LogTypes.booruHandlerInfo);
        if (!isReady) break;
      }
    }
    if (embedded > 0) {
      PerfTrace.instance.event('model.look', '$embedded thumbnails ${sw.elapsedMilliseconds} ms');
      Logger.Inst().log('look: $embedded thumbnails in ${sw.elapsedMilliseconds} ms (${_runner?.provider ?? ''})', className, 'imageVectors', LogTypes.booruHandlerInfo);
    }
    if (fresh.isNotEmpty && _settings.dbEnabled) {
      try {
        await _settings.dbHandler.putEmbeddings(storeKey, fresh);
      } catch (e, s) {
        Logger.Inst().log('storing look vectors failed: $e', className, 'imageVectors', LogTypes.exception, s: s);
      }
    }
    return out;
  }

  /// r76: a video's vector read from its frames (VideoFrames), in memory
  /// and in the database, over the one its preview picture gave.
  Future<void> putItemVector(BooruItem item, Float32List v) async {
    final String key = keyOf(item);
    _remember('k:$key', v);
    if (_settings.dbEnabled && _slug.isNotEmpty) {
      try {
        await _settings.dbHandler.putEmbeddings(storeKey, {key: v});
      } catch (e, s) {
        Logger.Inst().log("storing a video's look vector failed: $e", className, 'putItemVector', LogTypes.exception, s: s);
      }
    }
  }

  /// The average of unit vectors, made unit again; empty for none.
  static Float32List meanOf(List<Float32List> vectors) {
    if (vectors.isEmpty) return Float32List(0);
    final int n = vectors.first.length;
    final Float32List out = Float32List(n);
    for (final Float32List v in vectors) {
      for (int i = 0; i < n && i < v.length; i++) {
        out[i] += v[i];
      }
    }
    normalizeInPlace(out);
    return out;
  }

  /// An item's vector when it is already in memory (a scorer in a loop).
  Float32List? cached(BooruItem item) => _recall('k:${keyOf(item)}');

  @visibleForTesting
  void resetMemoryForTests() => _memory.clear();

  Float32List? _recall(String key) {
    final Float32List? v = _memory.remove(key);
    if (v != null) _memory[key] = v;
    return v;
  }

  Float32List _remember(String key, Float32List v) {
    _memory.remove(key);
    _memory[key] = v;
    while (_memory.length > _memoryCap) {
      _memory.remove(_memory.keys.first);
    }
    return v;
  }

  /// The picture as a CLIP model wants it (`preprocessor_config.json`):
  /// the shortest edge to [size], a centre crop of [size], RGB planes
  /// (channels first) scaled to 0-1, then `(x - mean) / std` when the model
  /// normalises (the OpenAI CLIP family does; MobileCLIP does not).
  static Float32List prepareImage(Uint8List bytes, int size, {List<double>? mean, List<double>? std}) {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (e) {
      throw FormatException('could not decode the image ($e)');
    }
    if (decoded == null) throw const FormatException('could not decode the image');
    return imageFromPicture(decoded, size, mean: mean, std: std);
  }

  /// r86: the same from a picture already decoded (by the phone, its short
  /// side at twice [size]: ModelPictures).
  static Float32List imageFromPicture(img.Image decoded, int size, {List<double>? mean, List<double>? std}) {
    img.Image src = decoded.format == img.Format.uint8 ? decoded : decoded.convert(format: img.Format.uint8);
    final int short = math.min(src.width, src.height);
    if (short != size) {
      final double scale = size / short;
      src = img.copyResize(
        src,
        width: math.max(size, (src.width * scale).round()),
        height: math.max(size, (src.height * scale).round()),
        interpolation: img.Interpolation.linear,
      );
    }
    if (src.width != size || src.height != size) {
      src = img.copyCrop(src, x: (src.width - size) ~/ 2, y: (src.height - size) ~/ 2, width: size, height: size);
    }
    final int plane = size * size;
    final Float32List out = Float32List(3 * plane);
    final bool norm = mean != null && std != null && mean.length >= 3 && std.length >= 3;
    int i = 0;
    for (final img.Pixel p in src) {
      double r = p.r / 255;
      double g = p.g / 255;
      double b = p.b / 255;
      if (norm) {
        r = (r - mean[0]) / std[0];
        g = (g - mean[1]) / std[1];
        b = (b - mean[2]) / std[2];
      }
      out[i] = r;
      out[plane + i] = g;
      out[2 * plane + i] = b;
      i++;
    }
    return out;
  }

  static void normalizeInPlace(Float32List v) {
    double s = 0;
    for (final double x in v) {
      s += x * x;
    }
    if (s <= 0) return;
    final double n = math.sqrt(s);
    for (int i = 0; i < v.length; i++) {
      v[i] = v[i] / n;
    }
  }

  static double cosine(List<double> a, List<double> b) {
    final int n = math.min(a.length, b.length);
    double s = 0;
    for (int i = 0; i < n; i++) {
      s += a[i] * b[i];
    }
    return s;
  }

  Future<void> _ensureLoaded(ModelUse use) => _loading ??= _load(use);

  Future<void> _load(ModelUse use) async {
    try {
      final String dir = dirFor(_settings.lookModel);
      _tokenizer ??= ClipTokenizer.fromJsonText(await File('$dir$tokenizerFileName').readAsString());
      _openThreads = ModelTasks.threads(ModelKind.look, use);
      // r87: on the NPU, the full-precision picture half when it is there
      // (without it the int8 one runs on the CPU, and the log says why).
      final bool npu = ModelTasks.runOn(ModelKind.look) == ModelAccelerator.npu;
      if (npu && !hasNpuFile) {
        Logger.Inst().log('look: the NPU needs the full-precision picture half (Settings -> Models); the CPU until then', className, '_load', LogTypes.booruHandlerInfo);
      }
      _runner = runnerFactory(npu && hasNpuFile ? npuImagePath : '$dir$imageFileName', '$dir$textFileName');
    } catch (e) {
      _loading = null;
      rethrow;
    }
  }

  void _fail(Object e) {
    Logger.Inst().log('looks model failed: $e', className, '_fail', LogTypes.exception);
    _dropRunner();
    final LookStatus s = status.value;
    status.value = LookStatus(state: LookState.error, repo: s.repo, bytes: s.bytes, dim: s.dim, inputSize: s.inputSize, downloadedAt: s.downloadedAt, message: 'The model could not be run: $e');
  }

  void _touch() {
    _idle?.cancel();
    _idle = Timer(idleClose, () {
      _idle = null;
      // r89 (review): never under a run (as the tagger, r79) - a closed
      // session fails the run, and on the NPU that counted as an NPU failure.
      // The run re-arms the timer when it ends.
      if (_runner == null || _inFlight > 0) return;
      Logger.Inst().log('look: sessions closed (idle)', className, '_touch', LogTypes.booruHandlerInfo);
      unawaited(close());
    });
  }

  // ── defaults ──

  static Future<Uint8List?> _defaultThumbnail(BooruItem item, Booru? booru) => PixelTags.thumbnailBytes(item, booru);

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
        headers: const {'User-Agent': 'LoliSnatcher (looks model download)'},
      ),
    );
  }

  static LookRunner _onnxRunner(String imagePath, String textPath) => OnnxLookRunner(imagePath, textPath, threads: LookModelHandler.maybe?._openThreads);
}
