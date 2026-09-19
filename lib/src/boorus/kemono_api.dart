import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/boorus/kemono_site.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/kemono_session_handler.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// Thrown when the API answers something other than success.
class KemonoApiException implements Exception {
  const KemonoApiException(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => message;
}

/// The one place that knows how to talk to kemono's API: the `Accept:
/// text/css` header every call needs (DDoS-Guard answers 403 to a browser
/// Accept; verified 2026-09-04), the session cookie, and the single
/// automatic re-login when a signed-in call answers 401. The handler, the
/// sidebar pages, the creator index and the site profile all go through here.
class KemonoApi {
  KemonoApi._();

  static const String site = 'https://kemono.cr';
  static const String api = '$site/api/v1';
  static const String img = 'https://img.kemono.cr';

  static const Duration timeout = Duration(seconds: 25);

  static Map<String, String> headers(Booru? booru) => headersFor(KemonoSite.of(booru), booru: booru);

  static Map<String, String> headersFor(KemonoSite s, {Booru? booru}) {
    final String? cookie = KemonoSessionHandler.instance.cookieFor(booru);
    return {
      'Accept': s.acceptHeader,
      'User-Agent': Tools.browserUserAgent,
      'Referer': '${s.site}/',
      'Cookie': ?cookie,
    };
  }

  static dynamic decode(dynamic data) {
    if (data == null) return null;
    if (data is String) {
      final String text = data.trim();
      if (text.isEmpty) return null;
      try {
        return jsonDecode(text);
      } catch (_) {
        return null;
      }
    }
    return data;
  }

  /// One request with the site's headers. On 401 with a configured login,
  /// one re-login and one retry; the result is whatever came back last.
  static Future<({int status, dynamic data, String raw})> request(
    String method,
    String url, {
    Booru? booru,
    Object? body,
    bool retried = false,
  }) async {
    final Options options = Options(
      validateStatus: (_) => true,
      responseType: ResponseType.plain,
      receiveTimeout: timeout,
      sendTimeout: timeout,
    );
    final Map<String, String> h = {
      ...headers(booru),
      if (body != null) 'Content-Type': 'application/json',
    };
    final Response response = switch (method) {
      'POST' => await DioNetwork.post(url, data: body == null ? null : jsonEncode(body), headers: h, options: options),
      'DELETE' => await DioNetwork.delete(url, data: body == null ? null : jsonEncode(body), headers: h, options: options),
      _ => await DioNetwork.get(url, headers: h, options: options),
    };
    final int status = response.statusCode ?? -1;
    final String raw = response.data?.toString() ?? '';
    if (status == 401 && !retried && booru != null && KemonoSessionHandler.hasCredentials(booru)) {
      _log('401 on $method ${_short(url)}; trying one re-login');
      if (await KemonoSessionHandler.instance.relogin(booru)) {
        return request(method, url, booru: booru, body: body, retried: true);
      }
    }
    return (status: status, data: decode(raw), raw: raw);
  }

  /// A decoded JSON body, or a [KemonoApiException] naming the refusal.
  static Future<dynamic> getJson(String url, {Booru? booru}) async {
    final r = await request('GET', url, booru: booru);
    if (r.status >= 200 && r.status < 300) return r.data;
    throw KemonoApiException(r.status, describeStatus(r.status, r.raw, site: KemonoSite.of(booru)));
  }

  static String describeStatus(int status, String raw, {KemonoSite site = KemonoSite.kemono}) {
    final String n = site.name;
    return switch (status) {
      401 => '$n rejected the session — check the username and password in the booru settings',
      403 => site.isKemono ? '$n refused the request (DDoS-Guard); try again in a moment' : '$n refused the request; try again in a moment',
      404 => '$n has nothing at that address',
      429 => '$n is rate-limiting; wait a minute',
      _ => '$n answered $status${raw.isEmpty ? '' : ': ${raw.substring(0, raw.length.clamp(0, 120))}'}',
    };
  }

  // ── URLs (kemono's; a handler asks its [KemonoSite] instead) ─────────

  static String creatorPath(String service, String id) => KemonoSite.kemono.creatorPath(service, id);

  static String postsUrl({String base = '$api/posts', String q = '', int offset = 0, List<String> tags = const []}) =>
      KemonoSite.kemono.postsUrl(base: base, q: q, offset: offset, tags: tags);

  static String popularUrl({required String period, required String date, int offset = 0}) =>
      KemonoSite.kemono.popularUrl(period: period, date: date, offset: offset);

  static String postUrl(String service, String user, String postId) => KemonoSite.kemono.postUrl(service, user, postId);

