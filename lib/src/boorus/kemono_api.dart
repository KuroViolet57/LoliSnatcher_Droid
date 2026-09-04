import 'dart:convert';

import 'package:dio/dio.dart';

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

  static Map<String, String> headers(Booru? booru) {
    final String? cookie = KemonoSessionHandler.instance.cookieFor(booru);
    return {
      'Accept': 'text/css',
      'User-Agent': Tools.browserUserAgent,
      'Referer': '$site/',
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
    throw KemonoApiException(r.status, describeStatus(r.status, r.raw));
  }

  static String describeStatus(int status, String raw) => switch (status) {
    401 => 'kemono rejected the session — check the username and password in the booru settings',
    403 => 'kemono refused the request (DDoS-Guard); try again in a moment',
    404 => 'kemono has nothing at that address',
    429 => 'kemono is rate-limiting; wait a minute',
    _ => 'kemono answered $status${raw.isEmpty ? '' : ': ${raw.substring(0, raw.length.clamp(0, 120))}'}',
  };

  // ── URLs ─────────────────────────────────────────────────────────────

  static String creatorPath(String service, String id) => '$api/$service/user/$id';

  /// `/posts?q=&o=&tag=&tag=` — `tag` repeats, so the query is built by hand.
  static String postsUrl({String base = '$api/posts', String q = '', int offset = 0, List<String> tags = const []}) {
    final List<String> parts = [];
    if (q.isNotEmpty) parts.add('q=${Uri.encodeQueryComponent(q)}');
    parts.add('o=$offset');
    for (final String t in tags) {
      parts.add('tag=${Uri.encodeQueryComponent(t)}');
    }
    return '$base?${parts.join('&')}';
  }

  static String popularUrl({required String period, required String date, int offset = 0}) =>
      '$api/posts/popular?date=$date&period=$period&o=$offset';

  static String postUrl(String service, String user, String postId) => '$site/$service/user/$user/post/$postId';

  static String thumbUrl(String path) => '$img/thumbnail/data$path';

  static String fileUrl(String path, {String? server}) => '${server ?? site}/data$path';

  static String iconUrl(String service, String id) => '$img/icons/$service/$id';

  static String bannerUrl(String service, String id) => '$img/banners/$service/$id';

  // ── typed helpers ────────────────────────────────────────────────────

  static Future<({String service, String id, String postId})?> randomPost() async {
    final data = await getJson('$api/posts/random');
    if (data is! Map) return null;
    final String service = data['service']?.toString() ?? '';
    final String id = data['artist_id']?.toString() ?? '';
    final String post = data['post_id']?.toString() ?? '';
    if (service.isEmpty || id.isEmpty || post.isEmpty) return null;
    return (service: service, id: id, postId: post);
  }

  static Future<({String service, String id})?> randomArtist() async {
    final data = await getJson('$api/artists/random');
    if (data is! Map) return null;
    final String service = data['service']?.toString() ?? '';
    final String id = data['artist_id']?.toString() ?? '';
    if (service.isEmpty || id.isEmpty) return null;
    return (service: service, id: id);
  }

  static Future<Map<String, dynamic>?> profile(String service, String id, {Booru? booru}) async {
    final data = await getJson('${creatorPath(service, id)}/profile', booru: booru);
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  static Future<Map<String, dynamic>?> postDetail(String service, String user, String postId, {Booru? booru}) async {
    final data = await getJson('${creatorPath(service, user)}/post/$postId', booru: booru);
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  static Future<List> comments(String service, String user, String postId, {Booru? booru}) async {
    final data = await getJson('${creatorPath(service, user)}/post/$postId/comments', booru: booru);
    return data is List ? data : const [];
  }

  static Future<List> creatorTags(String service, String id, {Booru? booru}) async {
    final data = await getJson('${creatorPath(service, id)}/tags', booru: booru);
    return data is List ? data : const [];
  }

  static Future<List> announcements(String service, String id, {Booru? booru}) async {
    final data = await getJson('${creatorPath(service, id)}/announcements', booru: booru);
    return data is List ? data : const [];
  }

  static Future<List> creatorDms(String service, String id, {Booru? booru}) async {
    final data = await getJson('${creatorPath(service, id)}/dms', booru: booru);
    return data is List ? data : const [];
  }

  static Future<({List rows, int count})> dms({int offset = 0, String q = '', Booru? booru}) async {
    final String url = '$api/dms?o=$offset${q.isEmpty ? '' : '&q=${Uri.encodeQueryComponent(q)}'}';
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
    final data = await getJson('$api/artists/updated', booru: booru);
    if (data is Map && data['results'] is List) return data['results'] as List;
    if (data is List) return data;
    return const [];
  }

  /// The signed-in account's favourites; [type] is `post` or `artist`.
  static Future<List> favourites(Booru booru, {required String type}) async {
    final data = await getJson('$api/account/favorites?type=$type', booru: booru);
    return data is List ? data : const [];
  }

  static Future<(bool, String)> setCreatorFavourite(Booru booru, String service, String id, bool value) async {
    try {
      final r = await request(value ? 'POST' : 'DELETE', '$api/favorites/creator/$service/$id', booru: booru);
      if (r.status >= 200 && r.status < 300) {
        return (true, value ? 'Added to your kemono favourites' : 'Removed from your kemono favourites');
      }
      return (false, describeStatus(r.status, r.raw));
    } catch (e) {
      return (false, 'Sync failed: $e');
    }
  }

  static Future<(bool, String)> setPostFavourite(Booru booru, String service, String user, String postId, bool value) async {
    try {
      final r = await request(value ? 'POST' : 'DELETE', '$api/favorites/post/$service/$user/$postId', booru: booru);
      if (r.status >= 200 && r.status < 300) {
        return (true, value ? 'Synced to your kemono account' : 'Removed from your kemono account');
      }
      return (false, describeStatus(r.status, r.raw));
    } catch (e) {
      return (false, 'Sync failed: $e');
    }
  }

  static String _short(String url) => url.replaceFirst(api, '');

  static void _log(String message) => Logger.Inst().log(message, 'KemonoApi', 'request', LogTypes.booruHandlerInfo);
}
