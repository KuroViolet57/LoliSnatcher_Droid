import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_on_rails_handler.dart';
import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/doujin_filters.dart';
import 'package:lolisnatcher/src/boorus/e621_handler.dart';
import 'package:lolisnatcher/src/boorus/hydrus_handler.dart';
import 'package:lolisnatcher/src/boorus/ink_bunny_handler.dart';
import 'package:lolisnatcher/src/boorus/kusowanka_handler.dart';
import 'package:lolisnatcher/src/boorus/moebooru_handler.dart';
import 'package:lolisnatcher/src/boorus/philomena_handler.dart';
import 'package:lolisnatcher/src/boorus/realbooru_handler.dart';
import 'package:lolisnatcher/src/boorus/redgifs_handler.dart';
import 'package:lolisnatcher/src/boorus/szurubooru_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/comment_item.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/note_item.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

/// r71 booru parity sweep: the thin booru sources get the base features of
/// their family (metatags and filter chips, comments, notes) plus what each
/// site offers. Every syntax below was checked on the live site on
/// 2026-09-17 (yande.re cheat sheet; twibooru sf/sd; realbooru sort:;
/// kusowanka's shelves; RedGifs type= and verified=; the comment APIs of
/// yande.re, e621, derpibooru and twibooru) or comes from the engine's
/// documented API (szurubooru, hydrus, inkbunny).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  Booru b(String name, BooruType type, String url) => Booru(name, type, '', url, '');
  dynamic fixture(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync());
  Response<dynamic> resp(dynamic data) => Response(requestOptions: RequestOptions(), data: data);
  List<String> values(DoujinFilterSpec spec, String key) => spec.group(key)!.options.map((o) => o.value).toList();
  List<String> keysOf(List<MetaTag> tags) => tags.map((m) => m.keyName).toList();

  setUp(() {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('booru_parity');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
  });
  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('moebooru (yande.re cheat sheet)', () {
    MoebooruHandler h() => MoebooruHandler(b('yande', BooruType.Moebooru, 'https://yande.re'), 20);

    test('metatags: rating, order, ranges, user, md5, source, parent, vote; chips from them', () {
      final List<MetaTag> tags = h().availableMetaTags();
      expect(
        keysOf(tags),
        containsAll(['rating', 'order', 'score', 'width', 'height', 'mpixels', 'ratio', 'date', 'id', 'user', 'md5', 'source', 'parent', 'vote']),
      );
      final OrderMetaTag order = tags.whereType<OrderMetaTag>().single;
      expect(
        order.values.map((v) => v.value),
        containsAll(['id', 'id_desc', 'score', 'score_asc', 'mpixels', 'mpixels_asc', 'landscape', 'portrait', 'vote']),
      );
      final DoujinFilterSpec spec = h().siteFilters!;
      expect(values(spec, 'order'), containsAll(['id', 'id_desc', 'score', 'landscape', 'portrait', 'vote']));
      expect(values(spec, 'order'), isNot(contains('score_asc')), reason: 'ascending twins stay typeable, not chips');
      expect(values(spec, 'rating'), ['', 'safe', 'questionable', 'explicit']);
    });

    test('comments: comment.json?post_id=, creator and body, the date as sent', () async {
      expect(h().hasCommentsSupport, isTrue);
      // The dialog counts pages from 0; one answer holds the whole thread.
      expect(h().makeCommentsURL('1000000', 0), 'https://yande.re/comment.json?post_id=1000000');
      expect(h().makeCommentsURL('1000000', 1), '');
      final List rows = h().parseCommentsList(resp(fixture('moebooru_comments.json')));
      expect(rows, hasLength(16));
      final CommentItem? c = h().parseComment(rows.first, 0);
      expect(c, isNotNull);
      expect(c!.id, '213214');
      expect(c.authorName, 'wxrpass');
      expect(c.authorID, '337105');
      expect(c.content, 'lucky~');
      expect(c.postID, '1000000');
      expect(c.createDateFormat, 'iso');
      expect(c.createDate, '2022-07-25T20:37:52.063Z', reason: 'the dialog turns the zone into local time');
    });

    test('notes: note.json?post_id=, inactive notes skipped; the post flag from last_noted_at', () async {
      expect(h().hasNotesSupport, isTrue);
      final List posts = h().parseListFromResponse(resp(File('test/fixtures/moebooru_posts.xml').readAsStringSync()));
      expect(posts, hasLength(2));
      expect(h().parseItemFromResponse(posts[0], 0)!.hasNotes, isTrue, reason: 'last_noted_at set');
      expect(h().parseItemFromResponse(posts[1], 1)!.hasNotes, isFalse, reason: 'last_noted_at="0"');
      expect(h().makeNotesURL('1246878'), 'https://yande.re/note.json?post_id=1246878');
      final List rows = h().parseNotesList(resp(fixture('moebooru_notes.json')));
      expect(rows, hasLength(22));
      final NoteItem? n = h().parseNote(rows.first, 0);
      expect(n, isNotNull);
      expect(n!.id, '7781');
      expect(n.postID, '1246878');
      expect(n.posX, 3098);
      expect(n.posY, 4677);
      expect(n.width, 442);
      expect(n.height, 392);
      expect(n.content, 'post #1246879');
      final Map<String, dynamic> inactive = Map<String, dynamic>.from(rows.first as Map)..['is_active'] = false;
      expect(h().parseNote(inactive, 0), isNull);
    });
  });

  group('e621 comments (comments.json)', () {
    e621Handler h() => e621Handler(b('e621', BooruType.e621, 'https://e621.net'), 20);

    test('url with page; rows with creator_name; hidden comments skipped', () async {
      expect(h().hasCommentsSupport, isTrue);
      // The dialog counts pages from 0, the site from 1.
      expect(h().makeCommentsURL('5000000', 0), 'https://e621.net/comments.json?search[post_id]=5000000&group_by=comment&page=1');
      expect(h().makeCommentsURL('5000000', 2), 'https://e621.net/comments.json?search[post_id]=5000000&group_by=comment&page=3');
      final List rows = h().parseCommentsList(resp(fixture('e621_comments.json')));
      expect(rows, hasLength(1));
      final CommentItem? c = h().parseComment(rows.first, 0);
      expect(c, isNotNull);
      expect(c!.id, '10034829');
      expect(c.authorName, 'Donovan_DMC');
      expect(c.authorID, '323290');
      expect(c.score, 0);
      expect(c.postID, '5000000');
      expect(c.createDate, '2026-08-26T22:17:26.682-04:00');
      expect(c.createDateFormat, 'iso');
      final Map<String, dynamic> hidden = Map<String, dynamic>.from(rows.first as Map)..['is_hidden'] = true;
      expect(h().parseComment(hidden, 0), isNull);
    });
  });

  group('philomena comments (derpibooru search/comments)', () {
    PhilomenaHandler h() => PhilomenaHandler(b('derpi', BooruType.Philomena, 'https://derpibooru.org'), 20);

    test('url (key when set); author, avatar and body', () async {
      expect(h().hasCommentsSupport, isTrue);
      // The dialog counts pages from 0; the site aliases page 0 to 1, so 0 -> 1.
      expect(h().makeCommentsURL('1', 0), 'https://derpibooru.org/api/v1/json/search/comments?q=image_id:1&per_page=50&page=1');
      final PhilomenaHandler keyed = h()..booru.apiKey = 'k';
      expect(keyed.makeCommentsURL('1', 2), 'https://derpibooru.org/api/v1/json/search/comments?q=image_id:1&per_page=50&page=3&key=k');
      final List rows = h().parseCommentsList(resp(fixture('philomena_comments.json')));
      expect(rows, hasLength(3));
      final CommentItem? c = h().parseComment(rows.first, 0);
      expect(c, isNotNull);
      expect(c!.id, '11561250');
      expect(c.authorName, 'AvoidingFever17');
      expect(c.authorID, '701696');
      expect(c.avatarUrl, startsWith('https://derpicdn.net/avatars/'));
      expect(c.postID, '1');
      expect(c.content, contains('Hooray'));
      expect(c.createDate, '2026-08-03T18:16:28Z');
    });
  });

  group('twibooru (booru-on-rails)', () {
    BooruOnRailsHandler h() => BooruOnRailsHandler(b('twi', BooruType.BooruOnRails, 'https://twibooru.org'), 20)..pageNum = 1;

    test('sort field and direction go to sf/sd, not into q; range terms stay in q', () {
      final String sorted = h().makeURL('solo sf:score sd:asc');
      expect(sorted, contains('q=solo&'));
      expect(sorted, endsWith('&sf=score&sd=asc'));
      expect(sorted, isNot(contains('sf:')));
      final String plain = h().makeURL('solo');
      expect(plain, 'https://twibooru.org/api/v3/search/posts?q=solo&perpage=20&page=1');
      expect(h().makeURL('solo score.gte:100'), contains('q=solo,score.gte:100&'));
      expect(h().makeURL('sf:random'), contains('q=*&'));
    });

    test('filter chips: sort, direction, score and favorites; metatags for the typed fields', () {
      final DoujinFilterSpec spec = h().doujinFilters;
      expect(values(spec, 'sf'), containsAll(['', 'score', 'random', 'faves', 'upvotes', 'comment_count', 'width', 'height', 'tag_count']));
      expect(values(spec, 'sd'), ['', 'asc']);
      expect(values(spec, 'score.gte'), ['', '10', '25', '50', '100'], reason: 'top scores are ~200; 500+ never matched');
      expect(values(spec, 'faves.gte'), ['', '10', '25', '50', '100']);
      expect(keysOf(h().availableMetaTags()), containsAll(['uploader', 'id', 'source_url', 'description', 'sha512_hash']));
    });

    test('comments: /api/v3/posts/<id>/comments; anonymous rows; hidden ones skipped', () async {
      expect(h().hasCommentsSupport, isTrue);
      expect(h().makeCommentsURL('3408660', 0), 'https://twibooru.org/api/v3/posts/3408660/comments');
      expect(h().makeCommentsURL('3408660', 1), '', reason: 'one answer holds the thread');
      final List rows = h().parseCommentsList(resp(fixture('twibooru_comments.json')));
      expect(rows, hasLength(26));
      final CommentItem? c = h().parseComment(rows.first, 0);
      expect(c, isNotNull);
      expect(c!.id, '15348');
      expect(c.authorName, 'Anonymous');
      expect(c.content, startsWith('ah sweet'));
      expect(c.createDate, '2024-12-13T06:37:44.421Z');
      final Map<String, dynamic> hidden = Map<String, dynamic>.from(rows.first as Map)..['hidden_from_users'] = true;
      expect(h().parseComment(hidden, 0), isNull);
    });
  });

  group('szurubooru', () {
    SzurubooruHandler h() => SzurubooruHandler(b('szu', BooruType.Szurubooru, 'https://booru.example'), 20)..pageNum = 0;

    test('order:asc flips the sort term to -sort:, order:desc unflips a typed -sort:', () {
      expect(h().makeURL('cat sort:score'), 'https://booru.example/api/posts/?offset=0&limit=20&query=cat sort:score');
      expect(h().makeURL('cat sort:score order:asc'), 'https://booru.example/api/posts/?offset=0&limit=20&query=cat -sort:score');
      expect(h().makeURL('cat order:asc'), 'https://booru.example/api/posts/?offset=0&limit=20&query=cat');
      expect(h().makeURL('-sort:score order:desc'), 'https://booru.example/api/posts/?offset=0&limit=20&query=sort:score');
      // What production sends: the base validator percent-encodes the query.
      expect(h().makeURL(Uri.encodeComponent('cat sort:score order:asc')), 'https://booru.example/api/posts/?offset=0&limit=20&query=cat%20-sort%3Ascore');
      expect(h().makeURL(Uri.encodeComponent('100%_orange_juice order:asc')), endsWith('query=100%25_orange_juice'));
    });

    test('metatags and chips: sort, direction, safety, type, special, ranges', () {
      final List<MetaTag> tags = h().availableMetaTags();
      expect(
        keysOf(tags),
        containsAll(['sort', 'order', 'safety', 'type', 'special', 'score', 'tag-count', 'uploader', 'id', 'date', 'pool', 'source', 'content-checksum', 'flag']),
      );
      final DoujinFilterSpec spec = h().doujinFilters!;
      expect(values(spec, 'safety'), ['', 'safe', 'sketchy', 'unsafe']);
      expect(values(spec, 'type'), ['', 'image', 'animation', 'video', 'flash']);
      expect(values(spec, 'special'), ['', 'liked', 'disliked', 'fav', 'tumbleweed']);
      expect(values(spec, 'sort'), containsAll(['', 'random', 'score', 'date', 'fav-count', 'comment-count', 'file-size', 'image-width']));
      expect(values(spec, 'order'), ['', 'asc']);
    });

    test('comments come with the post resource: /api/post/<id>, comments[]', () async {
      expect(h().hasCommentsSupport, isTrue);
      expect(h().makeCommentsURL('12', 0), 'https://booru.example/api/post/12');
      expect(h().makeCommentsURL('12', 1), '');
      final Map<String, dynamic> post = {
        'id': 12,
        'comments': [
          {
            'id': 5,
            'postId': 12,
            'user': {'name': 'alice', 'avatarUrl': 'data/avatars/alice.png'},
            'text': 'nice',
            'creationTime': '2024-01-02T03:04:05.000000Z',
            'score': 3,
          },
        ],
      };
      final List rows = h().parseCommentsList(resp(post));
      expect(rows, hasLength(1));
      final CommentItem? c = h().parseComment(rows.first, 0);
      expect(c, isNotNull);
      expect(c!.id, '5');
      expect(c.authorName, 'alice');
      expect(c.avatarUrl, 'https://booru.example/data/avatars/alice.png');
      expect(c.content, 'nice');
      expect(c.score, 3);
      expect(c.postID, '12');
      expect(c.createDate, '2024-01-02T03:04:05.000000Z');
      expect(h().parseCommentsList(resp({'id': 12})), isEmpty);
    });
  });

  group('kusowanka shelves', () {
    KusowankaHandler h() => KusowankaHandler(b('kuso', BooruType.Kusowanka, 'https://kusowanka.com'), 20)..pageNum = 0;

    test('sort:popular / random / top are the site pages; one page each', () {
      expect(h().makeURL('sort:popular'), 'https://kusowanka.com/popular/');
      expect(h().makeURL('sort:random'), 'https://kusowanka.com/random/');
      expect(h().makeURL('sort:top'), 'https://kusowanka.com/top-rated/');
      expect(h().makeURL('blonde'), 'https://kusowanka.com/tag/blonde/');
      final KusowankaHandler second = h()..pageNum = 1;
      expect(second.makeURL('sort:popular'), '');
      expect(second.locked, isTrue);
      expect(second.errorString, isEmpty, reason: 'the end of a shelf is not an error');
    });

    test('a shelf beside other terms gives way to the search (a saved default Sort must not break queries)', () {
      final KusowankaHandler mixed = h();
      expect(mixed.makeURL('sort:popular blonde'), 'https://kusowanka.com/tag/blonde/');
      expect(mixed.makeURL('artist:chun jian he sort:top'), 'https://kusowanka.com/artist/chun-jian-he/');
      expect(mixed.locked, isFalse);
      expect(mixed.errorString, isEmpty);
      final KusowankaHandler unknown = h();
      expect(unknown.makeURL('sort:nope'), '');
      expect(unknown.locked, isTrue);
      expect(unknown.errorString, contains('no "nope" shelf'));
    });

    test('the sort chip and the facet metatags', () {
      final List<MetaTag> tags = h().availableMetaTags();
      expect(keysOf(tags), containsAll(['sort', 'artist', 'character', 'parody', 'metadata']));
      expect(values(h().siteFilters!, 'sort'), ['', 'popular', 'random', 'top']);
    });
  });

  group('inkbunny', () {
    InkBunnyHandler h() => InkBunnyHandler(b('ib', BooruType.InkBunny, 'https://inkbunny.net'), 20)..pageNum = 1;

    test('type: narrows the submission types; scraps: goes to the scraps param', () {
      expect(h().makeURL('fox type%3Acomic'), contains('&type=4&'));
      expect(h().makeURL('fox type%3Acomic'), contains('text=fox&'));
      expect(h().makeURL('fox type%3Avideo'), contains('&type=8,9&'));
      expect(h().makeURL('fox type%3Acomic type%3Asketch'), contains('&type=2,4&'));
      expect(h().makeURL('fox scraps%3Aonly'), contains('&scraps=only'));
      final String plain = h().makeURL('fox');
      expect(plain, contains('&type=1,2,3,4,5,8,9,13,14&'));
      expect(plain, isNot(contains('scraps=')));
      expect(plain, contains('text=fox&'));
    });

    test('metatags: type values and scraps', () {
      final List<MetaTag> tags = h().availableMetaTags();
      expect(keysOf(tags), containsAll(['artist', 'pool', 'order', 'type', 'scraps']));
      final MetaTagWithValues type = tags.whereType<MetaTagWithValues>().firstWhere((t) => t.keyName == 'type');
      expect(type.values.map((v) => v.value), ['picture', 'sketch', 'series', 'comic', 'portfolio', 'video', 'charactersheet', 'photo']);
      expect(values(h().siteFilters!, 'scraps'), ['', 'no', 'only']);
    });
  });

  group('hydrus', () {
    HydrusHandler h() => HydrusHandler(b('hydrus', BooruType.Hydrus, 'http://localhost:45869'), 20);

    test('sort:/order: chips are lifted from the space-joined query; tags stay comma-separated and raw', () {
      Map<String, String> params(String q) => Uri.parse(h().makeURL(q)).queryParameters;
      expect(h().validateTags(' blue eyes, red hair '), 'blue eyes, red hair', reason: 'no percent-encoding into the JSON list');
      expect(params('blue eyes sort:random order:asc'), {'tags': '["blue eyes"]', 'file_sort_type': '4', 'file_sort_asc': 'true'});
      expect(params('blue eyes, red hair sort:filesize'), {'tags': '["blue eyes","red hair"]', 'file_sort_type': '0', 'file_sort_asc': 'false'});
      expect(params('sort:importtime'), {'tags': '["*"]', 'file_sort_type': '2', 'file_sort_asc': 'false'});
      expect(params(''), {'tags': '["*"]', 'file_sort_asc': 'false'});
    });

    test('sort metatag lists every file_sort_type the handler maps; order asc/desc', () {
      final List<MetaTag> tags = h().availableMetaTags();
      final SortMetaTag sort = tags.whereType<SortMetaTag>().single;
      expect(
        sort.values.map((v) => v.value),
        containsAll([
          'filesize', 'duration', 'importtime', 'filetype', 'random', 'width', 'height', 'ratio', 'numpixels', 'numtags',
          'numviews', 'totalviewtime', 'bitrate', 'hasaudio', 'modifiedtime', 'framerate', 'framecount', 'lastviewed',
          'archivetime', 'hashhex',
        ]),
      );
      for (final MetaTagValue v in sort.values) {
        expect(h().getSortType(v.value), isNot(-1), reason: '${v.value} is not a hydrus sort');
      }
      expect(tags.whereType<OrderMetaTag>().single.values.map((v) => v.value), ['desc', 'asc']);
      expect(keysOf(tags), isNot(contains('system')), reason: 'system predicates need commas, not a chip');
      expect(values(h().siteFilters!, 'sort'), containsAll(['importtime', 'random', 'numviews']));
    });
  });

  group('redgifs', () {
    RedGifsHandler h() => RedGifsHandler(b('rg', BooruType.RedGifs, 'https://www.redgifs.com'), 20)..pageNum = 1;
    Map<String, String> params(String tags) => Uri.parse(h().makeURL(tags)).queryParameters;

    test('type:images / type:gifs -> type=i / g; verified:yes -> verified=y; neither is a tag', () {
      expect(params('blonde type:images')['type'], 'i');
      expect(params('blonde type:images')['tags'], 'blonde');
      expect(params('blonde type:gifs')['type'], 'g');
      expect(params('blonde verified:yes')['verified'], 'y');
      expect(params('blonde verified:yes')['tags'], 'blonde');
      expect(params('blonde').containsKey('type'), isFalse);
      expect(params('blonde').containsKey('verified'), isFalse);
      expect(params('type:images')['tags'], 'nsfw', reason: 'the empty-query default stays');
      // The creator and niche endpoints take type= too (checked live).
      expect(Uri.parse(h().makeURL('creator:someone type:images')).path, '/v2/users/someone/search');
      expect(params('creator:someone type:images')['type'], 'i');
      expect(params('niche:just-boobs type:gifs')['type'], 'g');
      expect(params('niche:just-boobs').containsKey('type'), isFalse);
    });

    test('metatags and chips', () {
      expect(keysOf(h().availableMetaTags()), containsAll(['sort', 'type', 'verified']));
      expect(values(h().siteFilters!, 'type'), ['', 'gifs', 'images']);
      expect(values(h().siteFilters!, 'verified'), ['', 'yes']);
    });
  });

  group('realbooru', () {
    RealbooruHandler h() => RealbooruHandler(b('rb', BooruType.Realbooru, 'https://realbooru.com'), 20)..pageNum = 0;

    test('sort: score and id (checked live), typed through to the list url', () {
      final SortMetaTag sort = h().availableMetaTags().whereType<SortMetaTag>().single;
      expect(sort.values.map((v) => v.value), ['score', 'score:asc', 'id', 'id:asc']);
      expect(values(h().siteFilters!, 'sort'), ['', 'score', 'id']);
      expect(h().makeURL('blonde sort:score'), contains('tags=blonde+sort:score'));
      expect(h().makeURL(Uri.encodeComponent('blonde sort:score')), contains('tags=blonde%20sort%3Ascore'), reason: 'what production sends');
    });
  });
}
