import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// One reverse-image match: the site and post it points at, how similar,
/// and the character / series / artist names the index attached to it,
/// already spelled as booru tags.
class ReverseMatch {
  const ReverseMatch({
    required this.site,
    this.postId,
    required this.similarity,
    this.urls = const [],
    this.tags = const [],
    this.thumbnail,
    this.alsoOn = const {},
  });

  /// `danbooru`, `gelbooru`, `yandere`, `konachan`, `sankaku`, `e621`,
  /// `anime-pictures`, `idol`, or `other`.
  final String site;
  final String? postId;
  final double similarity;
  final List<String> urls;
  final List<String> tags;
  final String? thumbnail;

  /// The same picture's post ids on other sites, by site.
  final Map<String, String> alsoOn;

  Map<String, dynamic> toJson() => {
    'site': site,
    'postId': postId,
    'similarity': similarity,
    'urls': urls,
    'tags': tags,
    'thumbnail': thumbnail,
    'alsoOn': alsoOn,
  };

  factory ReverseMatch.fromJson(Map<String, dynamic> json) => ReverseMatch(
    site: json['site']?.toString() ?? 'other',
    postId: json['postId']?.toString(),
    similarity: (json['similarity'] as num?)?.toDouble() ?? 0,
    urls: [for (final dynamic u in (json['urls'] as List?) ?? const []) u.toString()],
    tags: [for (final dynamic t in (json['tags'] as List?) ?? const []) t.toString()],
    thumbnail: json['thumbnail']?.toString(),
    alsoOn: {for (final MapEntry<dynamic, dynamic> e in ((json['alsoOn'] as Map?) ?? const {}).entries) e.key.toString(): e.value.toString()},
  );
}

typedef ReversePoster = Future<Response<dynamic>> Function(String url, {Object? data, Map<String, String>? headers, Options? options});

/// Reverse image search for boards (r73). SauceNAO indexes most boorus and
/// names the character, series and artist of a match, but its API is closed
/// to anonymous callers (checked 2026-09-18: "The anonymous account type
/// does not permit API usage"), so it runs on the user's own key. e621 has
/// its own iqdb that takes a file upload.
class ReverseImageSearch {
  const ReverseImageSearch._();

  static const String sauceNaoUrl = 'https://saucenao.com/search.php';

  /// Below this SauceNAO similarity a result is noise.
  static const double sauceNaoMinSimilarity = 55;

  /// Below this e621 iqdb score a result is noise.
  static const double e621MinScore = 60;

  /// The per-site post id keys SauceNAO puts in `data`, in preference order.
  static const List<MapEntry<String, String>> siteIdKeys = [
    MapEntry('danbooru', 'danbooru_id'),
    MapEntry('gelbooru', 'gelbooru_id'),
    MapEntry('yandere', 'yandere_id'),
    MapEntry('konachan', 'konachan_id'),
    MapEntry('sankaku', 'sankaku_id'),
    MapEntry('e621', 'e621_id'),
    MapEntry('anime-pictures', 'anime-pictures_id'),
    MapEntry('idol', 'idol_id'),
  ];

  static ReversePoster poster = _defaultPoster;

  static Future<Response<dynamic>> _defaultPoster(String url, {Object? data, Map<String, String>? headers, Options? options}) =>
      DioNetwork.post(url, data: data, headers: headers, options: options);

  static void resetForTests() {
    poster = _defaultPoster;
  }

  /// SauceNAO: the image as a file upload or by url.
  static Future<List<ReverseMatch>> sauceNao({
    required String apiKey,
    List<int>? imageBytes,
    String? imageUrl,
    int numres = 8,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw StateError('SauceNAO needs an API key (Settings → Recommendations → Boards).');
    }
    final bool hasBytes = imageBytes != null && imageBytes.isNotEmpty;
    if (!hasBytes && (imageUrl == null || imageUrl.isEmpty)) {
      throw ArgumentError('No image to search for.');
    }
    final FormData form = FormData.fromMap({
      'api_key': apiKey.trim(),
      'output_type': '2',
      'numres': '$numres',
      'db': '999',
      if (hasBytes) 'file': MultipartFile.fromBytes(imageBytes, filename: 'image.jpg') else 'url': imageUrl,
    });
    final Response<dynamic> res = await poster(
      sauceNaoUrl,
      data: form,
      headers: {'User-Agent': Tools.browserUserAgent, 'Accept': 'application/json'},
      options: Options(responseType: ResponseType.json, validateStatus: (_) => true),
    ).timeout(const Duration(seconds: 30));
    return parseSauceNao(res.data);
  }

