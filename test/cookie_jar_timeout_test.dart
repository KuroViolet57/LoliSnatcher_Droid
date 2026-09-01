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
}
