import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/kemono_api.dart';
import 'package:lolisnatcher/src/boorus/kemono_handler.dart';
import 'package:lolisnatcher/src/boorus/kemono_query.dart';
import 'package:lolisnatcher/src/boorus/kemono_tag_catalog.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/kemono_creator.dart';
import 'package:lolisnatcher/src/data/kemono_post.dart';
import 'package:lolisnatcher/src/data/site_profile.dart';
import 'package:lolisnatcher/src/data/site_profiles/kemono_profile.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/kemono_creator_store.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/services/image_writer.dart';
import 'package:lolisnatcher/src/handlers/post_files_handler.dart';
import 'package:lolisnatcher/src/handlers/kemono_file_hosts.dart';
import 'package:lolisnatcher/src/handlers/kemono_session_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/pages/kemono_messages_pages.dart';
import 'package:lolisnatcher/src/widgets/image/custom_network_image.dart';

/// kemono.cr, against responses captured from the live API on 2026-09-04
/// (test/fixtures/kemono_*.json).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  String fixture(String name) => File('test/fixtures/$name').readAsStringSync();
  dynamic json(String name) => jsonDecode(fixture(name));
  Booru b() => Booru('kemono', BooruType.Kemono, '', 'https://kemono.cr', '');
  KemonoHandler handler() => KemonoHandler(b(), 50);

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('kemono');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    KemonoSessionHandler.instance.resetForTests();
    KemonoCreatorStore.instance.resetForTests();
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('the query language', () {
    test('plain words search; tags repeat; negations are dropped', () {
      final q = KemonoQuery.parse('hatsune miku tag:nsfw tag:wip_art -foo');
      expect(q.kind, KemonoQueryKind.posts);
      expect(q.q, 'hatsune miku');
      expect(q.tags, ['nsfw', 'wip art']);
      expect(q.error, isNull);
    });

    test('the site wants three characters', () {
      expect(KemonoQuery.parse('mi').error, KemonoQuery.tooShortMessage);
      expect(KemonoQuery.parse('mik').error, isNull);
      expect(KemonoQuery.parse('').kind, KemonoQueryKind.posts);
    });

    test('a creator by service and id, in both spellings, or by name', () {
      expect(KemonoQuery.parse('creator:patreon:5993691').creator, (service: 'patreon', id: '5993691'));
      expect(KemonoQuery.parse('patreon:5993691').creator, (service: 'patreon', id: '5993691'));
      final byName = KemonoQuery.parse('creator:Aenaluck');
      expect(byName.kind, KemonoQueryKind.creatorPosts);
      expect(byName.needsCreatorLookup, isTrue);
      expect(byName.creatorName, 'Aenaluck');
    });

    test('service filters locally, popular takes a period and a date, random and favorites are feeds', () {
      expect(KemonoQuery.parse('service:fanbox').service, 'fanbox');
      final pop = KemonoQuery.parse('popular:week:2026-08-25');
      expect(pop.kind, KemonoQueryKind.popular);
      expect(pop.period, 'week');
      expect(pop.date, '2026-08-25');
      expect(KemonoQuery.parse('popular:week:yesterday').error, isNotNull);
      expect(KemonoQuery.parse('random').kind, KemonoQueryKind.randomPost);
      expect(KemonoQuery.parse('favorites:posts').kind, KemonoQueryKind.favouritePosts);
      final one = KemonoQuery.parse('id:patreon:5993691:65627907');
      expect(one.kind, KemonoQueryKind.post);
      expect(one.postId, '65627907');
    });
  });

  group('URLs', () {
    test('offset paging in steps of 50, tags repeated, popular dated', () {
      final h = handler()..pageNum = 2;
      expect(h.makeURL('miku tag:nsfw tag:comic'), 'https://kemono.cr/api/v1/posts?q=miku&o=100&tag=nsfw&tag=comic');
      expect(h.makeURL('creator:patreon:5993691'), 'https://kemono.cr/api/v1/patreon/user/5993691/posts?o=100');
      expect(h.makeURL('popular:week:2026-08-25'), 'https://kemono.cr/api/v1/posts/popular?date=2026-08-25&period=week&o=100');
      expect(h.makeURL('popular'), contains('period=day'));
    });

    test('single-page feeds lock after the first page; a short query never fetches', () {
      final h = handler()..pageNum = 0;
      expect(h.makeURL('random'), 'https://kemono.cr/api/v1/posts/random');
      h.pageNum = 1;
      expect(h.makeURL('random'), '');
      expect(h.locked, isTrue);
      final short = handler()..pageNum = 0;
      expect(short.makeURL('mi'), '');
      expect(short.errorString, KemonoQuery.tooShortMessage);
    });

    test('favorites without a session is refused with a reason, not a 401', () {
      final h = handler()..pageNum = 0;
      expect(h.makeURL('favorites:posts'), '');
      expect(h.errorString, contains('username and password'));
    });
  });

  group('the listing', () {
    test('every shape of list yields rows and a count', () {
      expect(KemonoHandler.rowsOf(json('kemono_posts.json')).rows.length, greaterThan(0));
      expect(KemonoHandler.rowsOf(json('kemono_posts.json')).count, greaterThan(1000000));
      expect(KemonoHandler.rowsOf(json('kemono_creator_posts.json')).rows.length, 50, reason: 'a plain array');
      expect(KemonoHandler.rowsOf({'props': {'count': 7}, 'results': [{'id': '1'}]}).count, 7);
      expect(KemonoHandler.rowsOf(json('kemono_popular.json')).rows.length, greaterThan(0));
    });

    test('rows with no media are dropped; a service filter keeps its service', () {
      final rows = KemonoHandler.rowsOf(json('kemono_posts_search.json')).rows;
      final kept = KemonoHandler.filterRows(rows);
      expect(kept.every(KemonoHandler.hasMedia), isTrue);
      final fanbox = KemonoHandler.filterRows(rows, service: 'fanbox');
      expect(fanbox.every((r) => r['service'] == 'fanbox'), isTrue);
      expect(KemonoHandler.hasMedia({'file': {}, 'attachments': []}), isFalse);
    });

    test('an item: cover thumbnail, file on its hashed host, composite id, creator tag, badge', () async {
      final rows = KemonoHandler.rowsOf(json('kemono_posts.json')).rows;
      final row = rows.firstWhere((r) => (r['attachments'] as List).length >= 2);
      final BooruItem item = (await handler().parseItemFromResponse(row, 0))!;
      expect(item.thumbnailURL, startsWith('https://img.kemono.cr/thumbnail/data/'));
      expect(item.fileURL, matches(RegExp(r'^https://n[1-4]\.kemono\.cr/data/')));
      expect(item.fileURL, isNot(contains('https://kemono.cr/data')));
      expect(item.serverId, '${row['service']}:${row['user']}:${row['id']}');
      expect(item.postURL, 'https://kemono.cr/${row['service']}/user/${row['user']}/post/${row['id']}');
      expect(item.tagsList.any((t) => t.tagType == TagType.artist), isTrue);
      expect(item.tagsList.any((t) => t.fullString == 'service:${row['service']}'), isTrue);
      expect(item.fileCountHint.value, greaterThanOrEqualTo(2));
      expect(item.postDateFormat, 'iso');
      expect(item.description, contains(row['title'].toString().trim()));
    });

    test('the creators of a page feed the strip, two or more only', () {
      final h = handler();
      final rows = KemonoHandler.rowsOf(json('kemono_posts.json')).rows;
      final creators = h.creatorsOf(rows);
      expect(creators.length, greaterThanOrEqualTo(2));
      expect(creators.first.searchQuery, startsWith('creator:'));
      expect(creators.first.avatarUrl, startsWith('https://img.kemono.cr/icons/'));
      expect(h.creatorsOf(rows.take(1).toList()), isEmpty);
    });
  });

  group('post files', () {
    test('cover first, then the attachments, on the server the detail names', () {
      final files = KemonoProfile.filesFromDetail(json('kemono_post.json') as Map)!;
      expect(files.length, greaterThanOrEqualTo(2));
      expect(files.first.url, matches(RegExp(r'^https://n\d\.kemono\.cr/data/')), reason: 'the preview names its server');
      expect(files.every((f) => f.thumbnailUrl == null || f.thumbnailUrl!.startsWith('https://img.kemono.cr/thumbnail/')), isTrue);
      expect(files.map((f) => f.url).toSet().length, files.length, reason: 'no path twice');
    });

    test('the profile resolves by host, builds the detail address from the composite id, and asks for text/css', () {
      final profile = SiteProfile.forBooru(b())!;
      expect(profile.id, 'kemono');
      expect(profile.hasMultipleFilesPerPost, isTrue);
      final item = BooruItem(fileURL: 'x', sampleURL: 'x', thumbnailURL: 'x', tagsList: const [], postURL: 'p', serverId: 'patreon:5993691:65627907');
      expect(profile.postFilesUrl(b(), item), 'https://kemono.cr/api/v1/patreon/user/5993691/post/65627907');
      expect(profile.postFilesHeaders(b())['Accept'], 'text/css');
      expect(KemonoProfile.isVideoPath('/ab/cd/x.mp4'), isTrue);
      expect(KemonoProfile.isVideoPath('/ab/cd/x.gif'), isFalse);
    });
  });

  group('the creator index', () {
    test('rows decode compactly with epoch times', () {
      final rows = KemonoCreatorStore.parseRows(fixture('kemono_creators_200.json'));
      expect(rows.length, 200);
      expect(rows.first.length, 6);
      expect(rows.first[0], isA<String>());
      expect(rows.first[3], isA<int>());
      final c = KemonoCreator.fromJson((json('kemono_creators_200.json') as List).first as Map)!;
      expect(c.iconUrl, 'https://img.kemono.cr/icons/${c.service}/${c.id}');
      expect(c.bannerUrl, 'https://img.kemono.cr/banners/${c.service}/${c.id}');
      expect(c.searchQuery, 'creator:${c.service}:${c.id}');
      expect(KemonoCreator.epochOf('2026-04-04T22:42:47.243932'), greaterThan(1700000000));
      expect(KemonoCreator.epochOf(1680383094), 1680383094);
    });

    test('a profile and the updated list parse into creators', () {
      final profile = KemonoCreator.fromJson(json('kemono_profile.json') as Map)!;
      expect(profile.name, 'Aenaluck');
      final updated = (json('kemono_artists_updated.json') as Map)['results'] as List;
      expect(updated.map((r) => KemonoCreator.fromJson(r as Map)).whereType<KemonoCreator>().length, updated.length);
    });
  });

  group('the tag builder', () {
    test('the global tag list is one shard with counts, always inserted qualified', () {
      final rows = KemonoTagCatalog.parseTags(json('kemono_tags.json'));
      expect(rows.length, greaterThan(1000));
      expect(rows.first.name, 'nsfw');
      expect(rows.first.count, greaterThan(100000));
      final catalog = handler().tagCatalog as KemonoTagCatalog;
      expect(catalog.searchTerm(rows.first), 'tag:nsfw');
      expect(catalog.namespaceFor('creator')!.customPicker, isNotNull);
      expect(catalog.namespaceFor('creator_tags'), isNull, reason: 'only on a creator tab');
      final onCreator = handler()..makeURL('creator:patreon:5993691');
      expect(onCreator.tagCatalog.namespaceFor('creator_tags'), isNotNull);
    });
  });

  group('messages', () {
    test('DMs, creator DMs and announcements share one shape', () {
      final dms = (json('kemono_dms.json') as Map)['props']['dms'] as List;
      final first = KemonoMessage.fromJson(dms.first as Map)!;
      expect(first.user, isNotEmpty);
      expect(first.date, isNotNull);
      final creatorDms = json('kemono_creator_dms.json') as List;
      expect(KemonoMessage.fromJson(creatorDms.first as Map)!.text, isNotEmpty);
      final ann = json('kemono_announcements.json') as List;
      expect(KemonoMessage.fromJson(ann.first as Map)!.user, '5993691');
    });
  });

  group('the session', () {
    test('the cookie is read out of Set-Cookie, kept per username, and gone on logout', () async {
      expect(KemonoSessionHandler.sessionCookieFrom(['session=abc123; Path=/; HttpOnly; Secure']), 'session=abc123');
      expect(KemonoSessionHandler.sessionCookieFrom(['other=1']), isNull);
      final Booru withLogin = b()
        ..userID = 'someone'
        ..apiKey = 'secret';
      expect(KemonoSessionHandler.hasCredentials(withLogin), isTrue);
      expect(KemonoSessionHandler.hasCredentials(b()), isFalse);
      expect(KemonoSessionHandler.instance.hasSession(withLogin), isFalse);
      expect(KemonoApi.headers(withLogin).containsKey('Cookie'), isFalse);
      // No credentials: never a request, never a session.
      expect(await KemonoSessionHandler.instance.relogin(b()), isFalse);
      expect(KemonoApi.headers(b())['Accept'], 'text/css');
    });
  });

  group('file servers', () {
    // Observed 2026-09-04: the 302 target of https://kemono.cr/data{path} for
    // eight live paths. The site's bundle picks the same host client-side, and
    // the API names it in a post detail's `server` (checked below on the
    // fixture) — so the app addresses that host directly, as the site does.
    const Map<String, String> observed = {
      '/e5/01/e50103ae3e5a110a1d0c0613e1032e24d9fcddc666027bfa2dffc24a35873e3b.mp4': 'n3',
      '/5e/ed/5eed06421a9ec787dce18f6dd8a839c2cd63c1891435a74374d15485814ad259.png': 'n2',
      '/97/bd/97bd8f1d7c85e34d6352907a1d69343e0e3d86b3f618ce3921253f8b2a7168ca.mp4': 'n1',
      '/47/30/47308f1fc594f154c251fad08166bf9c6078f0a9e353964c84d9a225fe232393.png': 'n2',
      '/1a/86/1a869637084c232b1a2110313d893176605bbdd132be0cc4c0a64c7bba70687a.gif': 'n4',
      '/5c/3c/5c3ccbd159fb7f90f4473a6aea92abf89429b81fa5344bbd594385d1aad4065e.jpg': 'n4',
      '/fa/e6/fae63b2f505a9c0b1ebb159271d5be02e047dc2430aa3caa12886a80f2a96d7e.jpg': 'n3',
      '/35/93/359355058537746af301ba2b3d23e608eca865345daa87545e0639487f917b29.jpg': 'n3',
    };

    test('the murmur2 pick matches the redirect targets and the API-named servers', () {
      for (final e in observed.entries) {
        expect(KemonoApi.fileServer(e.key), 'https://${e.value}.kemono.cr', reason: e.key);
      }
      final detail = json('kemono_post.json');
      int checked = 0;
      for (final key in ['attachments', 'previews', 'videos']) {
        for (final e in (detail[key] as List? ?? [])) {
          if (e is Map && e['server'] != null && e['path'] != null) {
            expect(KemonoApi.fileServer(e['path'] as String), e['server'], reason: e['path'].toString());
            checked++;
          }
        }
      }
      expect(checked, greaterThan(0));
    });

    test('murmur2 known answers (murmurhash-js murmurhash2_32_gc, seed 0)', () {
      expect(KemonoApi.murmur2(''), 0);
      expect(KemonoApi.murmur2('/data/x'), 871033270);
    });

    test('URLs skip the redirect host; a named server wins; the cover is something the viewer can show', () {
      expect(KemonoApi.fileUrl('/ab/cd/abcd.png'), matches(RegExp(r'^https://n[1-4]\.kemono\.cr/data/ab/cd/abcd\.png$')));
      expect(KemonoApi.fileUrl('/ab/cd/abcd.png', server: 'https://n9.kemono.cr'), 'https://n9.kemono.cr/data/ab/cd/abcd.png');
      final files = KemonoProfile.filesFromDetail(json('kemono_post.json'))!;
      expect(files.every((f) => !f.url.startsWith('https://kemono.cr/data')), isTrue);
      expect(KemonoProfile.coverPath(['/a/b/pack.zip', '/a/b/pic.png', '/a/b/clip.mp4']), '/a/b/pic.png');
      expect(KemonoProfile.coverPath(['/a/b/pack.zip', '/a/b/doc.psd']), '/a/b/pack.zip');
    });
  });

  group('the post page', () {
    test('a post with an archive: the rar is an attachment with its real name, the picture is the only displayable file', () {
      final KemonoPost post = KemonoPost.fromDetail(json('kemono_post_attachments.json'))!;
      expect(post.title, contains('Download Link'));
      expect(post.files.length, 2, reason: 'cover + attachments, the duplicated picture once');
      expect(post.images.map((f) => f.name), ['picture1.png']);
      expect(post.images.single.url, 'https://n2.kemono.cr/data/89/00/8900e15531db8ab583708269fed7033a79fbd8a0eb502cc901ba31c4cf9f9093.png');
      expect(post.images.single.thumbUrl, startsWith('https://img.kemono.cr/thumbnail/data/'));
      final KemonoPostFile rar = post.attachments.single;
      expect(rar.name, 'Gayle Ped (NieR Reincarnation).rar');
      expect(rar.extension, 'rar', reason: 'stored as .bin, named .rar');
      expect(rar.kind, KemonoFileKind.other);
      expect(rar.url, 'https://n3.kemono.cr/data/e1/f4/e1f4aa53d4094f1d8d59655fb60e68d64fd4791b394bba3ffc53b955bc228da9.bin');
      expect(post.displayable.length, 1);
      expect(post.hasContent, isFalse);
      expect(post.embed, isNull);
      expect(post.tags, ['download', 'link']);
      expect(post.next, isNotEmpty);
      expect(post.prev, isNotEmpty);
    });

    test('content: links stay, the site-relative file links become file-host URLs', () {
      final KemonoPost post = KemonoPost.fromDetail(json('kemono_post_content.json'))!;
      expect(post.hasContent, isTrue);
      expect(post.contentForHtml(), contains('downloads.fanbox.cc'));
      const KemonoPost inline = KemonoPost(
        service: 'patreon',
        user: '1',
        id: '2',
        title: 't',
        contentHtml: '<p>hi <img src="/data/ab/cd/abcd.png"> <a href="/data/ab/cd/abcd.png">dl</a> <a href="https://x.y/z">x</a></p>',
        files: [],
        tags: [],
      );
      final String html = inline.contentForHtml();
      expect(html, contains('src="https://n'));
      expect(html, contains('.kemono.cr/data/ab/cd/abcd.png"'));
      expect(html, isNot(contains('"/data/')));
      expect(html, contains('href="https://x.y/z"'));
    });

    test('the files overlay keeps only what it can show; downloads keep the site name', () {
      final List<PostFile> files = KemonoProfile.filesFromDetail(json('kemono_post_attachments.json'))!;
      expect(files.length, 2);
      expect(files.map((f) => f.name), ['picture1.png', 'Gayle Ped (NieR Reincarnation).rar']);
      expect(files.map((f) => f.isDisplayable), [true, false]);
      expect(PostFilesHandler.displayable(files).length, 1);
      final BooruItem post = BooruItem(fileURL: 'https://n2.kemono.cr/x.png', sampleURL: '', thumbnailURL: 't', tagsList: const [], postURL: 'p');
      final List<BooruItem> items = PostFilesHandler.instance.itemsFor(post, files);
      expect(items.length, 1);
      expect(items.single.downloadFileName, 'picture1.png');
      final BooruItem rar = BooruItem(
        fileURL: 'https://n3.kemono.cr/data/e1/f4/e1f4.bin',
        sampleURL: '',
        thumbnailURL: 't',
        tagsList: const [],
        postURL: 'p',
        fileExt: 'rar',
        downloadFileName: 'Gayle Ped (NieR Reincarnation).rar',
      );
      expect(ImageWriter().getFilename(rar, b()), 'Gayle Ped (NieR Reincarnation).rar');
      final BooruItem odd = BooruItem(fileURL: 'https://n3.kemono.cr/a.bin', sampleURL: '', thumbnailURL: 't', tagsList: const [], postURL: 'p', downloadFileName: 'a/b:c?.zip');
      expect(ImageWriter().getFilename(odd, b()), 'a_b_c_.zip');
    });

    test("an image item samples from the site's image service; a video keeps its file", () async {
      final rows = KemonoHandler.rowsOf(json('kemono_posts.json')).rows;
      final h = handler();
      final BooruItem? image = await h.parseItemFromResponse(
        rows.firstWhere((r) => (r['file'] as Map)['path'].toString().endsWith('.png')),
        0,
      );
      expect(image!.sampleURL, image.thumbnailURL);
      expect(image.sampleURL, startsWith('https://img.kemono.cr/thumbnail/data/'));
      final BooruItem? video = await h.parseItemFromResponse(
        rows.firstWhere((r) => (r['file'] as Map)['path'].toString().endsWith('.mp4')),
        0,
      );
      expect(video!.sampleURL, video.fileURL);
      expect(video.sampleURL, matches(RegExp(r'^https://n[1-4]\.kemono\.cr/data/')));
    });
  });

  group('the file hosts', () {
    setUp(KemonoFileHosts.instance.resetForTests);
    tearDown(KemonoFileHosts.instance.resetForTests);

    test('a host that failed a fresh probe gets a notice; a reachable or stale one does not', () async {
      final KemonoFileHosts hosts = KemonoFileHosts.instance;
      expect(KemonoFileHosts.instance.hosts, ['n1.kemono.cr', 'n2.kemono.cr', 'n3.kemono.cr', 'n4.kemono.cr']);
      expect(hosts.noticeFor('https://n3.kemono.cr/data/x.png'), isNull, reason: 'nothing checked yet');
      hosts.probeOverride = (host) async => KemonoHostStatus(
        host: host,
        ok: host != 'n3.kemono.cr',
        error: host == 'n3.kemono.cr' ? 'connection timed out' : null,
        checkedAt: DateTime.now(),
      );
      await hosts.check();
      expect(hosts.checked, isTrue);
      expect(hosts.noticeFor('https://n3.kemono.cr/data/x.png'), contains('n3.kemono.cr is not reachable'));
      expect(hosts.noticeFor('https://n3.kemono.cr/data/x.png'), contains('connection timed out'));
      expect(hosts.noticeFor('https://n2.kemono.cr/data/x.png'), isNull);
      expect(hosts.noticeFor('https://img.kemono.cr/thumbnail/data/x.png'), isNull);
      expect(hosts.summary(), contains('n3 ✗'));
      expect(hosts.summary(), contains('connection timed out'));
      // A fresh result is reused; a forced check runs again.
      int probes = 0;
      hosts.probeOverride = (host) async {
        probes++;
        return KemonoHostStatus(host: host, ok: true, checkedAt: DateTime.now());
      };
      await hosts.check();
      expect(probes, 0);
      await hosts.check(force: true);
      expect(probes, 4);
      expect(hosts.noticeFor('https://n3.kemono.cr/data/x.png'), isNull);
      // Stale results say nothing.
      hosts.state.value = {
        'n1.kemono.cr': KemonoHostStatus(host: 'n1.kemono.cr', ok: false, error: 'x', checkedAt: DateTime.now().subtract(const Duration(hours: 1))),
      };
      expect(hosts.noticeFor('https://n1.kemono.cr/data/x.png'), isNull);
      expect(hosts.isFresh, isFalse);
    });

    test('the handler speaks for its file hosts only', () {
      final h = handler();
      expect(h.mediaOutageNotice('https://img.kemono.cr/thumbnail/data/x.png'), isNull);
      expect(KemonoFileHosts.isFileHost('n4.kemono.cr'), isTrue);
      expect(KemonoFileHosts.isFileHost('kemono.cr'), isFalse);
    });
  });

  group('paging and loading', () {
    test('the first fetch is o=0: runSearch increments before it, so the factory leaves pageNum at -1', () {
      final built = BooruHandlerFactory().getBooruHandler([b()], null);
      expect(built.startingPage, -1);
      final KemonoHandler h = built.booruHandler as KemonoHandler;
      h.pageNum = built.startingPage + 1;
      expect(h.makeURL('kemono'), 'https://kemono.cr/api/v1/posts?q=kemono&o=0');
      h.pageNum++;
      expect(h.makeURL('kemono'), 'https://kemono.cr/api/v1/posts?q=kemono&o=50');
    });

    test('the JPEG end-marker check only applies to JPEG bytes', () {
      expect(looksLikeJpeg([0xFF, 0xD8, 0xFF, 0xE0]), isTrue);
      expect(looksLikeJpeg('RIFF'.codeUnits), isFalse, reason: 'WebP under a .jpeg URL');
      expect(looksLikeJpeg([0x89, 0x50]), isFalse);
      expect(looksLikeJpeg([0xFF]), isFalse);
      expect(hasJpegEndMarker([0xFF, 0xD9, 0x53, 0x4E]), isTrue);
    });

    test('post files read a plain body, and a decoded one is re-encoded', () {
      expect(PostFilesHandler.bodyText('{"a":1}'), '{"a":1}');
      expect(PostFilesHandler.bodyText({'a': 1}), '{"a":1}');
      expect(PostFilesHandler.bodyText([1, 2]), '[1,2]');
      expect(PostFilesHandler.bodyText(null), '');
      final files = const KemonoProfile().parsePostFiles(fixture('kemono_post_attachments.json'), b());
      expect(files!.length, 2);
    });
  });
}
