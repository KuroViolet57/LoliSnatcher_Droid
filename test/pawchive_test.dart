import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/kemono_api.dart';
import 'package:lolisnatcher/src/boorus/kemono_handler.dart';
import 'package:lolisnatcher/src/boorus/kemono_query.dart';
import 'package:lolisnatcher/src/boorus/kemono_site.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/kemono_creator.dart';
import 'package:lolisnatcher/src/data/kemono_post.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/site_profile.dart';
import 'package:lolisnatcher/src/data/site_profiles/kemono_profile.dart';
import 'package:lolisnatcher/src/handlers/kemono_creator_store.dart';
import 'package:lolisnatcher/src/handlers/kemono_file_hosts.dart';
import 'package:lolisnatcher/src/handlers/kemono_session_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/widgets/preview/main_search_query_editor_page.dart';

/// pawchive.pw — kemono's archive on the older API — through the same
/// handler as kemono, with what the site lacks written down in [KemonoSite].
/// Fixtures captured 2026-09-05.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  String fixture(String name) => File('test/fixtures/$name').readAsStringSync();
  dynamic json(String name) => jsonDecode(fixture(name));

  Booru b() => Booru('pawchive', BooruType.Pawchive, '', 'https://pawchive.pw', '');
  Booru k() => Booru('kemono', BooruType.Kemono, '', 'https://kemono.cr', '');
  KemonoHandler handler() => KemonoHandler(b(), 50);

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('pawchive');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    KemonoSessionHandler.instance.resetForTests();
    KemonoFileHosts.forSite(KemonoSite.pawchive).resetForTests();
    KemonoApi.clearDetailCache();
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('the site', () {
    test('resolves from the booru type and keeps kemono as the default', () {
      expect(KemonoSite.of(b()), KemonoSite.pawchive);
      expect(KemonoSite.of(k()), KemonoSite.kemono);
      expect(KemonoSite.of(null), KemonoSite.kemono);
      expect(BooruType.Pawchive.isKemono, isTrue);
      expect(BooruType.Pawchive.isPawchive, isTrue);
      expect(BooruType.Kemono.isPawchive, isFalse);
      expect(BooruType.Pawchive.isDetectable, isFalse);
      expect(BooruType.Pawchive.alias, 'Pawchive');
    });

    test('URLs: one file host, thumbnails on img., icons and banners on the main host', () {
      const s = KemonoSite.pawchive;
      expect(s.api, 'https://pawchive.pw/api/v1');
      expect(s.fileUrl('/ab/cd/abcd.png'), 'https://file.pawchive.pw/data/ab/cd/abcd.png');
      expect(s.fileUrl('/ab/cd/abcd.png', server: 'https://n9.kemono.cr'), 'https://n9.kemono.cr/data/ab/cd/abcd.png');
      expect(s.thumbUrl('/ab/cd/abcd.png'), 'https://img.pawchive.pw/thumbnail/data/ab/cd/abcd.png');
      expect(s.iconUrl('fanbox', '1'), 'https://pawchive.pw/icons/fanbox/1');
      expect(s.bannerUrl('fanbox', '1'), 'https://pawchive.pw/banners/fanbox/1');
      expect(s.postUrl('fanbox', '5679193', '12549384'), 'https://pawchive.pw/fanbox/user/5679193/post/12549384');
      expect(s.creatorPostsUrl('fanbox', '5679193', offset: 50), 'https://pawchive.pw/api/v1/fanbox/user/5679193/posts?o=50');
      expect(s.postsUrl(q: 'ab', tags: ['x y']), 'https://pawchive.pw/api/v1/posts?q=ab&o=0&tag=x+y');
      expect(s.loginUrl, 'https://pawchive.pw/account/login');
      expect(KemonoSite.ofFileHost('file.pawchive.pw'), KemonoSite.pawchive);
      expect(KemonoSite.ofFileHost('n2.kemono.cr'), KemonoSite.kemono);
      expect(KemonoSite.ofFileHost('img.pawchive.pw'), isNull);
      // kemono's own builders did not move.
      expect(KemonoApi.fileUrl('/5e/ed/5eed06421a9ec787dce18f6dd8a839c2cd63c1891435a74374d15485814ad259.png'), startsWith('https://n2.kemono.cr/data/'));
    });

    test('headers: plain JSON accept, no referer on files; kemono unchanged', () {
      final h = handler();
      expect(h.getHeaders()['Accept'], 'application/json');
      expect(h.getHeaders()['Referer'], 'https://pawchive.pw/');
      expect(h.getMediaHeaders(), isEmpty);
      expect(KemonoHandler(k(), 50).getHeaders()['Accept'], 'text/css');
      expect(KemonoHandler(k(), 50).getMediaHeaders()['Referer'], 'https://kemono.cr/');
    });
  });

  group('the query', () {
    test('two characters search; popular and random are refused with the reason', () {
      final h = handler();
      expect(h.makeURL('ab'), 'https://pawchive.pw/api/v1/posts?q=ab&o=0');
      expect(h.errorString, isEmpty);
      final hk = KemonoHandler(k(), 50);
      expect(hk.makeURL('ab'), '');
      expect(hk.errorString, KemonoQuery.tooShortMessage);
      expect(h.makeURL('popular:day'), '');
      expect(h.errorString, 'pawchive has no popular feed');
      expect(h.makeURL('random'), '');
      expect(h.errorString, 'pawchive has no random post');
      expect(h.makeURL('favorites:posts'), '');
      expect(h.errorString, contains('pawchive username and password'));
      expect(h.makeURL('tag:x creator:fanbox:5679193'), 'https://pawchive.pw/api/v1/fanbox/user/5679193/posts?o=0&tag=x');
      expect(handler().makeURL('fanbox:5679193'), 'https://pawchive.pw/api/v1/fanbox/user/5679193/posts?o=0');
    });

    test('metatags and the tag builder drop what the site has not', () {
      final h = handler();
      final names = h.availableMetaTags().map((m) => m.name).toList();
      expect(names, isNot(contains('Popular')));
      expect(names, contains('Favorites'));
      expect(h.tagCatalog.namespaces.map((n) => n.key), ['creator']);
      expect(KemonoHandler(k(), 50).tagCatalog.namespaces.map((n) => n.key), containsAll(['tag', 'creator']));
      final labels = [
        for (final e in MetatagsBlock.mergedEntries(h.availableMetaTags(), h.tagCatalog))
          e is TagCatalogNamespace ? '[${e.label}]' : (e as MetaTag).name,
      ];
      expect(labels.first, '[Artists]');
      expect(labels, contains('Tag'));
    });
  });

  group('the listing', () {
    test('a bare array of 50 rows; items sample from the image service and file from file.pawchive.pw', () async {
      final parsed = KemonoHandler.rowsOf(json('pawchive_posts.json'));
      expect(parsed.rows.length, 50);
      final row = parsed.rows.firstWhere((r) => (r['file'] as Map)['path'].toString().endsWith('.jpeg'));
      final BooruItem item = (await handler().parseItemFromResponse(row, 0))!;
      expect(item.fileURL, startsWith('https://file.pawchive.pw/data/'));
      expect(item.sampleURL, startsWith('https://img.pawchive.pw/thumbnail/data/'));
      expect(item.thumbnailURL, item.sampleURL);
      expect(item.postURL, startsWith('https://pawchive.pw/${row['service']}/user/${row['user']}/post/'));
      expect(item.serverId, '${row['service']}:${row['user']}:${row['id']}');
      expect(KemonoHandler.rowsOf(json('pawchive_creator_posts.json')).rows.length, 50);
    });

    test('a video row keeps its file as the sample and the icon as the thumbnail', () async {
      // The captured page has its videos as attachments behind a cover; a
      // hand-made row with the video as the main file exercises the rule.
      final Map row = {
        'id': '1',
        'user': '2',
        'service': 'fanbox',
        'title': 'clip',
        'file': {'name': 'clip.mp4', 'path': '/69/d7/69d7ab45f64d7c5d771e935e36dcc0c401c6737e904edcc89e5b366c600938db.mp4'},
        'attachments': [],
      };
      final BooruItem item = (await handler().parseItemFromResponse(row, 0))!;
      expect(item.sampleURL, item.fileURL);
      expect(item.thumbnailURL, startsWith('https://pawchive.pw/icons/'));
    });
  });

  group('the post', () {
    test('a flat detail: no envelope, no servers, files on the site host, has_full read', () {
      final Map detail = json('pawchive_post.json') as Map;
      expect(detail['post'], isNull, reason: 'pawchive returns the post itself');
      expect(KemonoHandler.postOf(Map<String, dynamic>.from(detail))?['id'], '12549384');
      final KemonoPost post = KemonoPost.fromDetail(detail, site: KemonoSite.pawchive)!;
      expect(post.site, KemonoSite.pawchive);
      expect(post.files.length, 2);
      expect(post.files.first.name, 'cover.jpeg');
      expect(post.files.first.url, startsWith('https://file.pawchive.pw/data/11/d2/'));
      expect(post.files.first.thumbUrl, startsWith('https://img.pawchive.pw/thumbnail/data/'));
      expect(post.files.last.kind, KemonoFileKind.image);
      expect(post.hasFull, isNotNull);
      expect(post.hasContent, isTrue);
      expect(post.contentForHtml(), contains('<p>'));
      expect(post.next, isNotNull);
      expect(post.postUrl, 'https://pawchive.pw/fanbox/user/5679193/post/12549384');
      final List<PostFile> files = KemonoProfile.filesFromDetail(detail, site: KemonoSite.pawchive)!;
      expect(files.every((f) => f.url.startsWith('https://file.pawchive.pw/data/')), isTrue);
      expect(files.map((f) => f.name), ['cover.jpeg', 'cOwQHn7v1d8emHXdFwmX5DWW.png']);
    });

    test('kemono envelopes still parse (nothing moved for kemono)', () {
      final KemonoPost post = KemonoPost.fromDetail(json('kemono_post_attachments.json'))!;
      expect(post.site, KemonoSite.kemono);
      expect(post.hasFull, isNull);
      expect(post.attachments.single.url, startsWith('https://n3.kemono.cr/data/'));
    });

    test("site-relative links in the content resolve on this site's file host", () {
      const KemonoPost p = KemonoPost(
        service: 'fanbox',
        user: '1',
        id: '2',
        title: 't',
        contentHtml: '<img src="/data/ab/cd/abcd.png">',
        files: [],
        tags: [],
        site: KemonoSite.pawchive,
      );
      expect(p.contentForHtml(), '<img src="https://file.pawchive.pw/data/ab/cd/abcd.png">');
    });
  });

  group('the creator index', () {
    test("rows parse with the site attached; the store is separate from kemono's", () {
      final rows = KemonoCreatorStore.parseRows(fixture('pawchive_creators_200.json'));
      expect(rows.length, 200);
      final KemonoCreator c = KemonoCreator.fromJson(json('pawchive_creators_200.json')[0] as Map, site: KemonoSite.pawchive)!;
      expect(c.iconUrl, startsWith('https://pawchive.pw/icons/'));
      expect(c.bannerUrl, startsWith('https://pawchive.pw/banners/'));
      expect(KemonoCreatorStore.forSite(KemonoSite.pawchive).site.creatorTable, 'PawchiveCreator');
      expect(identical(KemonoCreatorStore.forSite(KemonoSite.pawchive), KemonoCreatorStore.instance), isFalse);
      expect(identical(KemonoCreatorStore.forSite(KemonoSite.kemono), KemonoCreatorStore.instance), isTrue);
      expect(KemonoCreatorStore.forSite(KemonoSite.pawchive).metaFile, 'pawchive_creators.json');
      expect(KemonoCreator.fromJson(json('pawchive_profile.json') as Map, site: KemonoSite.pawchive)!.name, 'kingnill');
      expect(KemonoCreator.epochOf('2026-09-05T00:00:00'), greaterThan(0));
    });

    test("profile, tags and announcements keep kemono's shapes", () {
      expect((json('pawchive_tags.json') as List).first['tag'], isNotEmpty);
      expect((json('pawchive_announcements.json') as List).first['content'], isNotEmpty);
    });
  });

  group('the file host and the session', () {
    test("the probe set is the site's own; a notice names pawchive", () async {
      final hosts = KemonoFileHosts.forSite(KemonoSite.pawchive);
      expect(hosts.hosts, ['file.pawchive.pw']);
      expect(identical(hosts, KemonoFileHosts.instance), isFalse);
      hosts.probeOverride = (host) async => KemonoHostStatus(host: host, ok: false, error: 'connection timed out', checkedAt: DateTime.now());
      await hosts.check();
      expect(hosts.noticeFor('https://file.pawchive.pw/data/x.png'), startsWith("pawchive's file host file.pawchive.pw"));
      expect(handler().mediaOutageNotice('https://file.pawchive.pw/data/x.png'), isNotNull);
      expect(handler().mediaOutageNotice('https://img.pawchive.pw/thumbnail/data/x.png'), isNull);
      expect(KemonoFileHosts.instance.noticeFor('https://n2.kemono.cr/data/x.png'), isNull, reason: "kemono's probes are its own");
    });

    test('sessions are keyed per site; the form login is read from the redirect', () {
      final Booru pw = b()
        ..userID = 'Someone'
        ..apiKey = 'pw';
      final Booru ke = k()
        ..userID = 'Someone'
        ..apiKey = 'pw';
      expect(KemonoSessionHandler.keyFor(pw), 'pawchive|someone');
      expect(KemonoSessionHandler.keyFor(ke), 'kemono|someone');
      expect(KemonoSessionHandler.sessionFromLoginResponse(302, ['session=abc; Path=/; HttpOnly'], form: true), 'session=abc');
      expect(KemonoSessionHandler.sessionFromLoginResponse(200, ['session=abc'], form: true), 'session=abc');
      expect(KemonoSessionHandler.sessionFromLoginResponse(200, const [], form: true), isNull);
      expect(KemonoSessionHandler.sessionFromLoginResponse(401, ['session=abc'], form: true), isNull);
      expect(KemonoSessionHandler.sessionFromLoginResponse(302, ['session=abc'], form: false), isNull, reason: 'the API login answers 200');
      expect(KemonoSessionHandler.instance.hasSession(pw), isFalse);
    });
  });
}
