import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/doujin_filters.dart';
import 'package:lolisnatcher/src/boorus/r34hentai_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/tag_suggestion.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';

/// r72: rule34hentai.net's own search, checked in the user's Chrome on
/// 2026-09-18 (the site sits behind Cloudflare, so curl and the built-in
/// browser never got in). The site's Sort menu is `order=id_desc` (newest,
/// the default) and `order=score_desc` (top voted); every other order form,
/// the colon form included, leaves the list unchanged. `content:video|audio`,
/// `ext=webm|mp4|gif|png|jpg`, `score>`, `favorites>`, `comments>` and the
/// Post List operators filter. `rating:` matches only the few rated posts
/// (safe 138 pages, questionable 48, explicit none, of 9,803), so there is
/// no Rating chip. Popular-by-day/month/year pages exist; `/random` is empty.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  Booru b(String name, BooruType type, String url) => Booru(name, type, '', url, '');
  Response<dynamic> resp(dynamic data) => Response(requestOptions: RequestOptions(), data: data);
  List<String> values(DoujinFilterSpec spec, String key) => spec.group(key)!.options.map((o) => o.value).toList();
  // The factory seeds this 1-based site at 0; the first fetch is page 1.
  R34HentaiHandler h() => R34HentaiHandler(b('r34h', BooruType.R34Hentai, 'https://rule34hentai.net'), 20)..pageNum = 1;

  setUp(() {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('r34hentai_parity');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
  });
  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('filter chips: the site menu sort, popular pages, content, file type, score, favorites, comments; no rating', () {
    final DoujinFilterSpec spec = h().siteFilters!;
    expect(spec.group('order')!.divider, '=', reason: 'the site ignores order:x, its menu writes order=x');
    expect(values(spec, 'order'), ['', 'score_desc']);
    expect(values(spec, 'popular'), ['', 'day', 'month', 'year']);
    expect(spec.group('content')!.divider, ':');
    expect(values(spec, 'content'), ['', 'video', 'audio']);
    expect(spec.group('ext')!.divider, '=');
    expect(values(spec, 'ext'), ['', 'webm', 'mp4', 'gif', 'png', 'jpg']);
    expect(spec.group('score')!.divider, '>');
    expect(values(spec, 'score'), ['', '0', '10', '50', '100']);
    expect(spec.group('favorites')!.divider, '>');
    expect(values(spec, 'favorites'), ['', '5', '10', '50', '100']);
    expect(spec.group('comments')!.divider, '>');
    expect(values(spec, 'comments'), ['', '1', '5', '10']);
    expect(spec.group('rating'), isNull, reason: 'only ~2% of posts carry a rating; a chip would hide the rest');
  });

  test('makeURL: terms ride in the path with their dividers; order: becomes order=; a Popular chip alone opens the page', () {
    expect(h().makeURL('blonde order=score_desc ext=webm score>10'), 'https://rule34hentai.net/post/list/blonde+order=score_desc+ext=webm+score>10/1');
    expect(h().makeURL('blonde order:score_desc'), 'https://rule34hentai.net/post/list/blonde+order=score_desc/1');
    expect(h().makeURL(''), 'https://rule34hentai.net/post/list/1');
    expect((h()..pageNum = 3).makeURL('content:video'), 'https://rule34hentai.net/post/list/content:video/3');
    expect(h().makeURL('popular:day'), 'https://rule34hentai.net/popular_by_day');
    expect(h().makeURL('popular:month'), 'https://rule34hentai.net/popular_by_month');
    expect(h().makeURL('popular:year'), 'https://rule34hentai.net/popular_by_year');
    final R34HentaiHandler second = h()..pageNum = 2;
    expect(second.makeURL('popular:day'), '');
    expect(second.locked, isTrue, reason: 'one page each');
    expect(second.errorString, isEmpty);
    expect(h().makeURL('popular:day blonde'), 'https://rule34hentai.net/post/list/blonde/1', reason: 'the search wins, as on kusowanka');
    // The card's own chips and a source's saved defaults do not defeat the Popular chip (review).
    expect(h().makeURL('popular:day ext=webm order=score_desc score>10'), 'https://rule34hentai.net/popular_by_day');
    final String withDefaults = SourceSettingsHandler.composeQuery(query: 'popular:month', spec: h().siteFilters, defaultFilters: 'ext=webm content:video');
    expect(withDefaults, 'popular:month content:video ext=webm', reason: 'defaults compose in the card order');
    expect(h().makeURL(withDefaults), 'https://rule34hentai.net/popular_by_month');
    expect(h().makeURL('popular:day score:>10'), 'https://rule34hentai.net/post/list/score:>10/1', reason: 'a typed field is a search');
    expect(h().makeURL('order:'), 'https://rule34hentai.net/post/list/order=/1', reason: 'harmless: the site ignores it');
    expect(Uri.parse(h().makeURL('score>10')).path, '/post/list/score%3E10/1', reason: 'the request encodes >; the site decodes path segments');
    final R34HentaiHandler unknown = h();
    expect(unknown.makeURL('popular:week'), '');
    expect(unknown.locked, isTrue);
    expect(unknown.errorString, contains('week'));
  });

  test('metatags: the site\'s typed search fields, sort and file type with their own dividers', () {
    final List<MetaTag> tags = h().availableMetaTags();
    expect(
      tags.map((m) => m.keyName),
      containsAll([
        'order', 'popular', 'content', 'ext', 'score', 'favorites', 'comments', 'width', 'height', 'filesize', 'id',
        'size', 'ratio', 'posted', 'source', 'user', 'hash', 'filename', 'upvoted_by', 'downvoted_by', 'favorited_by', 'commented_by',
      ]),
    );
    expect(tags.firstWhere((m) => m.keyName == 'order').divider, '=');
    expect(tags.firstWhere((m) => m.keyName == 'ext').divider, '=');
    expect(tags.firstWhere((m) => m.keyName == 'content').divider, ':');
    expect(tags.whereType<ComparableNumberMetaTag>().map((m) => m.keyName), containsAll(['score', 'favorites', 'comments', 'width', 'height', 'id']));
    expect(tags.map((m) => m.keyName), isNot(contains('rating')));
    expect(tags.firstWhere((m) => m.keyName == 'posted'), isA<DateMetaTag>(), reason: 'posted:date alone answers nothing; before/after does');
    expect(tags.map((m) => m.keyName), isNot(contains('tags')), reason: 'tags=N answers nothing on the site');
  });

  test('autocomplete: the site\'s internal endpoint answers a tag -> count map (Map or raw text), case kept', () {
    expect(h().hasTagSuggestions, isTrue);
    expect(h().makeTagURL('blon'), 'https://rule34hentai.net/api/internal/autocomplete?s=blon');
    final List rows = h().parseTagSuggestionsList(resp({'Blonde_Blazer': '50', 'bloney': '23'}));
    expect(rows, hasLength(2));
    final TagSuggestion? s = h().parseTagSuggestion(rows.first, 0);
    expect(s!.tag, 'Blonde_Blazer');
    expect(s.count, 50);
    final List raw = h().parseTagSuggestionsList(resp('{"Blonde_Blazer":"50","bloney":"23"}'));
    expect(raw.map((r) => (r as TagSuggestion).tag), ['Blonde_Blazer', 'bloney']);
    // A Cloudflare page is a failure, not "no tags": an empty list would be recorded as an alias miss (review).
    expect(() => h().parseTagSuggestionsList(resp('<html>challenge</html>')), throwsFormatException);
  });

  test('login: both credential fields are offered (the site login reads them); the signed-in check ignores saved defaults', () {
    final R34HentaiHandler handler = h();
    expect(handler.hasSignInSupport, isTrue);
    expect(handler.usesUserId, isTrue);
    expect(handler.usesApiKey, isTrue);
    expect(handler.userIdLabel, 'Username');
    expect(handler.apiKeyLabel, 'Password');
  });
}
