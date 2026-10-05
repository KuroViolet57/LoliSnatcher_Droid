import 'dart:convert';
import 'dart:io';

/// Which downloadable model a Hugging Face repo, or a folder of files, is for.
enum HfKind { tagger, encoder, look }

/// A Hugging Face repo id, optionally pinned to a branch, tag or commit.
class HfRepoId {
  const HfRepoId(this.owner, this.name, {this.revision});

  final String owner;
  final String name;

  /// From the link (`/tree/<rev>`) or from `owner/model@rev`. Null means the
  /// repo's default revision, which the file-list API names.
  final String? revision;

  String get id => '$owner/$name';
}

class HfParseResult {
  const HfParseResult._({this.repo, this.error});

  final HfRepoId? repo;
  final String? error;
}

/// One file to copy. [local] is the name the handlers already open.
class HfPlannedFile {
  const HfPlannedFile({required this.remote, required this.local, this.required = true});

  /// Path inside the repo, or the relative path inside a picked folder.
  final String remote;

  final String local;

  /// A missing optional file is skipped. A missing required file fails the import.
  final bool required;
}

class HfPlan {
  const HfPlan({this.files = const [], this.npuRemote, this.error});

  final List<HfPlannedFile> files;

  /// Full-precision picture half, when the chosen picture file is the
  /// quantized one. The NPU download uses it later. Not fetched up front.
  final String? npuRemote;

  final String? error;

  String? remote(String local) {
    for (final HfPlannedFile file in files) {
      if (file.local == local) return file.remote;
    }
    return null;
  }
}

/// One child of a folder the user picked.
class HfFolderFile {
  const HfFolderFile(this.name, this.isDir, this.uri);

  final String name;
  final bool isDir;
  final String uri;
}

/// How a model handler asks for a repo's file list. [revision] is the branch,
/// tag or commit from the link, or null for the repo's default branch.
typedef HfListingFetch = Future<HfListing> Function(String repoId, {String? revision});

/// The file list Hugging Face returns for one repo.
class HfListing {
  const HfListing({required this.id, required this.revision, required this.files, this.error});

  factory HfListing.failed(String message) => HfListing(id: '', revision: 'main', files: const [], error: message);

  /// Canonical `owner/model` from the API, when the call worked.
  final String id;

  /// Commit sha, or `main` when the API gave none.
  final String revision;

  final List<String> files;
  final String? error;

  bool get ok => error == null;
}

/// Turns a typed repo, a Hugging Face link, or a folder listing into the
/// files the three model handlers already know how to open.
class HfRepo {
  static const String howTo = 'A Hugging Face repo id looks like owner/model. A link to the repo page works too.';

  /// True when [raw] is a folder import, including quotes or a zero-width
  /// prefix that [parse] strips before it sees `files:`.
  static bool isFolderImport(String raw) {
    final String? error = parse(raw).error;
    return error != null && error.startsWith('This model was imported from a folder.');
  }

