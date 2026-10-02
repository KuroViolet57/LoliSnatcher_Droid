import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/widgets/image/booru_favicon.dart';

/// Round 3, item 8: sites that don't serve a usable favicon.ico (nhentai
/// answers it with a real 404) showed a red error tile everywhere their icon
/// appears. Each host now walks a chain — site icon, then DuckDuckGo's icon
/// service, then a generated letter tile — and the outcome is remembered per
/// host so the fallbacks are probed once, not on every render.
void main() {
  setUp(FaviconResolver.resetForTests);
  tearDown(FaviconResolver.resetForTests);

  const String siteIcon = 'https://nhentai.net/favicon.ico';

  group('candidate chain', () {
    test('an unknown host tries its own icon first, then DuckDuckGo', () {
      expect(FaviconResolver.candidatesFor(siteIcon), [
        siteIcon,
        'https://icons.duckduckgo.com/ip3/nhentai.net.ico',
      ]);
    });

    test('once a candidate works, that host only ever uses it', () {
      // Note the fallback lives on a DIFFERENT host — the memo has to be
      // keyed by the SOURCE's host or every site sharing the DuckDuckGo
      // fallback would collide on one key.
      const String ddg = 'https://icons.duckduckgo.com/ip3/nhentai.net.ico';
      FaviconResolver.rememberWorking(siteIcon, ddg);

      // Every later icon for this host starts at the winner — no re-probing
      // the 404 on each render.
      expect(FaviconResolver.candidatesFor(siteIcon), [ddg]);
      expect(FaviconResolver.usesLetterTile(siteIcon), isFalse);
    });

    test('a host where everything failed goes straight to the letter tile', () {
      FaviconResolver.rememberNone(siteIcon);
      expect(FaviconResolver.candidatesFor(siteIcon), isEmpty);
      expect(FaviconResolver.usesLetterTile(siteIcon), isTrue);
    });

    test('forgetting a host re-probes the whole chain (the manual retry)', () {
      FaviconResolver.rememberNone(siteIcon);
      FaviconResolver.forget(siteIcon);
      expect(FaviconResolver.usesLetterTile(siteIcon), isFalse);
      expect(FaviconResolver.candidatesFor(siteIcon).length, 2);
    });

    test('two sources both falling back to DuckDuckGo keep their own icons', () {
      FaviconResolver.rememberWorking(siteIcon, 'https://icons.duckduckgo.com/ip3/nhentai.net.ico');
      FaviconResolver.rememberWorking(
        'https://gelbooru.com/favicon.ico',
        'https://icons.duckduckgo.com/ip3/gelbooru.com.ico',
      );
      expect(FaviconResolver.candidatesFor(siteIcon), ['https://icons.duckduckgo.com/ip3/nhentai.net.ico']);
      expect(
        FaviconResolver.candidatesFor('https://gelbooru.com/favicon.ico'),
        ['https://icons.duckduckgo.com/ip3/gelbooru.com.ico'],
      );
    });

    test('the memo is per HOST, so other sources are unaffected', () {
      FaviconResolver.rememberNone(siteIcon);
      expect(FaviconResolver.candidatesFor('https://gelbooru.com/favicon.ico'), [
        'https://gelbooru.com/favicon.ico',
        'https://icons.duckduckgo.com/ip3/gelbooru.com.ico',
      ]);
    });

    test('an empty or hostless URL has nothing to try', () {
      expect(FaviconResolver.candidatesFor(''), isEmpty);
      expect(FaviconResolver.candidatesFor('not a url'), isEmpty);
    });

    test('a site whose icon IS the DuckDuckGo URL is not listed twice', () {
      const String ddg = 'https://icons.duckduckgo.com/ip3/icons.duckduckgo.com.ico';
      expect(FaviconResolver.candidatesFor(ddg), [ddg]);
    });
  });

  group('letter tile', () {
    test('uses the source name initial, falling back to the host', () {
      expect(FaviconLetterTile.letterFor('nhentai', 'nhentai.net'), 'N');
      expect(FaviconLetterTile.letterFor(null, 'gelbooru.com'), 'G');
      expect(FaviconLetterTile.letterFor('  ', 'e621.net'), 'E');
      // "www." isn't the site's initial.
      expect(FaviconLetterTile.letterFor(null, 'www.pixiv.net'), 'P');
      expect(FaviconLetterTile.letterFor(null, null), '?');
    });

    test('colour is stable per host and survives rebuilds', () {
      final Color first = FaviconLetterTile.colourFor('nhentai.net');
      expect(FaviconLetterTile.colourFor('nhentai.net'), first);
      // ...and different hosts generally get different colours.
      expect(FaviconLetterTile.colourFor('gelbooru.com'), isNot(equals(first)));
    });

    testWidgets('renders the initial', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FaviconLetterTile(size: 20, label: 'nhentai', host: 'nhentai.net'),
          ),
        ),
      );
      expect(find.text('N'), findsOneWidget);
    });
  });

  group('the letter tile never gives up on a "?"', () {
    test('a source added without a name falls back to its type and address', () {
      // The name field is optional, so leaving it blank is easy — and it used
      // to put a bare "?" on every card in that source's feed.
      expect(FaviconLetterTile.letterFor(null, 'hitomi.la'), 'H');
      expect(FaviconLetterTile.letterFor('', 'asmhentai.com'), 'A');
    });

    test('a name still wins over the address', () {
      expect(FaviconLetterTile.letterFor('Kuro', 'hitomi.la'), 'K');
    });

    test("www is skipped so the letter is the site's own initial", () {
      expect(FaviconLetterTile.letterFor(null, 'www.eahentai.com'), 'E');
    });

    test('"?" is only reached when there is genuinely nothing', () {
      expect(FaviconLetterTile.letterFor(null, null), '?');
      expect(FaviconLetterTile.letterFor('   ', '  '), '?');
    });
  });

  group('a source with no icon URL still reaches DuckDuckGo', () {
    // The device log carried 7 "Failed to load favicon:" lines with a BLANK
    // url. The icon field is optional, and an empty one produced an empty
    // candidate chain — so the fallback step was never reached and every card
    // in that feed dropped to a letter tile.
    setUp(FaviconResolver.resetForTests);

    test('the site host alone is enough to build a candidate', () {
      final candidates = FaviconResolver.candidatesFor('', fallbackHost: 'niyaniya.moe');

      expect(candidates, isNotEmpty, reason: 'gave up before trying DuckDuckGo');
      expect(candidates.single, FaviconResolver.duckDuckGoUrlFor('niyaniya.moe'));
    });

    test('a configured icon still leads, with DuckDuckGo behind it', () {
      final candidates = FaviconResolver.candidatesFor(
        'https://hitomi.la/favicon.ico',
        fallbackHost: 'hitomi.la',
      );

      expect(candidates.first, 'https://hitomi.la/favicon.ico');
      expect(candidates.last, FaviconResolver.duckDuckGoUrlFor('hitomi.la'));
    });

    test('with neither an icon nor a host there is genuinely nothing to try', () {
      expect(FaviconResolver.candidatesFor(''), isEmpty);
      expect(FaviconResolver.candidatesFor('', fallbackHost: ''), isEmpty);
    });

    test('a host already known to have no icon is not retried', () {
      FaviconResolver.rememberNone('https://niyaniya.moe/favicon.ico');
      expect(
        FaviconResolver.candidatesFor('', fallbackHost: 'niyaniya.moe'),
        isEmpty,
      );
    });
  });
}
