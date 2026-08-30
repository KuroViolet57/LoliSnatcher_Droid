import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/asmhentai_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/doujin_listing_tag_backfill.dart';
import 'package:lolisnatcher/src/boorus/doujin/eahentai_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/faccina_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/hitomi_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/schale_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// Round 4: three of the six doujin sources list covers and titles but no
/// tags. Without a backfill their grid cards would carry an empty tag strip
/// AND — because the per-source blacklist, the tag stars and the hidden/marked
/// checks all read `tagsList` — none of those could act on a card until it had
/// been opened once.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('backfill_test');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
  });

  tearDown(() {
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  BooruItem item(String id, {List<Tag> tags = const []}) => BooruItem(
    fileURL: 'https://example.test/$id.jpg',
    sampleURL: 'https://example.test/$id.jpg',
    thumbnailURL: 'https://example.test/$id.jpg',
    tagsList: tags,
    postURL: 'https://example.test/g/$id',
    serverId: id,
  );

  test('cards without tags get them, and the grid is told to repaint', () async {
    final handler = _FakeBackfillHandler();
    final items = [item('1'), item('2'), item('3')];

    await handler.run(items);

    expect(items.every((e) => e.tagsList.isNotEmpty), isTrue);
    expect(handler.requested..sort(), ['1', '2', '3']);
    expect(handler.filteredFetched.length, 3);
  });

  test('a card that already has tags is left alone', () async {
    final handler = _FakeBackfillHandler();
    final existing = item('1', tags: [Tag('kept')]);

    await handler.run([existing, item('2')]);

    expect(handler.requested, ['2']);
    expect(existing.tagsList.single.fullString, 'kept');
  });

  test('the same gallery is only fetched once across pages', () async {
    final handler = _FakeBackfillHandler();

    await handler.run([item('1')]);
    final second = item('1');
    await handler.run([second]);

    expect(handler.requested, ['1']);
    expect(second.tagsList, isNotEmpty);
  });

  test('a source that cannot supply tags costs one empty strip, not an error', () async {
    final handler = _FakeBackfillHandler(failOn: {'2'});

    final items = [item('1'), item('2')];
    await handler.run(items);

    expect(items[0].tagsList, isNotEmpty);
    expect(items[1].tagsList, isEmpty);
  });

  test('a backfill from an abandoned query does not write into the new one', () async {
    final handler = _FakeBackfillHandler(gate: true);
    final stale = item('1');

    final first = handler.run([stale]);
    await Future<void>.delayed(Duration.zero);

    // A new search starts before the first backfill has answered.
    handler.gate = false;
    final fresh = item('9');
    await handler.run([fresh]);

    handler.release();
    await first;

    expect(fresh.tagsList, isNotEmpty);
    expect(stale.tagsList, isEmpty);
  });

  group('which sources need it', () {
    test('the three tag-less listings mix it in', () {
      expect(SchaleHandler(Booru('n', BooruType.NiyaNiya, '', 'https://niyaniya.moe', ''), 20),
          isA<DoujinListingTagBackfill>());
      expect(AsmHentaiHandler(Booru('a', BooruType.AsmHentai, '', 'https://asmhentai.com', ''), 20),
          isA<DoujinListingTagBackfill>());
      expect(EaHentaiHandler(Booru('e', BooruType.EaHentai, '', 'https://eahentai.com', ''), 20),
          isA<DoujinListingTagBackfill>());
    });

    test('sources whose listings already carry tags do not', () {
      // hentalk's /api/library and hitomi's galleryinfo both return tags with
      // the listing, so a backfill would be pure extra traffic.
      expect(FaccinaHandler(Booru('h', BooruType.Faccina, '', 'https://hentalk.pw', ''), 20),
          isNot(isA<DoujinListingTagBackfill>()));
      expect(HitomiHandler(Booru('h', BooruType.Hitomi, '', 'https://hitomi.la', ''), 20),
          isNot(isA<DoujinListingTagBackfill>()));
    });
  });
}

class _FakeBackfillHandler extends BooruHandler with DoujinListingTagBackfill {
  _FakeBackfillHandler({this.failOn = const {}, this.gate = false})
      : super(Booru('fake', BooruType.NiyaNiya, '', 'https://example.test', ''), 20);

  final Set<String> failOn;
  bool gate;
  final List<String> requested = [];
  final List<void Function()> _gates = [];

  void release() {
    for (final open in _gates) {
      open();
    }
    _gates.clear();
  }

  /// What the mixin does inside [afterParseResponse], minus the base class's
  /// database round trips.
  Future<void> run(List<BooruItem> items) async {
    fetched.addAll(items);
    filterFetched();
    await backfillForTests(items);
  }

  @override
  Future<List<Tag>> tagsForListingItem(BooruItem item) async {
    final String id = item.serverId!;
    requested.add(id);
    if (gate) {
      final completer = Completer<void>();
      _gates.add(completer.complete);
      await completer.future;
    }
    if (failOn.contains(id)) throw StateError('no tags for $id');
    return [Tag('fetched_$id')];
  }
}
