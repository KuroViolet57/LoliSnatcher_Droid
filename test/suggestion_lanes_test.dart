import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/tag.dart';
import 'package:lolisnatcher/models/tag_type.dart';
import 'package:lolisnatcher/sources/framework/booru_handler.dart';
import 'package:lolisnatcher/features/recommender/logic/suggestion_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/storage/tag_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';

/// A site handler that, like the real base class, reads its page number
/// after an await (searchSetup) and notices being searched twice at once.
class _Site extends BooruHandler {
  _Site(super.booru, super.limit);

  int _inFlight = 0;
  bool reentered = false;

  /// (query, page) in the order the site saw them.
  final List<(String, int)> asked = [];

  @override
  String validateTags(String tags) => tags;

  @override
  Future search(String tags, int? pageNumCustom, {bool withCaptchaCheck = true}) async {
    if (_inFlight > 0) reentered = true;
    _inFlight++;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      asked.add((tags, pageNum));
      if (prevTags != tags) fetched.value = [];
      prevTags = tags;
      final String slug = tags.replaceAll(' ', '+');
      fetched.addAll([
        for (int i = 0; i < 3; i++)
          BooruItem(
            fileURL: 'https://img.site.example/$slug-$pageNum-$i.jpg',
            sampleURL: '',
            thumbnailURL: '',
            tagsList: [Tag(tags.split(' ').first)],
            postURL: 'https://site.example/p/$slug/$pageNum/$i',
          ),
      ]);
      return fetched;
    } finally {
      _inFlight--;
    }
  }
}

/// 1.0 (M2): the Suggested strip fired every facet at once on the post's own
/// site through ONE handler. Each facet bumped the shared page number before
/// the handler read it, so every facet asked the same deep page (page 7 of a
/// small character tag is empty), and the facets' results overwrote each
/// other in the shared list.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final Booru booru = Booru('site', BooruType.Gelbooru, '', 'https://site.example', '');
  final List<_Site> sites = [];

  BooruItem post() => BooruItem(
    fileURL: 'https://img.site.example/source.jpg',
    sampleURL: '',
    thumbnailURL: '',
    tagsList: [
      Tag('char_one', tagType: TagType.character),
      Tag('char_two', tagType: TagType.character),
      Tag('the_series', tagType: TagType.copyright),
      Tag('the_artist', tagType: TagType.artist),
      Tag('act_one_thing', count: 10),
      Tag('act_two_thing', count: 20),
    ],
    postURL: 'https://site.example/p/source',
  );

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    TagHandler.register();
    tempDir = Directory.systemTemp.createTempSync('suggestion_lanes');
    SettingsHandler.instance
      ..path = '${tempDir.path}${Platform.pathSeparator}'
      ..dbEnabled = false;
    sites.clear();
    SuggestionHandler.handlerFactory = (Booru b, int limit) {
      final _Site s = _Site(b, limit);
      sites.add(s);
      return s;
    };
  });

  tearDown(() {
    SuggestionHandler.handlerFactory = null;
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test("on the post's own site the facets take turns, and each asks its query's first page", () async {
    final SuggestionHandler h = SuggestionHandler(booru, 30, sourceItem: post());
    final List<BooruItem> got = List<BooruItem>.from(await h.search('suggestions', null) as List);
    final _Site site = sites.single;
    expect(site.asked.length, greaterThan(2), reason: 'several facets were asked');
    expect(site.reentered, isFalse, reason: 'a handler is never searched twice at once');
    expect(site.asked.map((a) => a.$2).toSet(), {0}, reason: 'every query starts at the first page: ${site.asked}');
    expect(got, isNotEmpty);
  });

  test('a query asked again on a later round asks its next page', () async {
    final SuggestionHandler h = SuggestionHandler(booru, 30, sourceItem: post());
    await h.search('suggestions', null);
    await h.search('suggestions', null);
    final _Site site = sites.single;
    expect(site.reentered, isFalse);
    final List<int> charOne = [for (final a in site.asked) if (a.$1 == 'char_one') a.$2];
    expect(charOne, [0, 1], reason: site.asked.toString());
  });

  test("each facet keeps its own posts: no post comes back under another facet's query", () async {
    final SuggestionHandler h = SuggestionHandler(booru, 30, sourceItem: post());
    final List<BooruItem> got = List<BooruItem>.from(await h.search('suggestions', null) as List);
    final Set<String> asked = {for (final a in sites.single.asked) a.$1.replaceAll(' ', '+')};
    // Every facet answered three posts; the blend shows each facet's own.
    final Set<String> shown = {for (final i in got) Uri.parse(i.postURL).pathSegments[1]};
    expect(shown, asked, reason: 'every facet is represented by its own posts');
  });
}
