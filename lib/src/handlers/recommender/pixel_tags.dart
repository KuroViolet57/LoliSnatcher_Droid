import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/recommender/image_tagger_handler.dart';
import 'package:lolisnatcher/src/services/image_writer.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// r74: what the downloaded tagger reads in a post's thumbnail, for a
/// reaction (Settings → Recommendations → Tag reactions with the picture).
/// The thumbnail is what the site chose to show — for a video, its preview
/// frame — read from the grid's cache when it is there.
class PixelTags {
  const PixelTags._();

  static const Duration fetchTimeout = Duration(seconds: 20);

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

  /// The picture's tags for a reaction: characters and general tags, names only.
  static Future<List<String>> forItem(BooruItem item, Booru? booru) async {
    final ImageTaggerHandler? t = ImageTaggerHandler.maybe;
    if (t == null || !t.enabled) return const [];
    final Uint8List? bytes = await thumbnailBytes(item, booru);
    if (bytes == null || bytes.isEmpty) return const [];
    final TaggerResult r = await t.tag(bytes);
    return [for (final PixelTag p in r.all) p.tag];
  }
}
