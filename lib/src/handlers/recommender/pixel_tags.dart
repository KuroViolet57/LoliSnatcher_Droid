import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/recommender/image_tagger_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/video_frames.dart';
import 'package:lolisnatcher/src/services/image_writer.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// r74: what the downloaded tagger reads in a post, for a reaction
/// (Settings → Recommendations → Tag reactions with the picture).
/// r76: a video's frames from the player when there are some (the first,
/// the middle and the last), their tags merged; otherwise the thumbnail the
/// site chose to show, read from the grid's cache when it is there.
class PixelTags {
  const PixelTags._();

  static const Duration fetchTimeout = Duration(seconds: 20);

  // Seams, replaced in tests.
  static bool Function() taggerReady = _defaultTaggerReady;
  static List<Uint8List> Function(BooruItem item) framesFor = _defaultFramesFor;
  static Future<TaggerResult> Function(Uint8List bytes) tagBytes = _defaultTagBytes;
  static Future<Uint8List?> Function(BooruItem item, Booru? booru) thumbnail = thumbnailBytes;

  static void resetForTests() {
    taggerReady = _defaultTaggerReady;
    framesFor = _defaultFramesFor;
    tagBytes = _defaultTagBytes;
    thumbnail = thumbnailBytes;
  }

  static bool _defaultTaggerReady() => ImageTaggerHandler.maybe?.enabled ?? false;

  static List<Uint8List> _defaultFramesFor(BooruItem item) => VideoFrames.maybe?.framesOf(item) ?? const <Uint8List>[];

  // r79: a reaction's tags are background work - the light session.
  static Future<TaggerResult> _defaultTagBytes(Uint8List bytes) => ImageTaggerHandler.instance.tag(bytes, use: TaggerUse.background);

  /// The thumbnail's bytes: the grid's cache first, else a download with
  /// the booru's own headers.
  static Future<Uint8List?> thumbnailBytes(BooruItem item, Booru? booru) async {
    final String url = item.thumbnailURL.isNotEmpty ? item.thumbnailURL : item.sampleURL;
    if (url.isEmpty) return null;
    try {
      final String? cached = await ImageWriter().getCachePath(Uri.base.resolve(url).toString(), 'thumbnails', fileNameExtras: item.fileNameExtras);
      if (cached != null) return File(cached).readAsBytesSync();
    } catch (_) {}
    Map<String, String> headers = {'User-Agent': Tools.browserUserAgent};
    if (booru != null) {
      try {
        headers = await Tools.getFileCustomHeaders(booru, item: item, checkForReferer: true);
      } catch (_) {}
    }
    final Response<dynamic> res = await DioNetwork.get(url, headers: headers, options: Options(responseType: ResponseType.bytes)).timeout(fetchTimeout);
    return res.data is List<int> ? Uint8List.fromList(res.data as List<int>) : null;
  }

  /// The picture's tags for a reaction: characters first, then general tags.
  static Future<List<String>> forItem(BooruItem item, Booru? booru) async {
    if (!taggerReady()) return const [];
    final List<Uint8List> frames = framesFor(item);
    if (frames.isNotEmpty) {
      // A set literal keeps its order and drops a repeated index.
      final List<int> picks = {0, frames.length ~/ 2, frames.length - 1}.toList();
      final List<TaggerResult> results = [for (final int i in picks) await tagBytes(frames[i])];
      return mergeNames(results);
    }
    final Uint8List? bytes = await thumbnail(item, booru);
    if (bytes == null || bytes.isEmpty) return const [];
    final TaggerResult r = await tagBytes(bytes);
    return [for (final PixelTag p in r.all) p.tag];
  }

  /// Tags of several frames as one list: each tag at its best confidence,
  /// characters first, strongest first, first seen first on a tie.
  static List<String> mergeNames(List<TaggerResult> results) {
    final Map<String, PixelTag> best = {};
    final Map<String, int> firstSeen = {};
    for (final TaggerResult r in results) {
      for (final PixelTag p in r.all) {
        firstSeen.putIfAbsent(p.tag, () => firstSeen.length);
        final PixelTag? prev = best[p.tag];
        if (prev == null || p.confidence > prev.confidence) best[p.tag] = p;
      }
    }
    int order(PixelTag a, PixelTag b) {
      final int c = b.confidence.compareTo(a.confidence);
      return c != 0 ? c : firstSeen[a.tag]!.compareTo(firstSeen[b.tag]!);
    }

    final List<PixelTag> characters = best.values.where((p) => p.character).toList()..sort(order);
    final List<PixelTag> general = best.values.where((p) => !p.character).toList()..sort(order);
    return [for (final PixelTag p in characters) p.tag, for (final PixelTag p in general) p.tag];
  }
}
