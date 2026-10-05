import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/sources/booru/pools/pool_source.dart';

/// Live check 2026-10-05, User-Agent LoliSnatcher_Droid/1.0.0:
/// e621.net and e6ai.net /pools.json return pools, and pool:<id> is not
/// post_ids order. danbooru.donmai.us /pools.json returns pools with that
/// UA; a browser UA was 403. ordpool:<id> matched post_ids; pool:<id> did not.
/// e926.net was 403 for both UAs, so it stays off the allowlist.
void main() {
  Booru site(BooruType type, String url) => Booru(type.name, type, '', url, '');

  test('e621, e6ai and danbooru.donmai.us have pools; lookalikes and e926 do not', () {
    expect(PoolSource.forBooru(site(BooruType.e621, 'https://e621.net')), isA<E621PoolSource>());
    expect(PoolSource.forBooru(site(BooruType.e621, 'https://www.e621.net/posts')), isA<E621PoolSource>());
    expect(PoolSource.forBooru(site(BooruType.e621, 'https://e6ai.net')), isA<E621PoolSource>());
    expect(PoolSource.forBooru(site(BooruType.Danbooru, 'https://danbooru.donmai.us')), isA<DanbooruPoolSource>());
    expect(PoolSource.forBooru(site(BooruType.Danbooru, 'https://www.danbooru.donmai.us')), isA<DanbooruPoolSource>());

    expect(PoolSource.forBooru(site(BooruType.e621, 'https://e926.net')), isNull);
    expect(PoolSource.forBooru(site(BooruType.e621, 'https://e621.net.evil')), isNull);
    expect(PoolSource.forBooru(site(BooruType.Danbooru, 'https://danbooru.donmai.us.evil')), isNull);
    expect(PoolSource.forBooru(site(BooruType.Gelbooru, 'https://gelbooru.com')), isNull);
    expect(
      PoolSource.forBooru(site(BooruType.Gelbooru, 'https://rule34.xxx')),
      isA<GelbooruHtmlPoolSource>(),
    );
  });

  test('e621 reorders by id, danbooru asks the server for pool order', () {
    expect(const E621PoolSource().postsQuery('59614'), 'pool:59614');
    expect(const E621PoolSource().queryPreservesOrder, isFalse);
    expect(const DanbooruPoolSource().postsQuery('32085'), 'ordpool:32085');
    expect(const DanbooruPoolSource().queryPreservesOrder, isTrue);
  });

  test('danbooru pool requests use the app user agent, which the site accepted', () {
    final String src = File('lib/sources/booru/pools/pool_source.dart').readAsStringSync();
    final int start = src.indexOf('class DanbooruPoolSource');
    final int end = src.indexOf('class PhilomenaGallerySource');
    expect(start, greaterThan(0));
    expect(end, greaterThan(start));
    final String body = src.substring(start, end);
    expect(body, contains('Tools.appUserAgent'));
    expect(body.contains('browserUserAgent'), isFalse);
  });
}
