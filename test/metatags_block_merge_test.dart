import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/eahentai_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/hitomi_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/schale_handler.dart';
import 'package:lolisnatcher/src/boorus/kemono_handler.dart';
import 'package:lolisnatcher/src/boorus/nhentai_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/widgets/preview/main_search_query_editor_page.dart';

/// The Metatags card's chip row with the tag builder merged in: a builder
/// chip stands in for the metatag with the same key, plain metatags stay
/// where they are, and list-only namespaces come last.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  Booru b(String name, BooruType type, String url) => Booru(name, type, '', url, '');

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('metatags');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  List<String> labels(BooruHandler h) => [
    for (final e in MetatagsBlock.mergedEntries(h.availableMetaTags(), h.tagCatalog))
      e is TagCatalogNamespace ? '[${e.label}]' : (e as MetaTag).name,
  ];

  test('niyaniya: builder chips replace their metatags in place, list-only ones follow', () {
    final h = SchaleHandler(b('n', BooruType.NiyaNiya, 'https://niyaniya.moe'), 20);
    expect(labels(h), ['[Artists]', '[Circles]', 'Series', 'Magazine', '[Female]', '[Male]', 'Language', '[Mixed]', '[Tags]']);
  });

  test('nhentai: nothing to replace, every builder chip is appended', () {
    final h = NHentaiHandler(b('n', BooruType.NHentai, 'https://nhentai.net'), 20);
    final got = labels(h);
    expect(got.where((l) => l.startsWith('[')).toList(), ['[Parodies]', '[Characters]', '[Artists]', '[Groups]', '[Tags]']);
    expect(got.indexOf('[Parodies]'), greaterThan(got.indexWhere((l) => !l.startsWith('['))));
  });

  test('hitomi: a key on both sides appears once, as the builder chip', () {
    final h = HitomiHandler(b('h', BooruType.Hitomi, 'https://hitomi.la'), 20);
    final got = labels(h);
    expect(got.where((l) => l == '[Languages]').length, 1);
    expect(got.where((l) => l == '[Types]').length, 1);
    expect(got, isNot(contains('Language')));
    expect(got, isNot(contains('Type')));
  });

  test('a source with no catalog keeps its plain metatag row', () {
    final h = EaHentaiHandler(b('e', BooruType.EaHentai, 'https://eahentai.com'), 20);
    expect(labels(h), ['Artist', 'Series', 'Character']);
  });

  test('kemono: Artists and Tags builder chips stand in for Creator and Tag; the rest stay plain', () {
    final h = KemonoHandler(b('k', BooruType.Kemono, 'https://kemono.cr'), 50);
    expect(labels(h), ['[Artists]', '[Tags]', 'Service (filters on the phone)', 'Popular', 'Favorites', 'Post id']);
  });

  test('pawchive: no tag list and no popular feed, so Tag stays plain and Popular is gone', () {
    final h = KemonoHandler(b('p', BooruType.Pawchive, 'https://pawchive.pw'), 50);
    expect(labels(h), ['[Artists]', 'Tag', 'Service (filters on the phone)', 'Favorites', 'Post id']);
  });
}
