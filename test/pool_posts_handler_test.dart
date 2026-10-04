import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/booru_pool.dart';
import 'package:lolisnatcher/models/tag.dart';
import 'package:lolisnatcher/sources/framework/booru_handler.dart';
import 'package:lolisnatcher/sources/booru/pools/pool_posts_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';

/// One post looked up by `id:N`, like the Gelbooru family's handler: a
/// refused request leaves the list empty and says why in [errorString].
class _ById extends BooruHandler {
  _ById(super.booru, super.limit, this.site);

  final _Site site;

  @override
  String validateTags(String tags) => tags;

  @override
  Future search(String tags, int? pageNumCustom, {bool withCaptchaCheck = true}) async {
    final String id = tags.substring('id:'.length);
    site.asked.add(id);
    await Future<void>.delayed(Duration.zero);
    if (site.refused.contains(id)) {
      errorString = '429 - Too Many Requests';
      return fetched;
    }
    if (site.gone.contains(id)) return fetched;
    fetched.add(
      BooruItem(
        fileURL: 'https://img.rule34.xxx/$id.jpg',
        sampleURL: '',
        thumbnailURL: '',
        tagsList: [Tag('pool_member')],
        postURL: 'https://rule34.xxx/index.php?page=post&s=view&id=$id',
        serverId: id,
      ),
    );
    return fetched;
  }
}

class _Site {
  final List<String> asked = [];
  final Set<String> refused = {};
  final Set<String> gone = {};
}

/// 1.0 (M2): a Gelbooru-family pool is read one post at a time by id. The
/// next page started at "how many posts were added", so a page where two
/// lookups failed asked two posts of the previous page again; and a page
/// where every lookup was refused (rate limit) ended the pool.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _Site site;
  final Booru r34 = Booru('rule34xxx', BooruType.Gelbooru, '', 'https://rule34.xxx', '');
  final List<String> forty = [for (int i = 1; i <= 40; i++) '$i'];

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    TagHandler.register();
    tempDir = Directory.systemTemp.createTempSync('pool_posts');
    SettingsHandler.instance
      ..path = '${tempDir.path}${Platform.pathSeparator}'
      ..dbEnabled = false;
    site = _Site();
    PoolPostsHandler.idsFor = (Booru booru, BooruPool pool) async => forty;
    PoolPostsHandler.lookupHandlerFor = (Booru booru) => _ById(booru, 1, site);
  });

  tearDown(() {
    PoolPostsHandler.idsFor = null;
    PoolPostsHandler.lookupHandlerFor = null;
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  List<String> idsOf(PoolPostsHandler h) => [for (final i in h.fetched) i.serverId!];

  test('a page where some lookups fail: the next page starts after the whole slice, and no post is asked twice', () async {
    site.refused.addAll(['5', '7']);
    final PoolPostsHandler h = PoolPostsHandler(r34, 20, poolId: '9', poolName: 'x');
    await h.search('pool: x', null);
    expect(idsOf(h), [for (int i = 1; i <= 20; i++) if (i != 5 && i != 7) '$i']);
    await h.search('pool: x', null);
    expect(idsOf(h), [for (int i = 1; i <= 40; i++) if (i != 5 && i != 7) '$i'], reason: 'pool order, nothing twice');
    expect(site.asked.toSet().length, site.asked.length, reason: 'each member asked once: ${site.asked}');
    expect(h.locked, isFalse);
    await h.search('pool: x', null);
    expect(h.locked, isTrue, reason: 'the end of the pool');
  });

  test('a page where every lookup is refused does not end the pool: it is an error, and a retry asks the same posts', () async {
    site.refused.addAll([for (int i = 1; i <= 20; i++) '$i']);
    final PoolPostsHandler h = PoolPostsHandler(r34, 20, poolId: '9', poolName: 'x');
    await h.search('pool: x', null);
    expect(h.fetched, isEmpty);
    expect(h.locked, isFalse, reason: 'later members exist');
    expect(h.errorString, contains('429'));
    // The site answers again; the feed's retry clears the error and asks again.
    site.refused.clear();
    h.errorString = '';
    await h.search('pool: x', null);
    expect(idsOf(h), [for (int i = 1; i <= 20; i++) '$i']);
  });

  test('posts the site no longer has are skipped and the pool goes on', () async {
    site.gone.addAll([for (int i = 1; i <= 20; i++) '$i']);
    final PoolPostsHandler h = PoolPostsHandler(r34, 20, poolId: '9', poolName: 'x');
    await h.search('pool: x', null);
    expect(idsOf(h), [for (int i = 21; i <= 40; i++) '$i']);
    expect(h.locked, isFalse);
    expect(h.errorString, isEmpty);
  });
}