  static final RegExp _owner = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,80}$');
  static final RegExp _name = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,120}$');
  static final RegExp _revision = RegExp(r'^[A-Za-z0-9._-]{1,80}$');

  /// A branch, tag or commit this app will put in a URL. `.` and `..` match
  /// [_revision] and are still refused, because a URL parser treats them as
  /// directories.
  static bool _allowedRevision(String revision) => revision != '.' && revision != '..' && _revision.hasMatch(revision);
  static final RegExp _direct = RegExp(r'^([A-Za-z0-9][A-Za-z0-9._-]{0,80})/([A-Za-z0-9][A-Za-z0-9._-]{0,120})(?:@([A-Za-z0-9._-]{1,80}))?/?$');
  static final RegExp _httpUrl = RegExp(r'https?://[^\s<>)\]]+', caseSensitive: false);
  static final RegExp _bareHost = RegExp(r'(?:www\.)?(?:huggingface\.co|hf\.co)/[^\s<>)\]]+', caseSensitive: false);

  static HfParseResult parse(String raw) {
    String text = raw.replaceAll('\u00a0', ' ').replaceAll('\u200b', '').trim();
    if (text.length >= 2) {
      final String open = text[0];
      final String close = text[text.length - 1];
      if ((open == '"' && close == '"') || (open == "'" && close == "'") || (open == '`' && close == '`')) {
        text = text.substring(1, text.length - 1).trim();
      }
    }
    if (text.isEmpty) return const HfParseResult._(error: howTo);
    if (text.startsWith('files:')) {
      return const HfParseResult._(error: 'This model was imported from a folder. Use Import from a folder again, or type a Hugging Face repo (owner/model).');
    }
    final Match? direct = _direct.firstMatch(text);
    if (direct != null) {
      return HfParseResult._(repo: HfRepoId(direct.group(1)!, direct.group(2)!, revision: direct.group(3)));
    }
    final List<Uri> urls = _urlsIn(text);
    if (urls.length > 1) return const HfParseResult._(error: '$howTo One link at a time.');
    if (urls.length == 1) return _fromUri(urls.single);
    if (text.contains('/') && !text.contains(' ')) {
      return const HfParseResult._(error: '$howTo Drop anything after the model name.');
    }
    return const HfParseResult._(error: howTo);
  }

  static List<Uri> _urlsIn(String text) {
    final List<Uri> out = [];
    for (final Match match in _httpUrl.allMatches(text)) {
      final Uri? uri = Uri.tryParse(match.group(0)!);
      if (uri != null && uri.host.isNotEmpty) out.add(uri);
    }
    if (out.isNotEmpty) return out;
    for (final Match match in _bareHost.allMatches(text)) {
      final Uri? uri = Uri.tryParse('https://${match.group(0)}');
      if (uri != null && uri.host.isNotEmpty) out.add(uri);
    }
    return out;
  }

  static HfParseResult _fromUri(Uri uri) {
    final String host = uri.host.toLowerCase();
    if (host != 'huggingface.co' && host != 'www.huggingface.co' && host != 'hf.co') {
      return const HfParseResult._(error: '$howTo The link has to be on huggingface.co.');
    }
    final List<String> segments = [for (final String segment in uri.pathSegments) if (segment.isNotEmpty) segment];
    if (segments.length < 2 || !_owner.hasMatch(segments[0]) || !_name.hasMatch(segments[1])) {
      return const HfParseResult._(error: howTo);
    }
    String? revision;
    if (segments.length >= 4 && (segments[2] == 'tree' || segments[2] == 'blob' || segments[2] == 'resolve' || segments[2] == 'commit')) {
      // A segment that is not a branch, tag or commit must not become "no
      // revision", because that lists the default branch.
      if (!_allowedRevision(segments[3])) {
        return const HfParseResult._(error: '$howTo That revision cannot be used.');
      }
      revision = segments[3];
    } else if (segments.length > 2) {
      return const HfParseResult._(error: '$howTo Use the repo page, not a file inside it.');
    }
    return HfParseResult._(repo: HfRepoId(segments[0], segments[1], revision: revision));
  }

  /// `resolve/<revision>/<file>`. Each path piece is encoded. A revision that
  /// is not a branch, tag or commit falls back to `main`.
  static String resolveUrl(String repo, String revision, String file) {
    final String rev = _revision.hasMatch(revision) ? revision : 'main';
    final String path = [for (final String piece in file.split('/')) if (piece.isNotEmpty) Uri.encodeComponent(piece)].join('/');
    return 'https://huggingface.co/$repo/resolve/$rev/$path';
  }

  static String slug(String text) => text.trim().toLowerCase().replaceAll('/', '__').replaceAll(RegExp(r'[^a-z0-9._\-]'), '-');

  /// Setting value for a model that came from a folder, not from a repo.
  static String localSetting(String label) => 'files:${slug(label.trim().isEmpty ? 'imported' : label)}';

  /// The folder name when every file sits in one directory. Otherwise `imported`.
  static String labelFor(Iterable<String> paths) {
    final Set<String> tops = {
      for (final String path in paths)
        if (path.contains('/')) path.split('/').first,
    };
    if (tops.length == 1 && paths.every((String path) => path.startsWith('${tops.first}/'))) return tops.first;
    return 'imported';
  }

  static HfPlan choose(HfKind kind, List<String> raw) {
    final List<String> files = [for (final String file in raw) if (_safePath(file)) file];
    switch (kind) {
      case HfKind.tagger:
        return _tagger(files);
      case HfKind.encoder:
        return _encoder(files);
      case HfKind.look:
        return _look(files);
    }
  }

  /// Relative path to the uri of that file. Root files, plus the files in
  /// each directory [children] names. Names that could leave the folder are dropped.
  static Map<String, String> indexFolder(List<HfFolderFile> root, Map<String, List<HfFolderFile>> children) {
    final Map<String, String> out = {};
    for (final HfFolderFile file in root) {
      if (file.isDir || !_safeName(file.name)) continue;
      out[file.name] = file.uri;
    }
    for (final MapEntry<String, List<HfFolderFile>> entry in children.entries) {
      if (!_safeName(entry.key)) continue;
      for (final HfFolderFile file in entry.value) {
        if (file.isDir || !_safeName(file.name)) continue;
        out['${entry.key}/${file.name}'] = file.uri;
      }
    }
    return out;
  }

  /// What to say when the configured model is not on disk. A folder import
  /// cannot be downloaded; the sentence names Import from a folder.
  static String missingOnDiskMessage(String setting) {
    final String? error = parse(setting).error;
    if (error != null && error.startsWith('This model was imported from a folder.')) return error;
    return 'The model files are missing; download again.';
  }

  /// File list for [revision], or the repo's default branch when [revision]
  /// is null. Probed 2026-10-05 against `openai-community/gpt2`:
  /// `/api/models/<id>` is the default branch (sha `607a30d7…`, 26 files) and
  /// `/api/models/<id>/revision/<rev>` is that commit (sha `e7da7f22…`, 15
  /// files). A `?revision=` query is ignored. An unknown rev is HTTP 404
  /// `{"error":"Invalid rev id: …"}`. Null when [revision] is not a branch,
  /// tag or commit this app will put in a URL.
  static String? listingUrl(String repoId, String? revision) {
    final String root = 'https://huggingface.co/api/models/$repoId';
    if (revision == null || revision.isEmpty) return root;
    // `.` and `..` match the revision pattern, then Uri.parse folds
    // `/revision/..` back to the default-branch URL.
    if (!_allowedRevision(revision)) return null;
    return '$root/revision/${Uri.encodeComponent(revision)}';
  }

  /// `GET` [listingUrl]. The `id` is the canonical casing, `sha` is the
  /// revision the file list was taken from, `siblings[].rfilename` is the files.
  static Future<HfListing> fetch(String repoId, {String? revision}) async {
    final String? url = listingUrl(repoId, revision);
    if (url == null) return HfListing.failed('Hugging Face could not list $repoId at $revision.');
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 30));
      request.headers.set(HttpHeaders.userAgentHeader, 'LoliSnatcher (model import)');
      final HttpClientResponse response = await request.close().timeout(const Duration(seconds: 30));
      final String body = await response.transform(utf8.decoder).join();
      if (response.statusCode == 401) {
        return HfListing.failed('Hugging Face refused $repoId. The name may be wrong, or the repo is private or gated.');
      }
      if (response.statusCode != 200) {
        final String where = revision == null || revision.isEmpty ? repoId : '$repoId at $revision';
        return HfListing.failed('Hugging Face answered ${response.statusCode} for $where.');
      }
      final dynamic decoded = jsonDecode(body);
      if (decoded is! Map) return HfListing.failed('Hugging Face returned an unexpected file list for $repoId.');
      final String? apiId = decoded['id'] is String ? decoded['id'] as String : null;
      final HfRepoId? canonical = apiId == null ? null : parse(apiId).repo;
      final String id = canonical != null && canonical.revision == null ? canonical.id : repoId;
      // Named `sha`, not `revision`: a local with the parameter's name is in
      // scope for the whole function and hides the revision we were asked for.
      final String sha = decoded['sha'] is String && _revision.hasMatch(decoded['sha'] as String) ? decoded['sha'] as String : 'main';
      final List<String> files = [
        for (final dynamic sibling in (decoded['siblings'] as List? ?? const []))
          if (sibling is Map && sibling['rfilename'] is String && _safePath(sibling['rfilename'] as String)) sibling['rfilename'] as String,
      ];
      return HfListing(id: id, revision: sha, files: files);
    } catch (e) {
      return HfListing.failed('Could not read the file list for $repoId ($e).');
    } finally {
      client.close(force: true);
    }
  }

  static bool _safePath(String file) {
    // A raw string cannot end in a single backslash, which is the character.
    // ignore: use_raw_strings
    if (file.isEmpty || file.startsWith('/') || file.startsWith('\\')) return false;
    // ignore: use_raw_strings
    if (file.contains('\\') || file.split('/').any((String piece) => piece == '..' || piece == '.')) return false;
    return true;
  }

  // ignore: use_raw_strings
  static bool _safeName(String name) => name.isNotEmpty && name != '.' && name != '..' && !name.contains('/') && !name.contains('\\') && !name.contains('..');

  static String? _pick(List<String> files, List<String> preferences, void Function(String listed) onSeveral) {
    for (final String preference in preferences) {
      final List<String> hits = [for (final String file in files) if (file == preference || file.endsWith('/$preference')) file];
      if (hits.isEmpty) continue;
      if (hits.contains(preference)) return preference;
      if (hits.length == 1) return hits.single;
      hits.sort();
      onSeveral(hits.join(', '));
      return null;
    }
    return null;
  }

  static String? _beside(List<String> files, String chosen, List<String> names) {
    final int slash = chosen.lastIndexOf('/');
    final String dir = slash < 0 ? '' : chosen.substring(0, slash + 1);
    for (final String name in names) {
      if (files.contains('$dir$name')) return '$dir$name';
    }
    String? several;
    final String? any = _pick(files, names, (String listed) => several = listed);
    if (several != null) return null;
    return any;
  }

  static String _onnxList(List<String> files) {
    final List<String> onnx = [for (final String file in files) if (file.toLowerCase().endsWith('.onnx')) file];
    if (onnx.isEmpty) return 'none';
    final String shown = onnx.take(8).join(', ');
    return onnx.length > 8 ? '$shown, …' : shown;
  }

  static HfPlan _tagger(List<String> files) {
    String? several;
    String? onnx = _pick(files, const ['model.onnx'], (String listed) => several = listed);
    if (several != null) {
      return HfPlan(error: "Several copies of model.onnx: $several. Open the model's own folder.");
    }
    if (onnx == null) {
      final List<String> any = [for (final String file in files) if (file.toLowerCase().endsWith('.onnx')) file];
      if (any.length == 1) {
        onnx = any.single;
      } else if (any.length > 1) {
        return HfPlan(error: "Several ONNX files and none is model.onnx: ${any.take(8).join(', ')}. Open the model's own folder.");
      }
    }
    if (onnx == null) {
      return HfPlan(error: 'This image tagger needs model.onnx (one picture in, one score per tag out) and selected_tags.csv. ONNX files here: ${_onnxList(files)}.');
    }
    final String? tags = _beside(files, onnx, const ['selected_tags.csv', 'tags.csv']);
    if (tags == null) {
      return HfPlan(error: 'This image tagger needs selected_tags.csv (or tags.csv) next to $onnx. ONNX files here: ${_onnxList(files)}.');
    }
    final String? config = _beside(files, onnx, const ['config.json']);
    final String? data = files.contains('$onnx.data')
        ? '$onnx.data'
        : files.contains('${onnx}_data')
        ? '${onnx}_data'
        : null;
    return HfPlan(
      files: [
        HfPlannedFile(remote: tags, local: 'selected_tags.csv'),
        if (config != null) HfPlannedFile(remote: config, local: 'config.json', required: false),
        HfPlannedFile(remote: onnx, local: 'model.onnx'),
        if (data != null) HfPlannedFile(remote: data, local: 'model.onnx.data'),
      ],
    );
  }

  static HfPlan _encoder(List<String> files) {
    String? several;
    final String? model = _pick(files, const [
      'onnx/model_quantized.onnx',
      'model_quantized.onnx',
      'onnx/model.onnx',
      'model.onnx',
      'onnx/model_qint8_arm64.onnx',
    ], (String listed) => several = listed);
    if (several != null) {
      return HfPlan(error: "Several copies of the text model: $several. Open the model's own folder.");
    }
    if (model == null) {
      return HfPlan(
        error:
            'This text encoder needs an ONNX file (onnx/model_quantized.onnx or onnx/model.onnx) and vocab.txt (WordPiece). '
            'fp16, q4 and AVX builds are skipped. ONNX files here: ${_onnxList(files)}.',
      );
    }
    if (!files.contains('vocab.txt') && !files.any((String file) => file.endsWith('/vocab.txt'))) {
      final bool hasTokenizer = files.any((String file) => file == 'tokenizer.json' || file.endsWith('/tokenizer.json'));
      return HfPlan(
        error: hasTokenizer
            ? 'This text encoder needs vocab.txt (WordPiece). This repo has tokenizer.json and no vocab.txt, so it cannot be loaded.'
            : 'This text encoder needs vocab.txt (WordPiece) next to the model. ONNX files here: ${_onnxList(files)}.',
      );
    }
    final String vocab = _beside(files, model, const ['vocab.txt']) ?? (files.contains('vocab.txt') ? 'vocab.txt' : files.firstWhere((String file) => file.endsWith('/vocab.txt')));
    final String? tokenizerConfig = _beside(files, model, const ['tokenizer_config.json']) ?? (files.contains('tokenizer_config.json') ? 'tokenizer_config.json' : null);
    final String? config = _beside(files, model, const ['config.json']) ?? (files.contains('config.json') ? 'config.json' : null);
    if (tokenizerConfig == null || config == null) {
      return HfPlan(error: 'This text encoder also needs tokenizer_config.json and config.json. ONNX files here: ${_onnxList(files)}.');
    }
    final String? data = files.contains('$model.data') ? '$model.data' : null;
    return HfPlan(
      files: [
        HfPlannedFile(remote: vocab, local: 'vocab.txt'),
        HfPlannedFile(remote: tokenizerConfig, local: 'tokenizer_config.json'),
        HfPlannedFile(remote: config, local: 'config.json'),
        HfPlannedFile(remote: model, local: 'model.onnx'),
        if (data != null) HfPlannedFile(remote: data, local: 'model.onnx.data'),
      ],
    );
  }

  static HfPlan _look(List<String> files) {
    String? several;
    final String? vision = _pick(files, const [
      'onnx/vision_model_quantized.onnx',
      'vision_model_quantized.onnx',
      'onnx/vision_model.onnx',
      'vision_model.onnx',
    ], (String listed) => several = listed);
    if (several != null) {
      return HfPlan(error: "Several copies of the picture half: $several. Open the model's own folder.");
    }
    final String? text = vision == null
        ? null
        : _pick(files, const ['onnx/text_model_quantized.onnx', 'text_model_quantized.onnx', 'onnx/text_model.onnx', 'text_model.onnx'], (String listed) => several = listed);
    if (several != null) {
      return HfPlan(error: "Several copies of the text half: $several. Open the model's own folder.");
    }
    if (vision == null || text == null) {
      final bool combined = files.any((String file) => file == 'onnx/model.onnx' || file.endsWith('/model.onnx'));
      return HfPlan(
        error:
            'This looks model needs separate vision and text ONNX files (onnx/vision_model.onnx and onnx/text_model.onnx) and tokenizer.json.'
            '${combined ? ' A single onnx/model.onnx is the whole network, which this app does not run.' : ''}'
            ' ONNX files here: ${_onnxList(files)}.',
      );
    }
    final String? tokenizer = _beside(files, vision, const ['tokenizer.json']) ?? (files.contains('tokenizer.json') ? 'tokenizer.json' : null);
    if (tokenizer == null) {
      return HfPlan(error: 'This looks model needs tokenizer.json (a CLIP tokenizer) next to the ONNX files. ONNX files here: ${_onnxList(files)}.');
    }
    final String? config = _beside(files, vision, const ['config.json']) ?? (files.contains('config.json') ? 'config.json' : null);
    final String? preprocessor = _beside(files, vision, const ['preprocessor_config.json']) ?? (files.contains('preprocessor_config.json') ? 'preprocessor_config.json' : null);
    String? npu;
    if (vision.contains('_quantized')) {
      final String full = vision.replaceFirst('_quantized', '');
      if (files.contains(full)) npu = full;
    }
    return HfPlan(
      npuRemote: npu,
      files: [
        if (config != null) HfPlannedFile(remote: config, local: 'config.json', required: false),
        HfPlannedFile(remote: tokenizer, local: 'tokenizer.json'),
        if (preprocessor != null) HfPlannedFile(remote: preprocessor, local: 'preprocessor_config.json', required: false),
        HfPlannedFile(remote: vision, local: 'vision_model.onnx'),
        HfPlannedFile(remote: text, local: 'text_model.onnx'),
      ],
    );
  }
}
