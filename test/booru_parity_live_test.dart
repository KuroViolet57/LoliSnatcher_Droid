@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_on_rails_handler.dart';
import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/e621_handler.dart';
import 'package:lolisnatcher/src/boorus/kusowanka_handler.dart';
import 'package:lolisnatcher/src/boorus/moebooru_handler.dart';
import 'package:lolisnatcher/src/boorus/philomena_handler.dart';
import 'package:lolisnatcher/src/boorus/realbooru_handler.dart';
import 'package:lolisnatcher/src/boorus/redgifs_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/comment_item.dart';
import 'package:lolisnatcher/src/data/note_item.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// r71 booru parity sweep against the LIVE sites, anonymous - a report run,
/// not part of the offline suite.
///
///   flutter test test/booru_parity_live_test.dart --run-skipped --tags live
void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  final SettingsHandler settingsHandler = SettingsHandler.register();
  await settingsHandler.initialize();
  settingsHandler
    ..tagTypeFetchEnabled = false
    ..itemLimit = 25;
  ViewerHandler.register();
  NavigationHandler.register();
  TagHandler.register();
  Logger.Inst();

  Booru of(BooruType type, String url) => Booru(type.name, type, '', url, '');

  test('yande.re: comments, notes and order:score', () async {
    // Page numbers are seeded the way the app does it (BooruHandlerFactory: 1-based sites start at 1).
    final MoebooruHandler h = MoebooruHandler(of(BooruType.Moebooru, 'https://yande.re'), 25)..pageNum = 1;
    final List<CommentItem> comments = await h.getComments('1000000', 0);
    debugPrint('yande.re comments: ${comments.length}, first "${comments.firstOrNull?.authorName}: ${comments.firstOrNull?.content}"');
    expect(comments, isNotEmpty);
    final List<NoteItem> notes = await h.getNotes('1246878');
    debugPrint('yande.re notes: ${notes.length}, first "${notes.firstOrNull?.content}" at ${notes.firstOrNull?.posX},${notes.firstOrNull?.posY}');
    expect(notes, isNotEmpty);
    final List<BooruItem> byScore = List<BooruItem>.from(await h.search('order:score', null));
    debugPrint('yande.re order:score: ${byScore.length}, scores ${byScore.take(3).map((i) => i.score).join(',')}');
    expect(byScore, isNotEmpty);
    expect(int.parse(byScore.first.score ?? '0'), greaterThan(100));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('e621: comments', () async {
    final e621Handler h = e621Handler(of(BooruType.e621, 'https://e621.net'), 25);
    final List<CommentItem> comments = await h.getComments('5000000', 0);
    debugPrint('e621 comments: ${comments.length}, first "${comments.firstOrNull?.authorName}"');
    expect(comments, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('derpibooru: comments', () async {
    final PhilomenaHandler h = PhilomenaHandler(of(BooruType.Philomena, 'https://derpibooru.org'), 25);
    final List<CommentItem> comments = await h.getComments('1', 0);
    final List<CommentItem> second = await h.getComments('1', 1);
    debugPrint('derpibooru comments page 2: ${second.length}, first id ${second.firstOrNull?.id} (page 1 first id ${comments.firstOrNull?.id})');
    expect(second, isNotEmpty);
    expect(second.first.id, isNot(comments.first.id), reason: 'page 2 must differ from page 1');
    debugPrint('derpibooru comments: ${comments.length}, first "${comments.firstOrNull?.authorName}"');
    expect(comments, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('twibooru: comments and a score sort', () async {
    final BooruOnRailsHandler h = BooruOnRailsHandler(of(BooruType.BooruOnRails, 'https://twibooru.org'), 25)..pageNum = 1;
    final List<CommentItem> comments = await h.getComments('3408660', 0);
    debugPrint('twibooru comments: ${comments.length}, first "${comments.firstOrNull?.content}"');
    expect(comments, isNotEmpty);
    final List<BooruItem> byScore = List<BooruItem>.from(await h.search('sf:score', null));
    debugPrint('twibooru sf:score: ${byScore.length}, scores ${byScore.take(3).map((i) => i.score).join(',')}, error "${h.errorString}"');
    expect(byScore, isNotEmpty);
    expect(int.parse(byScore.first.score ?? '0'), greaterThanOrEqualTo(int.parse(byScore[1].score ?? '0')));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('kusowanka: the popular and random shelves', () async {
    final KusowankaHandler h = KusowankaHandler(of(BooruType.Kusowanka, 'https://kusowanka.com'), 25);
    final List<BooruItem> popular = List<BooruItem>.from(await h.search('sort:popular', null));
    debugPrint('kusowanka popular: ${popular.length}, error "${h.errorString}"');
    expect(popular.length, greaterThan(30));
    final KusowankaHandler r = KusowankaHandler(of(BooruType.Kusowanka, 'https://kusowanka.com'), 25);
    final List<BooruItem> random = List<BooruItem>.from(await r.search('sort:random', null));
    debugPrint('kusowanka random: ${random.length}');
    expect(random, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('redgifs: images only', () async {
    final RedGifsHandler h = RedGifsHandler(of(BooruType.RedGifs, 'https://www.redgifs.com'), 25)..pageNum = 1;
    debugPrint('redgifs url: ${h.makeURL('blonde type:images')}');
    final List<BooruItem> images = List<BooruItem>.from(await h.search('blonde type:images', null));
    debugPrint('redgifs images: ${images.length}, first ${images.firstOrNull?.fileURL}, error "${h.errorString}"');
    expect(images, isNotEmpty);
    expect(images.every((i) => i.fileURL.contains('.jpg') || i.fileURL.contains('.jpeg') || i.fileURL.contains('.png')), isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('realbooru: sort:id:asc starts from the oldest posts', () async {
    final RealbooruHandler h = RealbooruHandler(of(BooruType.Realbooru, 'https://realbooru.com'), 25)..pageNum = 0;
    final List<BooruItem> oldest = List<BooruItem>.from(await h.search('blonde sort:id:asc', null));
    // The HTML list parser leaves serverId empty; the id sits in the post url.
    int idOf(BooruItem i) => int.tryParse(RegExp(r'id=(\d+)').firstMatch(i.postURL)?.group(1) ?? '') ?? 999999;
    debugPrint('realbooru sort:id:asc: ${oldest.length}, first id ${oldest.firstOrNull == null ? null : idOf(oldest.first)}, error "${h.errorString}"');
    expect(oldest, isNotEmpty);
    expect(idOf(oldest.first), lessThan(10000));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
