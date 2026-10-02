import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/foryou_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/interests_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

/// r75: "Recommend more like this" opens the For You feed seeded with a
/// post's tags. A feed whose sources answer nothing must say so, not stay
/// blank; a feed whose sources answer fills with what they said.
class _FakeSource extends BooruHandler {
  _FakeSource(super.booru, super.limit);

  final List<String> queries = [];
  Map<String, List<List<String>>> answers = {};

  String get host => Uri.parse(booru.baseURL!).host;

  @override
  String validateTags(String tags) => tags;

  @override
  Future search(String tags, int? pageNumCustom, {bool withCaptchaCheck = true}) async {
    queries.add(tags);
    if (prevTags != tags) fetched.value = [];
    prevTags = tags;
    final List<List<String>> rows = answers.entries.where((e) => tags.contains(e.key)).map((e) => e.value).firstOrNull ?? const [];
    fetched.addAll([
      for (int i = 0; i < rows.length; i++)
        BooruItem(
          fileURL: 'https://$host/f/${tags.hashCode.abs()}-$pageNum-$i.jpg',
          sampleURL: '',
          thumbnailURL: '',
          tagsList: rows[i].map(Tag.new).toList(),
          postURL: 'https://$host/p/${tags.hashCode.abs()}-$pageNum-$i',
          serverId: '${tags.hashCode.abs() % 1000}$pageNum$i',
        ),
    ]);
    return fetched;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  final Map<String, _FakeSource> fakes = {};
  Booru b(String name) => Booru(name, BooruType.Gelbooru, '', 'https://$name.example', '');
  final Booru forYou = Booru('For You', BooruType.ForYou, '', '', '');

  setUp(() {
    SettingsHandler.register();
    SearchHandler.register();
    InterestsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('foryou_seed');
    SettingsHandler.instance
      ..path = '${tempDir.path}${Platform.pathSeparator}'
      ..dbEnabled = false;
    SettingsHandler.instance.booruList.value = [b('one'), b('two')];
    fakes.clear();
    ForYouHandler.resetForTests();
    ForYouHandler.resolveTag = (String tag, Booru booru) async => tag;
    ForYouHandler.sourceFactory = (Booru booru, int limit) {
      final _FakeSource f = fakes.putIfAbsent(booru.name ?? '', () => _FakeSource(booru, limit));
      return (handler: f, startingPage: 0);
    };
  });
  tearDown(() {
    ForYouHandler.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a seeded feed asks every source for the seed and fills with the answers', () async {
    fakes['one'] = _FakeSource(b('one'), 20)..answers = {'hatsune_miku': [['hatsune_miku', 'vocaloid'], ['hatsune_miku', 'solo']]};
    fakes['two'] = _FakeSource(b('two'), 20)..answers = {'hatsune_miku': [['hatsune_miku', 'beach']]};
    final ForYouHandler h = ForYouHandler(forYou, 20);
    final List<BooruItem> items = List<BooruItem>.from(await h.search('seed:hatsune_miku', null) as List);
    expect(items, isNotEmpty);
    expect([...fakes['one']!.queries, ...fakes['two']!.queries].where((q) => q.contains('hatsune_miku')), isNotEmpty);
    expect(h.errorString, isEmpty);
    expect(h.locked, isFalse);
  });

  test('a seeded feed whose sources answer nothing says which seeds went unanswered instead of staying blank', () async {
    fakes['one'] = _FakeSource(b('one'), 20);
    fakes['two'] = _FakeSource(b('two'), 20);
    final ForYouHandler h = ForYouHandler(forYou, 20);
    final List items = await h.search('seed:hatsune_miku seed:vocaloid', null) as List;
    expect(items, isEmpty);
    expect(h.locked, isTrue);
    expect(h.errorString, contains('hatsune_miku'));
    expect(h.errorString, contains('vocaloid'));
    expect(fakes['one']!.queries, isNotEmpty, reason: 'the sources were asked before giving up');
  });

  test('a site that confirms it has no such tag is skipped for that seed; the others answer', () async {
    ForYouHandler.resolveTag = (String tag, Booru booru) async => booru.name == 'one' ? null : tag;
    fakes['one'] = _FakeSource(b('one'), 20)..answers = {'hatsune_miku': [['hatsune_miku', 'never']]};
    fakes['two'] = _FakeSource(b('two'), 20)..answers = {'hatsune_miku': [['hatsune_miku', 'beach']]};
    final ForYouHandler h = ForYouHandler(forYou, 20);
    final List<BooruItem> items = List<BooruItem>.from(await h.search('seed:hatsune_miku', null) as List);
    expect(items, isNotEmpty);
    expect(fakes['one']!.queries, isEmpty, reason: 'not asked for a tag it said it lacks');
    expect(fakes['two']!.queries, isNotEmpty);
  });

  test('from:<host> puts the post\'s own site first among many sources; the term is not a seed', () async {
    SettingsHandler.instance.booruList.value = [b('one'), b('two'), b('three'), b('four'), b('five'), b('six')];
    for (final String name in ['one', 'two', 'three', 'four', 'five', 'six']) {
      fakes[name] = _FakeSource(b(name), 20)..answers = {'hatsune_miku': [['hatsune_miku', name]]};
    }
    expect(ForYouHandler.preferredHost('from:six.example seed:hatsune_miku'), 'six.example');
    expect(ForYouHandler.preferredHost('seed:hatsune_miku'), isNull);
    final ForYouHandler h = ForYouHandler(forYou, 20);
    final List<BooruItem> items = List<BooruItem>.from(await h.search('from:six.example seed:hatsune_miku', null) as List);
    expect(items, isNotEmpty);
    expect(fakes['six']!.queries, isNotEmpty, reason: 'the post\'s own site is asked on the first page');
    expect(fakes['six']!.queries.first, 'hatsune_miku', reason: 'the from: term is not searched for');
    expect(fakes['six']!.queries.first, isNot(contains('from:')));
  });
}
