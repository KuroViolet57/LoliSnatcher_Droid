import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/schale_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/widgets/image/custom_network_image.dart';

/// r89 (phone log 2026-10-03): an e621 thumbnail failed 9 times in a row
/// although its preview address was fine. Since a15067f0 (2026-08-30) the
/// thumbnail passed `item.sources` as spare addresses - meant for
/// niyaniya/HDoujin, which publish a second image server there - but on every
/// other source `sources` are the artist's links. This post's third one is
/// e621's dead-link marker "-http://…", which is not an address: parsing it
/// threw before the real preview was even asked for.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('thumbnail_fallbacks');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    BooruHandlerFactory.clearMediaHeaderCache();
  });

  tearDown(() {
    BooruHandlerFactory.clearMediaHeaderCache();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Booru booru(BooruType type, String url) => Booru(type.name, type, '', url, '');

  BooruItem item(List<String> sources) => BooruItem(
    fileURL: 'https://static1.e621.net/data/6f/14/6f1441fe2e2c7e53fd6d09435fe0b2fb.gif',
    sampleURL: 'https://static1.e621.net/data/sample/6f/14/6f1441fe2e2c7e53fd6d09435fe0b2fb.jpg',
    thumbnailURL: 'https://static1.e621.net/data/preview/6f/14/6f1441fe2e2c7e53fd6d09435fe0b2fb.jpg',
    tagsList: const [],
    postURL: 'https://e621.net/posts/6732377',
  )..sources = sources;

  // e621 post 6732377 (md5 6f1441fe…), its `sources` as e621's API returned
  // them on 2026-10-03; the third is the dead-link marker.
  const List<String> e621Sources = [
    'https://64.media.tumblr.com/063d6f4f91fe65f354cbc41f99e92c9a/tumblr_oq0nlk57iv1uil8vgo1_1280.gif',
    'https://web.archive.org/web/20170521042627/http://twinkietwinks.tumblr.com/post/160710622867/finished-that-thing-for-commission-info-pm-me-or',
    '-http://twinkietwinks.tumblr.com/post/160710622867/finished-that-thing-for-commission-info-pm-me-or',
  ];

  test("a booru post's source links are never tried as its thumbnail", () {
    expect(BooruHandlerFactory.thumbnailFallbacksFor(booru(BooruType.e621, 'https://e621.net'), item(e621Sources)), isEmpty);
  });

  test('niyaniya and HDoujin keep their spare image server; what is not a web address is left out', () {
    for (final (BooruType type, String url) in [(BooruType.NiyaNiya, 'https://niyaniya.moe'), (BooruType.HDoujin, 'https://hdoujin.org')]) {
      expect(
        BooruHandlerFactory.thumbnailFallbacksFor(booru(type, url), item(['https://spare.example/t/1.webp', '-http://dead.example/x'])),
        ['https://spare.example/t/1.webp'],
        reason: type.name,
      );
    }
  });

  test('every source type has decided: only the two that publish a spare server pass one', () {
    final Set<BooruType> spares = {BooruType.NiyaNiya, BooruType.HDoujin};
    for (final BooruType type in BooruType.values) {
      final List<String> got = BooruHandlerFactory.thumbnailFallbacksFor(
        booru(type, 'https://${type.name.toLowerCase()}.example'),
        item(['https://spare.example/t/1.webp']),
      );
      expect(got, spares.contains(type) ? ['https://spare.example/t/1.webp'] : isEmpty, reason: type.name);
    }
  });

  test('review: a niyaniya/HDoujin post keeps its spare wherever it is shown - lists, merged tabs, the doujin For You', () {
    // Schale posts carry the resolved site (a mirror such as shupogaki.moe),
    // not always the configured one.
    SettingsHandler.instance.booruList.add(Booru('hd', BooruType.HDoujin, '', 'https://hdoujin.example', ''));
    addTearDown(SettingsHandler.instance.booruList.clear);
    final List<String> spare = ['https://spare.example/t/1.webp'];
    BooruItem schale(String postURL) => item(spare)..postURL = postURL;
    for (final BooruType host in [BooruType.ForYouDoujin, BooruType.Merge, BooruType.Favourites, BooruType.Downloads]) {
      final Booru feed = booru(host, '');
      expect(BooruHandlerFactory.thumbnailFallbacksFor(feed, schale('https://shupogaki.moe/g/1/k')), spare, reason: '${host.name}: mirror');
      expect(BooruHandlerFactory.thumbnailFallbacksFor(feed, schale('https://niyaniya.moe/g/1/k')), spare, reason: '${host.name}: niyaniya');
      expect(BooruHandlerFactory.thumbnailFallbacksFor(feed, schale('https://hdoujin.example/g/1/k')), spare, reason: '${host.name}: a configured HDoujin site');
      expect(BooruHandlerFactory.thumbnailFallbacksFor(feed, item(e621Sources)), isEmpty, reason: '${host.name}: a booru post');
      expect(BooruHandlerFactory.thumbnailFallbacksFor(feed, schale('https://niyaniya.moe.evil.example/g/1/k')), isEmpty, reason: 'a lookalike host');
    }
  });

  test("recheck: the site's own redirect target and its subdomains count too", () {
    addTearDown(SchaleHandler.forgetResolvedDomainsForTests);
    SchaleHandler.rememberResolvedDomainForTests('https://niyaniya.moe', 'https://next-mirror.example');
    expect(SchaleHandler.ownsPost('https://next-mirror.example/g/1/k'), isTrue, reason: 'a mirror the site redirected to');
    expect(SchaleHandler.ownsPost('https://www.hdoujin.org/g/1/k'), isTrue);
    expect(SchaleHandler.ownsPost('https://cdn.shupogaki.moe/g/1/k'), isTrue);
    expect(SchaleHandler.ownsPost('https://evilhdoujin.org/g/1/k'), isFalse, reason: 'a lookalike, not a subdomain');
    expect(SchaleHandler.ownsPost('https://e621.net/posts/1'), isFalse);
  });

  group('the loader skips a spare it cannot use instead of failing the thumbnail', () {
    final Uri primary = Uri.parse('https://static1.e621.net/data/preview/6f/14/6f1441fe2e2c7e53fd6d09435fe0b2fb.jpg');

    test("e621's real sources: only the web addresses, and never a parse error", () {
      expect(
        thumbnailCandidates(primary, primary.toString(), e621Sources),
        [primary, Uri.parse(e621Sources[0]), Uri.parse(e621Sources[1])],
      );
    });

    test('free text, other schemes, empty and the primary itself are left out', () {
      expect(
        thumbnailCandidates(primary, primary.toString(), ['', "Artist's FA: someone",'javascript:alert(1)', 'ftp://x.example/a.jpg', primary.toString(), 'HTTPS://Spare.Example/A.JPG']),
        [primary, Uri.parse('HTTPS://Spare.Example/A.JPG')],
      );
    });
  });
}
