@Tags(['live'])
library;

import 'dart:io';

import 'package:alice_lightweight/alice.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/doujin/asmhentai_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/eahentai_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/faccina_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/hitomi_handler.dart';
import 'package:lolisnatcher/src/boorus/doujin/schale_handler.dart';
import 'package:lolisnatcher/src/boorus/nhentai_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// The per-source parity walk, against the live sites.
///
/// nhentai is the reference: it is the source every doujin feature was built
/// on. Every other doujin source is supposed to have the same feature set, and
/// the promise has been made twice without being properly checked. This walks
/// each one and prints a row per capability so a gap is named rather than
/// averaged away.
///
/// It is deliberately a REPORT, not a pass/fail gate: several of these sites
/// block datacenter IPs, and a red row for "this machine cannot reach the site"
/// is a different fact from "the handler is broken". Both are printed.
///
/// Run with:
///   flutter test test/doujin_parity_walk_test.dart --run-skipped --tags live
///
/// Skipped in the normal suite (see dart_test.yaml): it takes minutes and
/// depends on six third-party sites being up and reachable.
void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  final SettingsHandler settingsHandler = SettingsHandler.register();
  await settingsHandler.initialize();
  settingsHandler
    ..tagTypeFetchEnabled = false
    ..itemLimit = 20
    ..alice = Alice();
  ViewerHandler.register();
  TagHandler.register();
  Logger.Inst();

  final Map<String, Map<String, String>> report = {};

  void note(String source, String capability, String verdict) {
    (report[source] ??= {})[capability] = verdict;
  }

  /// Runs one check and records what it found, never throwing.
  Future<void> check(
    String source,
    String capability,
    Future<String> Function() body,
  ) async {
    try {
      note(source, capability, await body());
    } catch (e) {
      note(source, capability, 'ERROR  ${e.toString().split('\n').first}');
    }
  }

  Future<void> walk(String source, BooruHandler handler) async {
    // 1. the feed
    List<BooruItem> feed = const [];
    await check(source, 'feed', () async {
      handler.pageNum = 1;
      feed = await handler.search('', handler.pageNum);
      if (feed.isEmpty) {
        return 'BROKEN  empty${handler.errorString.isNotEmpty ? ' (${handler.errorString})' : ''}';
      }
      return 'ok      ${feed.length} items';
    });

    if (feed.isEmpty) {
      for (final cap in ['covers', 'titles', 'tags', 'namespaces', 'detail', 'related', 'recommended', 'reader']) {
        note(source, cap, 'skipped (no feed)');
      }
      return;
    }

    await check(source, 'covers', () async {
      final int withCover = feed.where((e) => e.thumbnailURL.isNotEmpty).length;
      return withCover == feed.length ? 'ok      all $withCover' : 'PARTIAL $withCover/${feed.length}';
    });

    await check(source, 'titles', () async {
      final int withTitle = feed.where((e) => e.description?.trim().isNotEmpty == true).length;
      return withTitle == feed.length ? 'ok      all $withTitle' : 'PARTIAL $withTitle/${feed.length}';
    });

    // Tags can arrive with the listing or be backfilled just after it.
    await check(source, 'tags', () async {
      for (int i = 0; i < 20 && feed.where((e) => e.tagsList.isNotEmpty).isEmpty; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
      final int tagged = feed.where((e) => e.tagsList.isNotEmpty).length;
      if (tagged == 0) return 'BROKEN  no tags on any item';
      return tagged == feed.length ? 'ok      all $tagged' : 'PARTIAL $tagged/${feed.length}';
    });

    await check(source, 'namespaces', () async {
      final Map<String, int> seen = {};
      for (final item in feed) {
        for (final Tag tag in item.tagsList) {
          if (tag.fullString.contains(':')) return 'BROKEN  raw prefix in name: ${tag.fullString}';
          final String? ns = handler.tagNamespace(tag.fullString);
          if (ns != null && ns.isNotEmpty) seen[ns] = (seen[ns] ?? 0) + 1;
        }
      }
      if (seen.isEmpty) return 'BROKEN  no namespaces mapped';
      final sorted = seen.keys.toList()..sort();
      return 'ok      ${sorted.join(', ')}';
    });

    // 2. the detail page
    final BooruItem first = feed.first;
    await check(source, 'detail', () async {
      handler.pageNum = 1;
      final List<BooruItem> got = await handler.search('id:${_idOf(first, handler)}', 1);
      if (got.isEmpty) return 'BROKEN  id: returned nothing';
      return 'ok      ${got.first.description}';
    });

    // 3. the strips
    await check(source, 'related', () async {
      handler.pageNum = 1;
      final List<BooruItem> got = await handler.search('related:${_idOf(first, handler)}', 1);
      return got.isEmpty ? 'BROKEN  empty' : 'ok      ${got.length}';
    });

    await check(source, 'recommended', () async {
      handler.pageNum = 1;
      final List<BooruItem> got = await handler.search('recommend:${_idOf(first, handler)}', 1);
      return got.isEmpty ? 'BROKEN  empty' : 'ok      ${got.length}';
    });

    // 4. the media actually loads, per host
    await check(source, 'cover fetch', () async {
      final resp = await DioNetwork.head(
        first.thumbnailURL,
        headers: handler.getMediaHeaders(),
      );
      final String host = Uri.tryParse(first.thumbnailURL)?.host ?? '?';
      return resp.statusCode == 200 ? 'ok      $host' : 'BROKEN  ${resp.statusCode} $host';
    });

    // 5. the reader
    await check(source, 'reader', () async {
      final List<BooruItem> pages = await handler.loadItem(item: first, withCapcthaCheck: false).then(
            (r) => r.item?.sources?.isNotEmpty == true ? [r.item!] : const <BooruItem>[],
          );
      return pages.isEmpty ? 'unverified (needs the reader UI)' : 'ok';
    });
  }

  group('doujin parity walk', () {
    test('nhentai (reference)', () async {
      await walk('nhentai', NHentaiHandler(Booru('nhentai', BooruType.NHentai, '', 'https://nhentai.net', ''), 20));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('niyaniya', () async {
      await walk('niyaniya', SchaleHandler(Booru('niyaniya', BooruType.NiyaNiya, '', 'https://niyaniya.moe', ''), 20));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('asmhentai', () async {
      await walk('asmhentai', AsmHentaiHandler(Booru('asm', BooruType.AsmHentai, '', 'https://asmhentai.com', ''), 20));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('eahentai', () async {
      await walk('eahentai', EaHentaiHandler(Booru('ea', BooruType.EaHentai, '', 'https://eahentai.com', ''), 20));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('hentalk', () async {
      await walk('hentalk', FaccinaHandler(Booru('hentalk', BooruType.Faccina, '', 'https://hentalk.pw', ''), 20));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('hitomi', () async {
      await walk('hitomi', HitomiHandler(Booru('hitomi', BooruType.Hitomi, '', 'https://hitomi.la', ''), 20));
    }, timeout: const Timeout(Duration(minutes: 5)));

    tearDownAll(() {
      // The report. Printed as one block so it can be read and pasted whole.
      const List<String> caps = [
        'feed', 'covers', 'titles', 'tags', 'namespaces',
        'detail', 'related', 'recommended', 'cover fetch', 'reader',
      ];
      final buffer = StringBuffer('\n\n=== DOUJIN PARITY WALK ===\n');
      for (final source in report.keys) {
        buffer.writeln('\n$source');
        for (final cap in caps) {
          buffer.writeln('  ${cap.padRight(13)} ${report[source]?[cap] ?? '-'}');
        }
      }
      buffer.writeln('\nstructural parity (set membership, confers favourites,');
      buffer.writeln('collections, history, follows, saved searches, pins,');
      buffer.writeln('per-source settings, backup, tabs, tag stars):');
      for (final type in DoujinDataHandler.doujinTypes) {
        buffer.writeln('  ${type.name}');
      }
      // ignore: avoid_print
      print(buffer);
    });
  });
}

/// The gallery id each source's query protocol expects.
String _idOf(BooruItem item, BooruHandler handler) {
  final segments = Uri.tryParse(item.postURL)?.pathSegments ?? const [];
  for (final s in segments) {
    if (RegExp(r'^\d+$').hasMatch(s)) return s;
  }
  return segments.isNotEmpty ? segments.last : '';
}