  static String thumbUrl(String path) => KemonoSite.kemono.thumbUrl(path);

  static String iconUrl(String service, String id) => KemonoSite.kemono.iconUrl(service, id);

  static String bannerUrl(String service, String id) => KemonoSite.kemono.bannerUrl(service, id);

  /// The file hosts and their share of the paths, as the site's bundle
  /// (`/assets/index-szizO2gj.js`, read 2026-09-04) lists them. The site never
  /// asks `kemono.cr/data` for a file — that host is DDoS-Guard and answers a
  /// redirect — it picks the host itself from a murmur2 hash of `/data{path}`,
  /// and the API names the same host in a post detail's `server`. A share of 0
  /// is the catch-all and must stay last.
  static const List<({String host, int percent})> fileServers = [
    (host: 'https://n1.kemono.cr', percent: 25),
    (host: 'https://n2.kemono.cr', percent: 25),
    (host: 'https://n3.kemono.cr', percent: 25),
    (host: 'https://n4.kemono.cr', percent: 0),
  ];

  static const int _hashMax = 4294967295;
  static const int _mask = 0xffffffff;

  /// murmurhash-js `murmurhash2_32_gc`: 32-bit MurmurHash2 over the low byte
  /// of each code unit (the paths are ASCII), everything modulo 2^32.
  static int murmur2(String s, [int seed = 0]) {
    const int m = 0x5bd1e995;
    final List<int> b = s.codeUnits;
    int l = b.length;
    int h = (seed ^ l) & _mask;
    int i = 0;
    while (l >= 4) {
      int k = (b[i] & 0xff) | ((b[i + 1] & 0xff) << 8) | ((b[i + 2] & 0xff) << 16) | ((b[i + 3] & 0xff) << 24);
      k = (k * m) & _mask;
      k ^= k >>> 24;
      k = (k * m) & _mask;
      h = ((h * m) & _mask) ^ k;
      l -= 4;
      i += 4;
    }
    if (l == 3) h ^= (b[i + 2] & 0xff) << 16;
    if (l >= 2) h ^= (b[i + 1] & 0xff) << 8;
    if (l >= 1) {
      h ^= b[i] & 0xff;
      h = (h * m) & _mask;
    }
    h ^= h >>> 13;
    h = (h * m) & _mask;
    h ^= h >>> 15;
    return h & _mask;
  }

  /// The host the site itself would fetch `path` from.
  static String fileServer(String path) {
    final int h = murmur2('/data$path');
    int acc = 0;
    for (final s in fileServers) {
      if (s.percent == 0) return s.host;
      acc += (s.percent * _hashMax) ~/ 100;
      if (h < acc) return s.host;
    }
    return fileServers.last.host;
  }

  /// A file's URL on kemono's hosts: the one the detail names when there is
  /// one, else the one the hash picks. Never `kemono.cr/data`.
  static String fileUrl(String path, {String? server}) => KemonoSite.kemono.fileUrl(path, server: server);

  // ── typed helpers ────────────────────────────────────────────────────

  static Future<({String service, String id, String postId})?> randomPost({Booru? booru}) async {
    final data = await getJson('${KemonoSite.of(booru).api}/posts/random', booru: booru);
    if (data is! Map) return null;
    final String service = data['service']?.toString() ?? '';
    final String id = data['artist_id']?.toString() ?? '';
    final String post = data['post_id']?.toString() ?? '';
    if (service.isEmpty || id.isEmpty || post.isEmpty) return null;
    return (service: service, id: id, postId: post);
  }

  static Future<({String service, String id})?> randomArtist({Booru? booru}) async {
    final data = await getJson('${KemonoSite.of(booru).api}/artists/random', booru: booru);
    if (data is! Map) return null;
    final String service = data['service']?.toString() ?? '';
    final String id = data['artist_id']?.toString() ?? '';
    if (service.isEmpty || id.isEmpty) return null;
    return (service: service, id: id);
  }

