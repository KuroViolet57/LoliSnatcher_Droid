import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alice_lightweight/alice.dart';
import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart'
    show HTTPCookieSameSitePolicy, InAppWebViewPlatform, PlatformCookieManager, PlatformCookieManagerCreationParams, PlatformInAppWebViewController, WebUri;
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/logging/logger.dart';
import 'package:lolisnatcher/core/network/dio_network.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/settings/source_settings_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/core/utils/tools.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/sources/booru/agnph_handler.dart';
import 'package:lolisnatcher/sources/booru/civitai_handler.dart';
import 'package:lolisnatcher/sources/booru/ink_bunny_handler.dart';
import 'package:lolisnatcher/sources/tube/redgifs_handler.dart';

/// The WebView cookie jar, as a list of what was written into it.
class _RecordingCookieManager extends PlatformCookieManager {
  _RecordingCookieManager() : super.implementation(const PlatformCookieManagerCreationParams());

  final List<({String name, String value})> written = [];

  @override
  Future<bool> setCookie({
    required WebUri url,
    required String name,
    required String value,
    String path = '/',
    String? domain,
    int? expiresDate,
    int? maxAge,
    bool? isSecure,
    bool? isHttpOnly,
    HTTPCookieSameSitePolicy? sameSite,
    PlatformInAppWebViewController? iosBelow11WebViewController,
    PlatformInAppWebViewController? webViewController,
  }) async {
    written.add((name: name, value: value));
    return true;
  }
}

class _FakeWebViewPlatform extends InAppWebViewPlatform {
  _FakeWebViewPlatform(this.cookies);

  final _RecordingCookieManager cookies;

  @override
  PlatformCookieManager createPlatformCookieManager(PlatformCookieManagerCreationParams params) => cookies;
}

