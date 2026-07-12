import 'dart:async';
import 'dart:math';

import 'package:get_it/get_it.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// Local behaviour tracker feeding the "For You" recommender.
///
/// Collects implicit interest signals — which posts you dwell on and for how
/// long, what you favourite / snatch / collect, what you search and preview —
/// and folds them into per-tag scores with a 30-day half-life (see
/// DatabaseHandler.addTagSignals). Everything stays in the local DB; nothing
/// is ever sent anywhere.
///
/// Signal weights (dimensionless, relative):
///   dwell on a post   0.2..1.5 (scales with seconds viewed, capped at 30s)
///   favourite         +6   (unfavourite -3)
///   add to collection +5
///   snatch            +4
///   search for a tag  +2
///   open tag preview  +1.5
class InterestsHandler {
  static InterestsHandler get instance => GetIt.instance<InterestsHandler>();

  static InterestsHandler register() {
    if (!GetIt.instance.isRegistered<InterestsHandler>()) {
      GetIt.instance.registerSingleton(InterestsHandler());
    }
    return instance;
  }

  static void unregister() => GetIt.instance.unregister<InterestsHandler>();

  final Map<String, double> _pending = {};
  Timer? _flushTimer;

  bool get _enabled {
    final s = SettingsHandler.instance;
    return s.dbEnabled && s.enableInterestTracking;
  }

  // Tags too generic to describe taste — tracked signals on them would drown
  // out the meaningful ones and produce garbage recommendation queries.
  static const Set<String> genericTags = {
    'animated', 'video', 'sound', 'webm', 'mp4', 'gif', 'loop', 'longer_than_30_seconds',
    'hi_res', 'highres', 'absurd_res', 'absurdres', 'high_resolution', '4k', '60fps', 'hd',
    '1girl', '1girls', '1boy', '1boys', '2girls', '2boys', 'solo', 'duo', 'female', 'male',
    'nsfw', 'explicit', 'questionable', 'safe', 'rating:explicit', 'tagme', 'translated',
    'uncensored', 'censored', 'english_text', 'text', 'speech_bubble', 'watermark', 'signature',
    'breasts', 'big_breasts', 'large_breasts', 'huge_breasts', 'nipples', 'nude', 'naked',
    'penis', 'pussy', 'vaginal', 'sex', 'straight', 'male/female', 'hetero', 'ass', 'thighs',
    'looking_at_viewer', 'smile', 'blush', 'open_mouth', 'long_hair', 'short_hair',
    'digital_media_(artwork)', 'source_request', 'commentary', 'artist_request',
  };

  static bool isMeaningfulTag(String tag) {
    final String t = tag.trim().toLowerCase();
    if (t.isEmpty || t.length < 2) return false;
    if (t.contains(':') && !t.startsWith('creator:')) return false; // meta tags (sort:, rating:, niche:, ...)
    if (t.startsWith('-') || t.startsWith('~')) return false;
    if (genericTags.contains(t)) return false;
    return true;
  }

  void _add(Iterable<String> tags, double weight) {
    if (!_enabled || weight == 0) return;
    for (final tag in tags) {
      final String t = tag.trim().toLowerCase();
      if (!isMeaningfulTag(t)) continue;
      _pending[t] = (_pending[t] ?? 0) + weight;
    }
    _scheduleFlush();
  }

  void _scheduleFlush() {
    _flushTimer ??= Timer(const Duration(seconds: 10), _flush);
  }

  Future<void> _flush() async {
    _flushTimer = null;
    if (_pending.isEmpty) return;
    final Map<String, double> batch = Map.of(_pending);
    _pending.clear();
    try {
      await SettingsHandler.instance.dbHandler.addTagSignals(batch);
    } catch (e, s) {
      Logger.Inst().log('failed to flush tag signals: $e', 'InterestsHandler', '_flush', LogTypes.exception, s: s);
    }
  }

  /// Flush without waiting for the debounce (e.g. before reading the profile).
  Future<void> flushNow() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _flush();
  }

  //
  // Signal entry points
  //

  /// Post was on screen in the viewer for [dwell]. Ignores flick-throughs.
  void onItemViewed(BooruItem item, Duration dwell) {
    if (dwell.inMilliseconds < 1500) return;
    final double seconds = min(dwell.inMilliseconds / 1000, 30);
    final double weight = 0.2 + (seconds / 30) * 1.3;
    _add(item.tagsList.map((t) => t.fullString), weight);
  }

  void onItemFavourited(BooruItem item, {required bool nowFavourite}) {
    _add(item.tagsList.map((t) => t.fullString), nowFavourite ? 6 : -3);
  }

  void onItemsSnatched(List<BooruItem> items) {
    for (final item in items.take(20)) {
      _add(item.tagsList.map((t) => t.fullString), 4);
    }
  }

  void onItemsCollected(List<BooruItem> items) {
    for (final item in items.take(20)) {
      _add(item.tagsList.map((t) => t.fullString), 5);
    }
  }

  void onSearch(String query) {
    final tags = query.split(' ').where(isMeaningfulTag).take(5);
    _add(tags, 2);
  }

  void onTagPreviewOpened(String tag) {
    _add(tag.split(' '), 1.5);
  }

  //
  // Profile access
  //

  Future<List<MapEntry<String, double>>> topTags({int limit = 100}) async {
    await flushNow();
    try {
      return await SettingsHandler.instance.dbHandler.getTagSignals(limit: limit);
    } catch (_) {
      return [];
    }
  }

  Future<void> removeTag(String tag) => SettingsHandler.instance.dbHandler.deleteTagSignal(tag);

  Future<void> resetProfile() async {
    _pending.clear();
    await SettingsHandler.instance.dbHandler.clearTagSignals();
  }

  /// Extracts the tags that best characterise a post, for "more like this"
  /// seeding: characters + artists + copyrights first, then meaningful
  /// general tags as fallback.
  static List<String> seedTagsFromItem(BooruItem item, {int limit = 3}) {
    final List<String> picked = [];
    void pick(bool Function(Tag) test, int cap) {
      int taken = 0;
      for (final t in item.tagsList) {
        if (taken >= cap || picked.length >= limit) break;
        final String name = t.fullString.trim();
        if (name.isEmpty || picked.contains(name)) continue;
        if (test(t)) {
          picked.add(name);
          taken++;
        }
      }
    }

    pick((t) => t.tagType.isCharacter, 2);
    pick((t) => t.tagType.isArtist, 1);
    pick((t) => t.tagType.isCopyright, 1);
    if (picked.isEmpty) {
      pick((t) => isMeaningfulTag(t.fullString), 2);
    }
    return picked;
  }
}
