import 'dart:io';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

/// r85: the sites whose links the app offers to open (Settings → Links).
///
/// Android cannot add link hosts to an app while it runs: they are in the
/// manifest, on the `.SourceLinks` entry, which stays off until the switch
/// turns it on. Link Sheet offers an app for a link only when its filter
/// names the link's host, so every site is named there, once as itself and
/// once as `*.site` for its subdomains (www. included). The sites are not
/// ours to verify, so Android and link apps offer the app - they never make
/// it the default by themselves.
///
/// The list is every site the app knows a source for; a source on another
/// address (a self-hosted booru) is listed in Settings → Links as not
/// covered. `test/source_links_test.dart` keeps this list and the manifest
/// in step.
class SourceLinks {
  const SourceLinks._();

  static const List<String> sites = [
    // Danbooru engine and the like
    'donmai.us',
    'aibooru.online',
    // Gelbooru engine
    'gelbooru.com',
    'safebooru.org',
    'rule34.xxx',
    'realbooru.com',
    'xbooru.com',
    'tbib.org',
    'hypnohub.net',
    'booru.org',
    'bakemono.app',
    // e621
    'e621.net',
    'e926.net',
    // Moebooru
    'yande.re',
    'konachan.com',
    'konachan.net',
    // Sankaku
    'sankakucomplex.com',
    'sankaku.app',
    // Shimmie
    'paheal.net',
    'whyneko.com',
    // Philomena and its kin
    'derpibooru.org',
    'furbooru.org',
    'twibooru.org',
    'rainbooru.org',
    // the rest of the classic boorus
    'rule34.us',
    'rule34hentai.net',
    'rule34.world',
    'animazone34.com',
    'rule34vault.com',
    'rule34.dev',
    'agn.ph',
    'nozomi.la',
    'inkbunny.net',
    'nyanpals.com',
    'wildcritters.ws',
    'furaffinity.net',
    'civitai.com',
    // videos
    'redgifs.com',
    'rule34video.com',
    'hanime1.me',
    'kusowanka.com',
    'tik.porn',
    'xxxtik.com',
    'xxxfollow.com',
    // creators' archives
    'kemono.cr',
    'kemono.su',
    'kemono.party',
    'pawchive.pw',
    // doujins
    'nhentai.net',
    'e-hentai.org',
    'exhentai.org',
    'hitomi.la',
    'eahentai.com',
    'hentaipaw.com',
    'niyaniya.moe',
    'shupogaki.moe',
    'hdoujin.org',
    'asmhentai.com',
    'hentalk.pw',
  ];

  /// [host] is one of [sites] or a subdomain of one.
  static bool covers(String host) {
    final String h = host.trim().toLowerCase();
    if (h.isEmpty) return false;
    return sites.any((s) => h == s || h.endsWith('.$s'));
  }

  /// Your sources, split by whether their links can open in the app. Your
  /// own lists and the virtual feeds (merge, For You, boards) are not sources.
  static ({List<Booru> covered, List<Booru> uncovered}) coverage(Iterable<Booru> boorus) {
    final List<Booru> covered = [], uncovered = [];
    for (final Booru b in boorus) {
      final BooruType? type = b.type;
      if (type == null || !BooruType.saveable.contains(type) || type.isLocalDb) continue;
      final String host = Uri.tryParse(b.baseURL ?? '')?.host ?? '';
      if (host.isEmpty) continue;
      (covers(host) ? covered : uncovered).add(b);
    }
    return (covered: covered, uncovered: uncovered);
  }

  /// Turns the manifest entry on or off; replaced in tests.
  static Future<void> Function(bool on) apply = _defaultApply;

  static Future<void> _defaultApply(bool on) async {
    if (!Platform.isAndroid) return;
    await ServiceHandler.setSourceLinks(on);
  }

  /// At start: the entry follows the saved switch (after a restore on a new
  /// install the switch comes back, the entry's state does not).
  static Future<void> applySaved() => apply(SettingsHandler.instance.openSourceLinks);

  static void resetForTests() => apply = _defaultApply;
}
