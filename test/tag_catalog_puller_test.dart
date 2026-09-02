import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_puller.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';

/// A source with in-memory shards; one shard can be made to throw.
class _Fake extends TagCatalogSource {
  _Fake({this.shared = false, this.total, this.failAt, this.perShard = 3, this.open = false});

  final bool shared;
  final int? total;
  final int? failAt;
  final int perShard;
  final bool open;
  final List<(String, int)> asked = [];

  @override
  bool get sharedShards => shared;

  @override
  int? get sharedShardCount => total;

  @override
  Duration get shardDelay => Duration.zero;

  @override
  List<TagCatalogNamespace> get namespaces => [
    TagCatalogNamespace(key: 'artist', label: 'Artists', type: TagType.artist, shards: open ? null : total, maxShards: open ? 4 : null),
    const TagCatalogNamespace(key: 'tag', label: 'Tags', type: TagType.none),
  ];

  @override
  Future<List<BooruTagEntry>?> shardAt(String namespace, int shard) async {
    asked.add((namespace, shard));
    if (failAt == shard) throw Exception('rate limited');
    if (open && shard >= 6) return null;
    return [
      for (int i = 0; i < perShard; i++)
        BooruTagEntry(name: 's${shard}_$i', namespace: shared ? (i.isEven ? 'artist' : 'tag') : namespace, tagType: TagType.none),
    ];
  }
}

void main() {
  final Booru booru = Booru('h', BooruType.Hitomi, '', 'https://hitomi.la', '');
  final puller = TagCatalogPuller.instance;
  late List<BooruTagEntry> written;

  setUp(() {
    written = [];
    puller.recordFn = (b, entries) async {
      written.addAll(entries);
      return entries.length;
    };
  });

  test('walks every known shard, stores each, and reports done', () async {
    final fake = _Fake(total: 3);
    puller.resetResume(booru, fake, 'artist');
    await puller.pull(booru, fake, 'artist');
    final state = puller.stateFor(booru, fake, 'artist').value;
    expect(fake.asked, [('artist', 0), ('artist', 1), ('artist', 2)]);
    expect(written.length, 9);
    expect(state.done, isTrue);
    expect(state.running, isFalse);
    expect(state.stored, 9);
    expect(state.progress, 1);
  });

  test('a failing shard keeps what was stored and resumes from there', () async {
    final fake = _Fake(total: 4, failAt: 2);
    puller.resetResume(booru, fake, 'artist');
    await puller.pull(booru, fake, 'artist');
    var state = puller.stateFor(booru, fake, 'artist').value;
    expect(state.error, contains('rate limited'));
    expect(state.done, isFalse);
    expect(written.length, 6);

    final again = _Fake(total: 4);
    await puller.pull(booru, again, 'artist');
    expect(again.asked.first, ('artist', 2), reason: 'resumes at the failed shard');
    state = puller.stateFor(booru, again, 'artist').value;
    expect(state.done, isTrue);
  });

  test('an open-ended walk stops at the cap, then at the end', () async {
    final fake = _Fake(open: true);
    puller.resetResume(booru, fake, 'artist');
    await puller.pull(booru, fake, 'artist');
    expect(fake.asked.length, 4, reason: 'maxShards 4 per pull');
    expect(puller.stateFor(booru, fake, 'artist').value.done, isFalse);
    final more = _Fake(open: true);
    await puller.pull(booru, more, 'artist');
    expect(more.asked.map((a) => a.$2).toList(), [4, 5, 6]);
    expect(puller.stateFor(booru, more, 'artist').value.done, isTrue, reason: 'shard 6 answered null');
  });

  test('a shared source runs one job that every namespace mirrors', () async {
    final fake = _Fake(shared: true, total: 2);
    puller.resetResume(booru, fake, 'artist');
    await puller.pull(booru, fake, 'tag');
    expect(fake.asked, [('', 0), ('', 1)]);
    expect(identical(puller.stateFor(booru, fake, 'artist'), puller.stateFor(booru, fake, 'tag')), isTrue);
    expect(written.map((e) => e.namespace).toSet(), {'artist', 'tag'});
  });

  test('cancel stops the walk and keeps the resume point', () async {
    final fake = _Fake(total: 50);
    puller.resetResume(booru, fake, 'tag');
    // Cancel from inside the first shard by hooking the record function.
    puller.recordFn = (b, entries) async {
      puller.cancel(booru, fake, 'tag');
      return entries.length;
    };
    await puller.pull(booru, fake, 'tag');
    final state = puller.stateFor(booru, fake, 'tag').value;
    expect(fake.asked.length, 1);
    expect(state.running, isFalse);
    expect(state.done, isFalse);
  });
}
