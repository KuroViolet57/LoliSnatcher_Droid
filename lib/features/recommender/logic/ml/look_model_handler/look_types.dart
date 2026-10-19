part of '../look_model_handler.dart';

/// The "looks" model the user can download from Hugging Face (r75): a
/// CLIP-family pair of ONNX halves (MobileCLIP presets) that turn a picture,
/// or a sentence, into one unit vector in a shared space, so two pictures
/// that look alike — or a picture and the words that describe it — sit
/// close. Boards and "Posts like this" order candidates by it; For You
/// learns from it. Thumbnails are embedded once and kept in the database.
class LookPreset {
  const LookPreset({
    required this.id,
    required this.repo,
    required this.label,
    required this.description,
    required this.imageBytes,
    required this.textBytes,
    this.imageFile = LookModelHandler.defaultImageRemote,
    this.textFile = LookModelHandler.defaultTextRemote,
    this.npuImageBytes,
  });

  /// r87: the full-precision picture half (`onnx/vision_model.onnx`) the NPU
  /// runs, fetched when the NPU is chosen.
  final int? npuImageBytes;

  final String id;
  final String repo;
  final String label;
  final String description;
  final int imageBytes;
  final int textBytes;
  final String imageFile;
  final String textFile;

  int get bytes => imageBytes + textBytes;

  static const LookPreset s0 = LookPreset(
    id: 's0',
    repo: 'Xenova/mobileclip_s0',
    label: 'Small (55 MB)',
    description: 'MobileCLIP-S0, 8-bit: 12 MB for pictures, 43 MB for words. Made for phones; a thumbnail in a few tens of milliseconds.',
    imageBytes: 11846843,
    textBytes: 42799238,
    npuImageBytes: 45543630,
  );

  static const LookPreset s2 = LookPreset(
    id: 's2',
    repo: 'Xenova/mobileclip_s2',
    label: 'Larger (101 MB)',
    description: 'MobileCLIP-S2, 8-bit: 37 MB for pictures, 64 MB for words. Better matches, roughly three times slower.',
    imageBytes: 36735889,
    textBytes: 64117260,
    npuImageBytes: 143020962,
  );

  static const List<LookPreset> values = [s0, s2];

  static LookPreset? byId(String id) {
    for (final LookPreset p in values) {
      if (p.id == id) return p;
    }
    return null;
  }
}

enum LookState { none, downloading, ready, error }

@immutable
class LookStatus {
  const LookStatus({
    required this.state,
    this.progress = 0,
    this.message = '',
    this.repo = '',
    this.bytes = 0,
    this.dim = 0,
    this.inputSize = 0,
    this.downloadedAt,
  });

  static const LookStatus none = LookStatus(state: LookState.none);

  final LookState state;
  final double progress;
  final String message;
  final String repo;
  final int bytes;
  final int dim;
  final int inputSize;
  final DateTime? downloadedAt;
}

/// Runs the two halves: a picture `[1, 3, size, size]` (0-1, RGB planes)
/// to a vector; token ids and their mask `[1, length]` to a vector.
abstract class LookRunner {
  String get provider;
  Future<Float32List> image(Float32List nchw, int size);
  Future<Float32List> text(List<int> ids, List<int> mask);
  Future<void> close();
}

typedef LookFetcher = Future<void> Function(String url, File to, {void Function(int received, int total)? onProgress, CancelToken? cancelToken});

typedef LookRunnerFactory = LookRunner Function(String imageModelPath, String textModelPath);

typedef ThumbnailFetcher = Future<Uint8List?> Function(BooruItem item, Booru? booru);