  /// The JSON answer (output_type 2). A non-zero header status is the
  /// site's refusal (limits, key) and comes back as an error with its text.
  static List<ReverseMatch> parseSauceNao(dynamic json) {
    dynamic data = json;
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {
        throw const FormatException('SauceNAO answered no JSON (a challenge page or an outage).');
      }
    }
    if (data is! Map) throw const FormatException('SauceNAO answered an unexpected shape.');
    final Map<dynamic, dynamic> header = data['header'] is Map ? data['header'] as Map : const {};
    // Negative: the site refused (key, limits). Positive: a server-side
    // partial answer (an index down) that still carries results.
    final int status = int.tryParse(header['status']?.toString() ?? '0') ?? 0;
    if (status < 0) {
      throw Exception('SauceNAO: ${header['message'] ?? 'error $status'}');
    }
    final List<ReverseMatch> out = [];
    for (final dynamic r in (data['results'] as List?) ?? const []) {
      if (r is! Map) continue;
      final Map<dynamic, dynamic> h = r['header'] is Map ? r['header'] as Map : const {};
      final Map<dynamic, dynamic> d = r['data'] is Map ? r['data'] as Map : const {};
      final double similarity = double.tryParse(h['similarity']?.toString() ?? '') ?? 0;
      if (similarity < sauceNaoMinSimilarity) continue;
      String site = 'other';
      String? postId;
      final Map<String, String> alsoOn = {};
      for (final MapEntry<String, String> e in siteIdKeys) {
        final dynamic id = d[e.value];
        if (id == null || id.toString().isEmpty) continue;
        if (postId == null) {
          site = e.key;
          postId = id.toString();
        } else {
          alsoOn[e.key] = id.toString();
        }
      }
      final List<String> tags = [
        ...splitNames(d['characters']?.toString()),
        ...splitNames(d['material']?.toString()),
        ...splitNames(d['creator']?.toString()),
      ];
      final List<String> unique = [];
      for (final String t in tags) {
        if (!unique.contains(t)) unique.add(t);
      }
      out.add(
        ReverseMatch(
          site: site,
          postId: postId,
          similarity: similarity,
          urls: [for (final u in (d['ext_urls'] as List?) ?? const []) u.toString()],
          tags: unique,
          thumbnail: h['thumbnail']?.toString(),
          alsoOn: alsoOn,
        ),
      );
    }
    return out;
  }

  /// e621's own iqdb: a file upload to `/iqdb_queries.json`. The real answer
  /// (post 5000000, 2026-09-18) wraps the post as `post.posts` with a
  /// space-separated `tag_string`; an older shape had `post.tags` by category.
  static Future<List<ReverseMatch>> e621Iqdb({
    required List<int> imageBytes,
    String baseUrl = 'https://e621.net',
    Map<String, String>? headers,
  }) async {
    final FormData form = FormData.fromMap({'search[file]': MultipartFile.fromBytes(imageBytes, filename: 'image.jpg')});
    final Response<dynamic> res = await poster(
      '$baseUrl/iqdb_queries.json',
      data: form,
      headers: {'User-Agent': Tools.browserUserAgent, 'Accept': 'application/json', ...?headers},
      options: Options(responseType: ResponseType.json, validateStatus: (_) => true),
    ).timeout(const Duration(seconds: 30));
    return parseE621Iqdb(res.data);
  }

  static List<ReverseMatch> parseE621Iqdb(dynamic json) {
    dynamic data = json;
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {
        throw const FormatException('e621 answered no JSON.');
      }
    }
    if (data is Map && data['success'] == false) {
      throw Exception('e621: ${data['message'] ?? 'refused'}');
    }
    if (data is! List) return const [];
    final List<ReverseMatch> out = [];
    for (final dynamic r in data) {
      if (r is! Map) continue;
      final double score = double.tryParse(r['score']?.toString() ?? '') ?? 0;
      if (score < e621MinScore) continue;
      final String? postId = r['post_id']?.toString();
      final Map<dynamic, dynamic> post = r['post'] is Map ? r['post'] as Map : const {};
      final Map<dynamic, dynamic> inner = post['posts'] is Map ? post['posts'] as Map : post;
      final Map<dynamic, dynamic> byCategory = inner['tags'] is Map ? inner['tags'] as Map : const {};
      final List<String> tags = [
        for (final String cat in const ['character', 'artist', 'copyright', 'species', 'general'])
          for (final dynamic t in (byCategory[cat] as List?) ?? const []) normaliseTag(t.toString()),
      ];
      for (final String t in (inner['tag_string']?.toString() ?? '').split(' ')) {
        final String n = normaliseTag(t);
        if (n.isNotEmpty && !tags.contains(n)) tags.add(n);
      }
      out.add(ReverseMatch(site: 'e621', postId: postId, similarity: score, tags: tags.where((t) => t.isNotEmpty).toList()));
    }
    return out;
  }

  /// "Sakamata Chloe" -> `sakamata_chloe`.
  static String normaliseTag(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');

  /// A comma-separated list of display names as tags.
  static List<String> splitNames(String? s) {
    if (s == null || s.trim().isEmpty) return const [];
    return [for (final String part in s.split(',')) normaliseTag(part)].where((t) => t.isNotEmpty).toList();
  }
}