/// m2 (1.0): source bugs that only show over a real connection. Every
/// request goes to a server on this machine's loopback address that answers
/// like the site would; nothing leaves the PC.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final _RecordingCookieManager jar = _RecordingCookieManager();
  InAppWebViewPlatform.instance = _FakeWebViewPlatform(jar);
  // The test binding answers every request with a 400 of its own; these tests
  // need the real client, talking only to the server below.
  HttpOverrides.global = null;

  late HttpServer server;
  late String base;
  late Directory tempDir;
  final Map<String, Future<void> Function(HttpRequest request)> routes = {};
  final List<Uri> seen = [];

  Future<void> answer(HttpRequest request, Object body, {ContentType? type}) async {
    request.response.headers.contentType = type ?? ContentType.json;
    request.response.write(body is String ? body : jsonEncode(body));
    await request.response.close();
  }

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((HttpRequest request) async {
      seen.add(request.uri);
      for (final MapEntry<String, Future<void> Function(HttpRequest)> route in routes.entries) {
        if (request.uri.path.startsWith(route.key)) {
          await route.value(request);
          return;
        }
      }
      request.response.statusCode = 404;
      await request.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    TagHandler.register();
    tempDir = Directory.systemTemp.createTempSync('source_local_server_test');
    SettingsHandler.instance
      ..path = '${tempDir.path}${Platform.pathSeparator}'
      ..alice = Alice();
    SourceSettingsHandler.instance.resetForTests();
    Logger.Inst();
    // No WebView jar on a test host.
    Tools.cookieJarReaderOverride = (String uri) async => const {};
    routes.clear();
    seen.clear();
  });

  tearDown(() {
    Tools.resetCookieJarForTests();
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test("InkBunny: a signed-in session's id never reaches the log", () async {
    const String sid = 'SIDVALUE0123456789abc';
    routes['/api_login.php'] = (r) => answer(r, {'sid': sid, 'user_id': '0', 'ratingsmask': '11100'});
    routes['/api_userrating.php'] = (r) => answer(r, {'sid': sid});
    routes['/api_search.php'] = (r) => answer(r, {
      'sid': sid,
      'results_count_all': '1',
      'pages_count': 1,
      'submissions': [
        {'submission_id': '10'},
      ],
    });
    routes['/api_submissions.php'] = (r) => answer(r, {
      'sid': sid,
      'submissions': [
        {
          'submission_id': '10',
          'username': 'someartist',
          'keywords': [
            {'keyword_name': 'red fox'},
          ],
          'pools': [],
          'files': [
            {
              'file_url_screen': 'https://media.invalid/s.png',
              'file_url_preview': 'https://media.invalid/p.png',
              'file_url_full': 'https://media.invalid/f.png',
              'full_size_x': '100',
              'full_size_y': '100',
              'screen_size_x': '50',
              'screen_size_y': '50',
              'preview_size_x': '10',
              'preview_size_y': '10',
              'full_file_md5': 'abc',
            },
          ],
          'favorites_count': '3',
          'create_datetime': '2026-01-01 10:00:00.123+00',
          'rating_name': 'General',
        },
      ],
    });
    final Booru inkbunny = Booru('InkBunny', BooruType.InkBunny, '', base, '');
    final int before = Logger.talker.history.length;

    await InkBunnyHandler(inkbunny, 20).search('fox', null);

    expect(seen.any((u) => u.queryParameters['sid'] == sid), isTrue, reason: 'the session was used');
    final String logged = [for (final e in Logger.talker.history.skip(before)) e.generateTextMessage()].join('\n');
    expect(logged, contains('api_search.php'), reason: 'the requests are still logged');
    expect(logged, isNot(contains(sid)));
  });

  test('AGNPH: the tags fetched later land on their own post when a post before them was skipped', () async {
    String post(String id, {bool withFile = true}) =>
        '<post><id>$id</id>${withFile ? '<file_url>https://media.invalid/$id.png</file_url>' : ''}'
        '<preview_url>https://media.invalid/$id-s.png</preview_url><thumbnail_url>https://media.invalid/$id-t.png</thumbnail_url>'
        '<width>10</width><height>10</height><rating>s</rating><fav_count>1</fav_count><source></source>'
        '<md5>m$id</md5><created_at>1600000000</created_at></post>';
    routes['/gallery/post/show/'] = (r) {
      final String id = r.uri.pathSegments.where((s) => s.isNotEmpty).last;
      return answer(r, '<post><tags>tag_$id</tags><artist>artist$id</artist></post>', type: ContentType('text', 'xml'));
    };
    routes['/gallery/post/'] = (r) => answer(
      r,
      '<posts count="3">${post('1', withFile: false)}${post('2')}${post('3')}</posts>',
      type: ContentType('text', 'xml'),
    );
    final AGNPHHandler h = AGNPHHandler(Booru('AGNPH', BooruType.AGNPH, '', base, ''), 20);

    await h.search('sylveon', null);

    expect(h.fetched.map((i) => i.serverId), ['2', '3']);
    final BooruItem two = h.fetched[0];
    final BooruItem three = h.fetched[1];
    final DateTime until = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(until) && (two.tagsList.isEmpty || three.tagsList.isEmpty)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(two.tagsList.map((t) => t.fullString), contains('tag_2'));
    expect(three.tagsList.map((t) => t.fullString), contains('tag_3'));
    expect(three.tagsList.map((t) => t.fullString), isNot(contains('tag_2')));
  });

  test('AGNPH: the blacklist judges a post again once its tags arrive', () async {
    String post(String id) =>
        '<post><id>$id</id><file_url>https://media.invalid/$id.png</file_url>'
        '<preview_url>https://media.invalid/$id-s.png</preview_url><thumbnail_url>https://media.invalid/$id-t.png</thumbnail_url>'
        '<width>10</width><height>10</height><rating>s</rating><fav_count>1</fav_count><source></source>'
        '<md5>m$id</md5><created_at>1600000000</created_at></post>';
    // The tags answer only after the page is on screen, as on a slow line.
    final Completer<void> release = Completer<void>();
    routes['/gallery/post/show/'] = (r) async {
      await release.future;
      final String id = r.uri.pathSegments.where((s) => s.isNotEmpty).last;
      await answer(r, '<post><tags>tag_$id</tags><artist>artist$id</artist></post>', type: ContentType('text', 'xml'));
    };
    routes['/gallery/post/'] = (r) => answer(r, '<posts count="2">${post('2')}${post('3')}</posts>', type: ContentType('text', 'xml'));
    final SettingsHandler settings = SettingsHandler.instance;
    final bool filterHated = settings.filterHated;
    settings
      ..filterHated = true
      ..hiddenTags.add('tag_3')
      ..invalidateBlacklistCache();
    addTearDown(() {
      settings
        ..filterHated = filterHated
        ..hiddenTags.remove('tag_3')
        ..invalidateBlacklistCache();
    });
    final AGNPHHandler h = AGNPHHandler(Booru('AGNPH', BooruType.AGNPH, '', base, ''), 20);

    await h.search('sylveon', null);

    expect(h.filteredFetched.map((i) => i.serverId), ['2', '3'], reason: 'no tags yet, nothing to judge');
    release.complete();
    final BooruItem two = h.fetched[0];
    final BooruItem three = h.fetched[1];
    final DateTime until = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(until) && (two.tagsList.isEmpty || three.tagsList.isEmpty)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(h.filteredFetched.map((i) => i.serverId), ['2']);
  });

  test('RedGifs: a user token the API rejects is set aside for the session, not wiped from the source', () async {
    String jwt(DateTime exp) {
      final String payload = base64Url.encode(utf8.encode(jsonEncode({'exp': exp.millisecondsSinceEpoch ~/ 1000}))).replaceAll('=', '');
      return 'eyJhbGciOiJIUzI1NiJ9.$payload.c2lnbmF0dXJl';
    }

    final String token = jwt(DateTime.now().add(const Duration(days: 1)));
    final List<String?> auth = [];
    routes['/v2/gifs/search'] = (r) async {
      auth.add(r.headers.value('authorization'));
      r.response.statusCode = HttpStatus.unauthorized;
      await r.response.close();
    };
    // The fresh guest token comes from api.redgifs.com: that request is sent
    // to this server as a proxy, which refuses the tunnel. Nothing leaves.
    final HttpClient client = DioNetwork.sharedHttpClient;
    client.findProxy = (Uri uri) => uri.host == 'api.redgifs.com' ? 'PROXY 127.0.0.1:${server.port}' : 'DIRECT';
    addTearDown(() => client.findProxy = HttpClient.findProxyFromEnvironment);
    final Booru redgifs = Booru.withKey('RedGifs', BooruType.RedGifs, '', base, '', token, '');
    final RedGifsHandler h = RedGifsHandler(redgifs, 20);
    expect(await h.isSignedIn(), isTrue);

    await expectLater(h.fetchSearch(Uri.parse('$base/v2/gifs/search?search_text=cat'), 'cat'), throwsA(isA<DioException>()));

    expect(auth, ['Bearer $token']);
    expect(redgifs.apiKey, token, reason: 'a backup or a save of the source must not write an empty key');
    expect(await h.isSignedIn(), isFalse, reason: 'this session goes on as a guest');
  });

  test('Civitai: a page whose every item a -tag excludes does not end the feed', () async {
    Map<String, dynamic> image(int id, String tag) => {
      'id': id,
      'url': 'https://image.invalid/key/uuid-$id/original=true/$id.jpeg',
      'type': 'image',
      'width': 10,
      'height': 10,
      'tags': [
        {'name': tag, 'id': id},
      ],
      'username': 'someone',
      'stats': {'likeCount': 1},
    };
    routes['/api/v1/images'] = (r) {
      final String cursor = r.uri.queryParameters['cursor'] ?? '';
      return switch (cursor) {
        '' => answer(r, {
          'items': [image(1, 'skip me'), image(2, 'skip me')],
          'metadata': {'nextCursor': 'c2'},
        }),
        'c2' => answer(r, {
          'items': [image(3, 'keep'), image(4, 'keep')],
          'metadata': {'nextCursor': 'c3'},
        }),
        _ => answer(r, {
          'items': [image(5, 'keep')],
          'metadata': {'nextCursor': ''},
        }),
      };
    };
    final CivitaiHandler h = CivitaiHandler(Booru('Civitai', BooruType.Civitai, '', base, ''), 20);
    // SearchHandler.runSearch counts the first page up from the factory's -1.
    h.pageNum = 0;

    await h.search('-skip_me', null);

    expect(h.fetched.map((i) => i.serverId), ['3', '4']);
    expect(h.locked, isFalse);
  });
}
