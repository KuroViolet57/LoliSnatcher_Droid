@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:alice_lightweight/alice.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_catalog_source.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_index_source.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// The tag builder's first page from each booru family, fetched from the
/// LIVE sites — a report run, not part of the offline suite (see
/// dart_test.yaml). A red row can mean this machine cannot reach the site
/// (danbooru's Cloudflare challenges plain clients) rather than a broken
/// walk; read the printed lines.
///
///   flutter test test/tag_index_live_test.dart --run-skipped --tags live
void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test answers every HTTP request with an empty 400 unless the
  // mock overrides are removed; this file wants the real sites.
  HttpOverrides.global = null;

  final SettingsHandler settingsHandler = SettingsHandler.register();
  await settingsHandler.initialize();
  settingsHandler
    ..tagTypeFetchEnabled = false
    ..itemLimit = 20
    ..alice = Alice();
  ViewerHandler.register();
  NavigationHandler.register();
  TagHandler.register();
  Logger.Inst();
  TagIndexSource.resetForTests();

  Booru b(String name, BooruType type, String url) => Booru(name, type, '', url, '');

  Future<List<BooruTagEntry>> page(Booru booru, String namespace) async {
    final BooruHandler handler = BooruHandlerFactory().getBooruHandler([booru], null).booruHandler;
    final TagCatalogSource catalog = handler.tagCatalog!;
    final rows = await catalog.shardAt(namespace, 0) ?? const [];
    debugPrint(
      '${booru.name} ${namespace.isEmpty ? 'index' : namespace}: ${rows.length} rows, '
      'first ${rows.take(3).map((r) => '${r.name}(${r.tagType.name},${r.count})').join(' ')}',
    );
    return rows;
  }

  test('rule34.xxx: the shared list, most-used first', () async {
    final rows = await page(b('rule34', BooruType.GelbooruAlike, 'https://rule34.xxx'), '');
    expect(rows.length, greaterThanOrEqualTo(15));
    expect(rows.first.count, greaterThan(rows.last.count));
  });

  test('gelbooru.com: its own row markup', () async {
    final rows = await page(b('gelbooru', BooruType.Gelbooru, 'https://gelbooru.com'), '');
    expect(rows.map((r) => r.name), contains('1girl'));
    expect(rows.map((r) => r.name), isNot(contains('')));
  });

  test('realbooru: fifty rows with models as artists', () async {
    final rows = await page(b('realbooru', BooruType.Realbooru, 'https://realbooru.com'), '');
    expect(rows.length, greaterThanOrEqualTo(40));
    expect(rows.where((r) => r.tagType == TagType.artist), isNotEmpty);
  });

  test('e621: one category, 320 a page', () async {
    final rows = await page(b('e621', BooruType.e621, 'https://e621.net'), 'artist');
    expect(rows.length, 320);
    expect(rows.every((r) => r.tagType == TagType.artist), isTrue);
  });

  test('derpibooru: artists by name, characters by category', () async {
    final booru = b('derpibooru', BooruType.Philomena, 'https://derpibooru.org');
    final artists = await page(booru, 'artist');
    expect(artists.length, 50);
    expect(artists.every((r) => r.name.startsWith('artist:') && r.tagType == TagType.artist), isTrue);
    final characters = await page(booru, 'character');
    expect(characters.length, 50);
    expect(characters.every((r) => r.tagType == TagType.character && !r.name.contains(' ')), isTrue);
  });

  test('yande.re: tag.json by type, 500 a page', () async {
    final rows = await page(b('yandere', BooruType.Moebooru, 'https://yande.re'), 'artist');
    expect(rows.length, 500);
    expect(rows.every((r) => r.tagType == TagType.artist), isTrue);
  });

  test('sankaku: the API host, 1000 a page', () async {
    final rows = await page(b('sankaku', BooruType.Sankaku, 'https://chan.sankakucomplex.com'), 'artist');
    expect(rows.length, 1000);
    expect(rows.every((r) => r.tagType == TagType.artist), isTrue);
  });

  test('danbooru: category filter (Cloudflare may refuse this machine)', () async {
    final rows = await page(b('danbooru', BooruType.Danbooru, 'https://danbooru.donmai.us'), 'artist');
    expect(rows.length, 1000);
    expect(rows.every((r) => r.tagType == TagType.artist), isTrue);
  });
}
