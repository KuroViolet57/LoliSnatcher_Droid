@Tags(['live'])
library;

import 'dart:io';

import 'package:alice_lightweight/alice.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/e621_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_index_source.dart';

/// r44, live: a contributor search on e621 comes back with the contributors
/// typed, the tag builder's Contributors page lists modelers, and a filter
/// term from the cheatsheet narrows the results.
///
///   flutter test test/e621_live_test.dart --run-skipped --tags live
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late Directory tempDir;
  final Booru e621 = Booru('e621', BooruType.e621, '', 'https://e621.net', '');

  setUp(() {
    SettingsHandler.register();
    TagHandler.register();
    tempDir = Directory.systemTemp.createTempSync('e621_live');
    SettingsHandler.instance
      ..path = '${tempDir.path}${Platform.pathSeparator}'
      ..alice = Alice();
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('contributors are typed, listed by the tag builder, and filters narrow a search', () async {
    // The app advances the page before a search (the factory starts e621 at 0); e621 answers page=0 with 410 Gone.
    final e621Handler h = e621Handler(e621, 20)..pageNum = 1;
    final List items = await h.search('mayosplash_(modeler) rating:e type:webm', null) as List;
    // ignore: avoid_print
    print('search: ${items.length} ${h.errorString}');
    expect(items, isNotEmpty);
    final BooruItem first = items.first as BooruItem;
    expect(first.fileExt, 'webm');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(TagHandler.instance.getTag('mayosplash_(modeler)').tagType, TagType.contributor);

    final page = await const E621TagIndex().categoryPageAt(e621, TagType.contributor, 0);
    // ignore: avoid_print
    print('contributors page 1: ${page.length}, first ${page.isEmpty ? '-' : page.first.name}');
    expect(page, isNotEmpty);
    expect(page.every((e) => e.tagType == TagType.contributor), isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
