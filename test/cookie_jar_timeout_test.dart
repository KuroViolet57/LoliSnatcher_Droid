import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/utils/tools.dart';

/// The reported symptom: after the app sat in the background, every AIBooru
/// request hung forever — posts, tag previews, and every newly opened tab —
/// with no error and no timeout, while an already-cached video still played.
///
/// The shared log has no hung HTTP entry for it, and that is the clue rather
/// than a gap: the stall happens BEFORE a request is issued. Dio's onRequest
/// interceptor awaits Tools.getCookies on every single request, which crosses
/// a platform channel into the Android WebView's CookieManager. That call had
/// a try/catch but no timeout, so a channel that never answers — which is what
/// a WebView reaped in the background gives you — means handler.next(options)
/// is never reached and the request is never made.
///
/// FALSIFIER: an unbounded await anywhere on the request path. A request that
/// goes out without cookies can fail and be retried; a request that is never
/// made cannot do anything at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the cookie jar cannot wedge a request', () {
    test('the read is bounded', () {
      expect(Tools.cookieJarTimeout, greaterThan(Duration.zero));
    });

    test('the bound is short enough to be a timeout, not a hang', () {
      // Long enough for a healthy jar on a cold start, short enough that a
      // dead channel costs one slow request rather than the session.
      expect(Tools.cookieJarTimeout, lessThanOrEqualTo(const Duration(seconds: 10)));
      expect(Tools.cookieJarTimeout, greaterThanOrEqualTo(const Duration(seconds: 2)));
    });

    test('a timed-out read yields no cookies rather than throwing', () async {
      // On this platform there is no webview, which exercises the same exit:
      // the caller gets a string and proceeds.
      final String cookies = await Tools.getCookies('https://aibooru.online/posts.json');
      expect(cookies, isA<String>());
    });
  });

  /// r39, from the log of 2026-09-15 03:10: after the app sat in the
  /// background the jar never answered, and every request — thumbnails,
  /// favicons, pages — waited out the full timeout: 6,848 of them in 38 s,
  /// 2,832 in one second. A jar that stopped answering is asked once, then
  /// left alone for a while.
  group('a cookie jar that stopped answering', () {
    tearDown(Tools.resetCookieJarForTests);

    test('concurrent reads share one call; a timeout pauses the jar; after the pause it is asked again', () async {
      int calls = 0;
      final Completer<Map<String, String>> never = Completer();
      Tools.cookieJarTimeoutOverride = const Duration(milliseconds: 50);
      Tools.cookieJarPauseOverride = const Duration(milliseconds: 300);
      Tools.cookieJarReaderOverride = (String uri) {
        calls++;
        return never.future;
      };
      final Stopwatch first = Stopwatch()..start();
      final List<String> out = await Future.wait([for (int i = 0; i < 25; i++) Tools.getCookies('https://example.org/thumb/$i.jpg')]);
      expect(out.every((c) => c.isEmpty), isTrue);
      expect(calls, 1, reason: 'one call into the jar for 25 requests to one host');
      expect(first.elapsedMilliseconds, lessThan(1000));
      expect(Tools.cookieJarPaused, isTrue);
      final Stopwatch paused = Stopwatch()..start();
      expect(await Tools.getCookies('https://example.org/other'), '');
      expect(await Tools.saveCookies('https://example.org/', ['a=1; path=/']), isTrue);
      expect(paused.elapsedMilliseconds, lessThan(40), reason: 'paused: no wait at all');
      expect(calls, 1);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      Tools.cookieJarReaderOverride = (String uri) async {
        calls++;
        return {'a': '1'};
      };
      expect(await Tools.getCookies('https://example.org/x'), contains('a=1'));
      expect(calls, 2);
      expect(Tools.cookieJarPaused, isFalse);
    });
  });
}
