@Tags(['live'])
library;

import 'dart:io';

import 'package:alice_lightweight/alice.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/furaffinity_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';

/// r40, live: the real site, logged out (general content only).
///
///   flutter test test/furaffinity_live_test.dart --run-skipped --tags live
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late Directory tempDir;
  final Booru fa = Booru('FurAffinity', BooruType.FurAffinity, '', 'https://www.furaffinity.net', '');

  setUp(() {
    SettingsHandler.register();
    TagHandler.register();
    tempDir = Directory.systemTemp.createTempSync('furaffinity_live');
    SettingsHandler.instance
      ..path = '${tempDir.path}${Platform.pathSeparator}'
      ..alice = Alice();
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('browse, a search and its page 2, a gallery, and one submission opened', () async {
    final FurAffinityHandler browse = FurAffinityHandler(fa, 48);
    final List items = await browse.search('', null) as List;
    // ignore: avoid_print
    print('browse: ${items.length} ${browse.errorString}');
    expect(items, isNotEmpty);

    final FurAffinityHandler search = FurAffinityHandler(fa, 48);
    final List p1 = List.of(await search.search('fox', null) as List);
    final List p2 = List.of(await search.search('fox', null) as List);
    // ignore: avoid_print
    print('search: page 1 ${p1.length}, after page 2 ${p2.length} ${search.errorString}');
    expect(p2.length, greaterThan(p1.length));

    final FurAffinityHandler gallery = FurAffinityHandler(fa, 48);
    final List g = await gallery.search('user:ryan-the-fox', null) as List;
    expect(g, isNotEmpty);

    final BooruItem first = items.first as BooruItem;
    final res = await browse.loadItem(item: first);
    // ignore: avoid_print
    print('opened ${first.postURL}: failed=${res.failed} ${res.error} file=${first.fileURL} type=${first.mediaType.value}');
    expect(res.failed, isFalse);
    expect(first.fileURL, contains('d.furaffinity.net'));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