  static Future<Map<String, dynamic>?> profile(String service, String id, {Booru? booru}) async {
    final data = await getJson('${KemonoSite.of(booru).creatorPath(service, id)}/profile', booru: booru);
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  static const Duration detailCacheFor = Duration(minutes: 10);
  static const int detailCacheSize = 50;
  static final Map<String, (Map<String, dynamic>, DateTime)> _detailCache = {};

  /// The post detail, shared by the viewer's item refresh, the files overlay
  /// and the post page — one fetch per post per ten minutes.
  static Future<Map<String, dynamic>?> postDetail(String service, String user, String postId, {Booru? booru}) async {
    final String url = '${KemonoSite.of(booru).creatorPath(service, user)}/post/$postId';
    final cached = _detailCache[url];
    if (cached != null && DateTime.now().difference(cached.$2) < detailCacheFor) return cached.$1;
    final data = await getJson(url, booru: booru);
    if (data is! Map) return null;
    final Map<String, dynamic> detail = Map<String, dynamic>.from(data);
    if (_detailCache.length >= detailCacheSize) _detailCache.remove(_detailCache.keys.first);
    _detailCache[url] = (detail, DateTime.now());
    return detail;
  }

  @visibleForTesting
  static void clearDetailCache() => _detailCache.clear();

  /// pawchive answers 404 `{"error":"Not found"}` for a post with no comments.
  static Future<List> comments(String service, String user, String postId, {Booru? booru}) async {
    try {
      final data = await getJson('${KemonoSite.of(booru).creatorPath(service, user)}/post/$postId/comments', booru: booru);
      return data is List ? data : const [];
    } on KemonoApiException catch (e) {
      if (e.status == 404) return const [];
      rethrow;
    }
  }

  static Future<List> creatorTags(String service, String id, {Booru? booru}) async {
    final data = await getJson('${KemonoSite.of(booru).creatorPath(service, id)}/tags', booru: booru);
    return data is List ? data : const [];
  }

  static Future<List> announcements(String service, String id, {Booru? booru}) async {
    final data = await getJson('${KemonoSite.of(booru).creatorPath(service, id)}/announcements', booru: booru);
    return data is List ? data : const [];
  }

  static Future<List> creatorDms(String service, String id, {Booru? booru}) async {
    final data = await getJson('${KemonoSite.of(booru).creatorPath(service, id)}/dms', booru: booru);
    return data is List ? data : const [];
  }

  static Future<({List rows, int count})> dms({int offset = 0, String q = '', Booru? booru}) async {
    final String url = '${KemonoSite.of(booru).api}/dms?o=$offset${q.isEmpty ? '' : '&q=${Uri.encodeQueryComponent(q)}'}';
    final data = await getJson(url, booru: booru);
    if (data is Map) {
      final props = data['props'];
      final List rows = (props is Map ? props['dms'] : data['dms']) as List? ?? const [];
      final int count = int.tryParse((props is Map ? props['count'] : data['count'])?.toString() ?? '') ?? rows.length;
      return (rows: rows, count: count);
    }
    if (data is List) return (rows: data, count: data.length);
    return (rows: const [], count: 0);
  }

  static Future<List> updatedArtists({Booru? booru}) async {
    final data = await getJson('${KemonoSite.of(booru).api}/artists/updated', booru: booru);
    if (data is Map && data['results'] is List) return data['results'] as List;
    if (data is List) return data;
    return const [];
  }

  /// The signed-in account's favourites; [type] is `post` or `artist`.
  static Future<List> favourites(Booru booru, {required String type}) async {
    final data = await getJson('${KemonoSite.of(booru).api}/account/favorites?type=$type', booru: booru);
    return data is List ? data : const [];
  }

  static Future<(bool, String)> setCreatorFavourite(Booru booru, String service, String id, bool value) async {
    try {
      final KemonoSite s = KemonoSite.of(booru);
      final r = await request(value ? 'POST' : 'DELETE', '${s.api}/favorites/creator/$service/$id', booru: booru);
      if (r.status >= 200 && r.status < 300) {
        return (true, value ? 'Added to your ${s.name} favourites' : 'Removed from your ${s.name} favourites');
      }
      return (false, describeStatus(r.status, r.raw, site: s));
    } catch (e) {
      return (false, 'Sync failed: $e');
    }
  }

  static Future<(bool, String)> setPostFavourite(Booru booru, String service, String user, String postId, bool value) async {
    try {
      final KemonoSite s = KemonoSite.of(booru);
      final r = await request(value ? 'POST' : 'DELETE', '${s.api}/favorites/post/$service/$user/$postId', booru: booru);
      if (r.status >= 200 && r.status < 300) {
        return (true, value ? 'Synced to your ${s.name} account' : 'Removed from your ${s.name} account');
      }
      return (false, describeStatus(r.status, r.raw, site: s));
    } catch (e) {
      return (false, 'Sync failed: $e');
    }
  }

  static String _short(String url) => url.replaceFirst(RegExp('^https://[^/]+/api/v1'), '');

  static void _log(String message) => Logger.Inst().log(message, 'KemonoApi', 'request', LogTypes.booruHandlerInfo);
}
