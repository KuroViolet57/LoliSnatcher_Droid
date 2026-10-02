import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/handlers/reverse_image_search.dart';

/// r73: reverse image search for boards. SauceNAO (the user's own API key;
/// the anonymous account may not use the API, checked 2026-09-18) answers a
/// JSON list with per-site post ids and the character / series / artist of
/// the match; e621's own iqdb takes a file upload. Both shapes are the
/// documented ones; a real SauceNAO answer needs the user's key.
void main() {
  setUp(ReverseImageSearch.resetForTests);
  tearDown(ReverseImageSearch.resetForTests);

  const Map<String, dynamic> sauceNao = {
    'header': {
      'user_id': '1', 'account_type': '1', 'short_limit': '6', 'long_limit': '200', 'long_remaining': 199, 'short_remaining': 5,
      'status': 0, 'results_requested': 8, 'search_depth': '128', 'minimum_similarity': 50.5, 'results_returned': 3,
    },
    'results': [
      {
        'header': {'similarity': '93.55', 'thumbnail': 'https://img3.saucenao.com/thumb.jpg', 'index_id': 9, 'index_name': 'Index #9: Danbooru - x', 'dupes': 1},
        'data': {
          'ext_urls': ['https://danbooru.donmai.us/post/show/1234', 'https://gelbooru.com/index.php?page=post&s=view&id=99'],
          'danbooru_id': 1234, 'gelbooru_id': 99, 'creator': 'ebifurai', 'material': 'Hololive', 'characters': 'Sakamata Chloe, Ookami Mio', 'source': 'https://twitter.com/x',
        },
      },
      {
        'header': {'similarity': '71.20', 'thumbnail': '', 'index_id': 29, 'index_name': 'Index #29: e621 - x'},
        'data': {'ext_urls': ['https://e621.net/post/show/555'], 'e621_id': 555, 'creator': 'someone', 'material': '', 'characters': ''},
      },
      {
        'header': {'similarity': '40.00', 'thumbnail': '', 'index_id': 5, 'index_name': 'Index #5: Pixiv Images'},
        'data': {'ext_urls': ['https://www.pixiv.net/artworks/1'], 'pixiv_id': 1, 'member_name': 'p', 'title': 't'},
      },
    ],
  };

  test('SauceNAO: matches with site, post id, similarity and the match\'s own tags; weak ones dropped', () {
    final List<ReverseMatch> m = ReverseImageSearch.parseSauceNao(sauceNao);
    expect(m, hasLength(2), reason: 'below the minimum similarity is noise');
    expect(m.first.site, 'danbooru');
    expect(m.first.postId, '1234');
    expect(m.first.similarity, closeTo(93.55, 0.01));
    expect(m.first.alsoOn, {'gelbooru': '99'}, reason: 'the same match names the post on other sites');
    expect(m.first.tags, ['sakamata_chloe', 'ookami_mio', 'hololive', 'ebifurai']);
    expect(m.first.urls.first, 'https://danbooru.donmai.us/post/show/1234');
    expect(m[1].site, 'e621');
    expect(m[1].postId, '555');
    expect(m[1].tags, ['someone']);
  });

  test('SauceNAO: a negative status is a refusal with the site\'s message; a positive one is a partial answer that keeps its results; a weird body is an error', () {
    expect(
      () => ReverseImageSearch.parseSauceNao(const {'header': {'status': -1, 'message': 'The anonymous account type does not permit API usage.'}}),
      throwsA(predicate((e) => e.toString().contains('anonymous account'))),
    );
    expect(
      () => ReverseImageSearch.parseSauceNao(const {'header': {'status': -2, 'message': 'Search Rate Too High.'}, 'results': []}),
      throwsA(predicate((e) => e.toString().contains('Rate'))),
    );
    final Map<String, dynamic> partial = Map<String, dynamic>.from(sauceNao)
      ..['header'] = {...sauceNao['header'] as Map<String, dynamic>, 'status': 1, 'message': 'Index #9 is down'};
    expect(ReverseImageSearch.parseSauceNao(partial), hasLength(2), reason: 'an index down still leaves the others');
    expect(() => ReverseImageSearch.parseSauceNao('<html>'), throwsA(anything));
  });

  test('SauceNAO request: the key, JSON output, the count and the image as a file or a url', () async {
    String? url;
    FormData? form;
    ReverseImageSearch.poster = (String u, {Object? data, Map<String, String>? headers, Options? options}) async {
      url = u;
      form = data as FormData;
      return Response(requestOptions: RequestOptions(), data: sauceNao);
    };
    final List<ReverseMatch> m = await ReverseImageSearch.sauceNao(apiKey: 'k1', imageBytes: [1, 2, 3], numres: 5);
    expect(m, hasLength(2));
    expect(url, 'https://saucenao.com/search.php');
    final Map<String, String> fields = {for (final f in form!.fields) f.key: f.value};
    expect(fields['api_key'], 'k1');
    expect(fields['output_type'], '2');
    expect(fields['numres'], '5');
    expect(fields['db'], '999');
    expect(form!.files.single.key, 'file');
    await ReverseImageSearch.sauceNao(apiKey: 'k1', imageUrl: 'https://x/y.jpg');
    final Map<String, String> fields2 = {for (final f in form!.fields) f.key: f.value};
    expect(fields2['url'], 'https://x/y.jpg');
    expect(form!.files, isEmpty);
    expect(() => ReverseImageSearch.sauceNao(apiKey: '', imageBytes: [1]), throwsA(predicate((e) => e.toString().contains('API key'))));
  });

  test('e621 iqdb: a file upload to iqdb_queries.json; the real answer (post 5000000, 2026-09-18) wraps the post as "posts" with a tag_string', () async {
    String? url;
    FormData? form;
    ReverseImageSearch.poster = (String u, {Object? data, Map<String, String>? headers, Options? options}) async {
      url = u;
      form = data as FormData;
      return Response(requestOptions: RequestOptions(), data: jsonDecode(File('test/fixtures/e621_iqdb.json').readAsStringSync()));
    };
    final List<ReverseMatch> m = await ReverseImageSearch.e621Iqdb(imageBytes: [1, 2, 3]);
    expect(url, 'https://e621.net/iqdb_queries.json');
    expect(form!.files.single.key, 'search[file]');
    expect(m, hasLength(1));
    expect(m.first.site, 'e621');
    expect(m.first.postId, '5000000');
    expect(m.first.similarity, closeTo(97.85, 0.01));
    expect(m.first.tags, containsAll(['fleurfurr', 'anthro', 'jackalope']));
    // Weak rows dropped; the older categorised shape still reads.
    expect(ReverseImageSearch.parseE621Iqdb([{'post_id': 1, 'score': 10.0, 'post': {'posts': {'tag_string': 'x'}}}]), isEmpty);
    expect(
      ReverseImageSearch.parseE621Iqdb([{'post_id': 2, 'score': 90.0, 'post': {'tags': {'character': ['c'], 'general': ['g']}}}]).single.tags,
      ['c', 'g'],
    );
    expect(() => ReverseImageSearch.parseE621Iqdb({'success': false, 'message': 'Not allowed to request content from this URL'}), throwsA(predicate((e) => e.toString().contains('Not allowed'))));
  });

  test('a match round-trips through json (the board caches them)', () {
    final ReverseMatch m = ReverseImageSearch.parseSauceNao(sauceNao).first;
    final ReverseMatch back = ReverseMatch.fromJson(m.toJson());
    expect(back.site, 'danbooru');
    expect(back.postId, '1234');
    expect(back.similarity, closeTo(93.55, 0.01));
    expect(back.tags, m.tags);
    expect(back.alsoOn, {'gelbooru': '99'});
    expect(back.urls, m.urls);
  });

  test('tag normalisation: the site\'s display names become booru tags', () {
    expect(ReverseImageSearch.normaliseTag(' Sakamata Chloe '), 'sakamata_chloe');
    expect(ReverseImageSearch.splitNames('Sakamata Chloe, Ookami Mio'), ['sakamata_chloe', 'ookami_mio']);
    expect(ReverseImageSearch.splitNames(''), isEmpty);
    expect(ReverseImageSearch.splitNames(null), isEmpty);
  });
}
