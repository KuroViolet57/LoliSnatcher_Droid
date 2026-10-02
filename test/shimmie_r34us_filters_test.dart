import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/doujin_filters.dart';
import 'package:lolisnatcher/src/boorus/r34us_handler.dart';
import 'package:lolisnatcher/src/boorus/shimmie_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/widgets/preview/main_search_query_editor_page.dart';

/// r47: the last sources with search options. rule34.paheal (Shimmie) writes
/// some terms with `=` and `>` (`ext=webm`, `score>10`), so a filter group
/// carries its divider. Checked live on 2026-09-15: on paheal "cat" gave 81
/// posts, `content:video` 14, `ext=webm` 1, `score>10` 16 (`order:score_desc`
/// changed nothing, so no sort); on rule34.us `sort:score` and `score:>10`
/// changed the results, `rating:explicit` did not.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  Booru b(String name, BooruType type, String url) => Booru(name, type, '', url, '');
  List<String> values(DoujinFilterSpec spec, String key) => spec.group(key)!.options.map((o) => o.value).toList();

  setUp(() {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('shimmie_r34us');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
  });

  tearDown(() {
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a filter term can use = or > instead of :', () {
    expect(DoujinFilters.selected('cat ext=webm', 'ext', divider: '='), ['webm']);
    expect(DoujinFilters.selected('cat score>10', 'score', divider: '>'), ['10']);
    expect(DoujinFilters.selected('cat ext:webm', 'ext', divider: '='), isEmpty, reason: 'a different divider is a different term');
    expect(DoujinFilters.apply('cat', 'ext', ['webm'], divider: '='), 'cat ext=webm');
    expect(DoujinFilters.apply('cat ext=webm score>10', 'ext', const [], divider: '='), 'cat score>10');
    expect(DoujinFilters.apply('cat', 'rating', ['e']), 'cat rating:e', reason: 'the colon stays the default');
  });

  test('paheal: content, file type and score, each in its own divider; saved defaults compose the same way', () {
    final ShimmieHtmlHandler h = ShimmieHtmlHandler(b('rule34paheal', BooruType.Shimmie, 'https://rule34.paheal.net'), 20);
    final DoujinFilterSpec spec = h.siteFilters!;
    expect(spec.groups.map((g) => g.key), containsAll(['content', 'ext', 'score']));
    expect(spec.group('content')!.divider, ':');
    expect(spec.group('ext')!.divider, '=');
    expect(spec.group('score')!.divider, '>');
    expect(values(spec, 'content'), ['', 'video', 'audio']);
    expect(values(spec, 'ext'), containsAll(['webm', 'mp4', 'gif']));
    expect(spec.group('sort'), isNull, reason: 'order:score_desc changed nothing on the site');
    expect(SourceSettingsHandler.composeQuery(query: 'cat', spec: spec, defaultFilters: 'ext=webm score>10'), 'cat ext=webm score>10');
    expect(SourceSettingsHandler.composeQuery(query: 'cat ext=mp4', spec: spec, defaultFilters: 'ext=webm'), 'cat ext=mp4');
    expect(SourceSettingsHandler.withDefaults(spec, 'ext=webm').group('ext')!.defaultValue, 'webm');
  });

  test('rule34.us: sort and score; no rating (it changed nothing)', () {
    final DoujinFilterSpec spec = R34USHandler(b('Rule34Us', BooruType.R34US, 'https://rule34.us'), 20).siteFilters!;
    expect(values(spec, 'sort'), ['', 'score']);
    expect(values(spec, 'score'), containsAll(['>10', '>50', '>100']));
    expect(spec.group('rating'), isNull);
  });

  testWidgets('a paheal chip writes its own divider', (tester) async {
    String query = 'cat';
    final DoujinFilterSpec spec = ShimmieHtmlHandler(b('rule34paheal', BooruType.Shimmie, 'https://rule34.paheal.net'), 20).siteFilters!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: DoujinFiltersBlock(spec: spec, query: query, onQueryChanged: (q) => setState(() => query = q)),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('doujin-filter-ext-webm')));
    await tester.pump();
    expect(query, 'cat ext=webm');
    expect(tester.widget<FilterChip>(find.byKey(const ValueKey('doujin-filter-ext-webm'))).selected, isTrue);
  });
}
