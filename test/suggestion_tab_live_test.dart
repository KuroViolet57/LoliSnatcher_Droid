@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:alice_lightweight/alice.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/suggestion_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/suggestion_engine.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// r76 (build 96), live: the post from the user's screenshot (taanukic,
/// meow_skulls, wild_card) read from e621's API, its suggestion query built,
/// a tab made from that query, and one page asked of e621 through the same
/// loader the strip uses.
///
///   flutter test test/suggestion_tab_live_test.dart --run-skipped --tags live
void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late Directory tempDir;
  final Booru e621 = Booru('e621', BooruType.e621, '', 'https://e621.net', '');

  setUp(() {
    final SettingsHandler settings = SettingsHandler.register();
    ViewerHandler.register();
    NavigationHandler.register();
    TagHandler.register();
    SearchHandler.register();
    tempDir = Directory.systemTemp.createTempSync('suggestion_live');
    settings
      ..path = '${tempDir.path}${Platform.pathSeparator}'
      ..alice = Alice()
      ..dbEnabled = false;
    settings.booruList.value = [e621];
  });
  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a suggestion tab for the screenshot post fills from e621 with posts that share its facets', () async {
    final HttpClient client = HttpClient()..userAgent = 'LoliSnatcher/2.6 (by KuroViolet57)';
    final HttpClientRequest req = await client.getUrl(Uri.parse('https://e621.net/posts.json?limit=1&tags=taanukic%20meow_skulls%20wild_card'));
    final HttpClientResponse res = await req.close();
    final Map<String, dynamic> body = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
    client.close();
    final Map<String, dynamic> p = (body['posts'] as List).first as Map<String, dynamic>;
    final Map<String, dynamic> t = p['tags'] as Map<String, dynamic>;
    List<Tag> typed(String key, TagType type) => [for (final dynamic n in (t[key] as List? ?? const [])) Tag(n.toString(), tagType: type)];
    final BooruItem post = BooruItem(
      fileURL: (p['file'] as Map)['url']?.toString() ?? 'https://e621.net/posts/${p['id']}',
      sampleURL: '',
      thumbnailURL: '',
      tagsList: [
        ...typed('character', TagType.character),
        ...typed('copyright', TagType.copyright),
        ...typed('artist', TagType.artist),
        ...typed('species', TagType.species),
        ...typed('general', TagType.none),
      ],
      postURL: 'https://e621.net/posts/${p['id']}',
    );
    final String q = SuggestionHandler.queryFor(post);
    // ignore: avoid_print
    print('post ${p['id']} query: ${q.length > 200 ? '${q.substring(0, 200)}…' : q}');
    final SearchTab tab = SearchTab(e621, null, q);
    expect(tab.booruHandler, isA<SuggestionHandler>());
    final List items = await tab.booruHandler.search(q, null) as List;
    final Set<String> facetTerms = {
      for (final f in SuggestionEngine.facetsForItem((tab.booruHandler as SuggestionHandler).sourceItem)) ...f.query.split(' '),
    };
    // ignore: avoid_print
    print('suggestion tab: ${items.length} posts; facets: $facetTerms; error "${tab.booruHandler.errorString}"');
    expect(items, isNotEmpty, reason: tab.booruHandler.errorString);
    int sharing = 0;
    for (final dynamic i in items) {
      final Set<String> tags = {for (final Tag tag in (i as BooruItem).tagsList) tag.fullString};
      if (facetTerms.any(tags.contains)) sharing++;
    }
    // ignore: avoid_print
    print('$sharing of ${items.length} carry one of the facet tags');
    expect(sharing, items.length, reason: 'every suggestion came from one of the post\'s facets');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
