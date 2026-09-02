import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:get_it/get_it.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/post_similarity.dart';

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

  /// Signals waiting to be written, for tests that check the door held.
  @visibleForTesting
  Map<String, double> get pendingSignals => Map.unmodifiable(_pending);

  /// The guard at the door. This profile is the BOORU taste profile; doujin
  /// activity has its own world and must never reach it, whichever caller
  /// forgot to check. Judged per item (post URL host) so merge tabs mixing
  /// both worlds stay separated, and per source for the string-only signals.
  static bool _refuses(BooruItem item) => DoujinDataHandler.isDoujinItem(item);

  static bool _refusesSource(Booru? booru) => DoujinDataHandler.isDoujinBooru(booru);

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
    if (_refuses(item)) return;
    if (dwell.inMilliseconds < 1500) return;
    final double seconds = min(dwell.inMilliseconds / 1000, 30);
    final double weight = 0.2 + (seconds / 30) * 1.3;
    _add(item.tagsList.map((t) => t.fullString), weight);
  }

  void onItemFavourited(BooruItem item, {required bool nowFavourite}) {
    if (_refuses(item)) return;
    _add(item.tagsList.map((t) => t.fullString), nowFavourite ? 6 : -3);
  }

  void onItemsSnatched(List<BooruItem> items) {
    for (final item in items.where((i) => !_refuses(i)).take(20)) {
      _add(item.tagsList.map((t) => t.fullString), 4);
    }
  }

  void onItemsCollected(List<BooruItem> items) {
    for (final item in items.where((i) => !_refuses(i)).take(20)) {
      _add(item.tagsList.map((t) => t.fullString), 5);
    }
  }

  /// [booru] is the source searched; a doujin source is refused here even
  /// when the caller did not check.
  void onSearch(String query, {Booru? booru}) {
    if (_refusesSource(booru)) return;
    final tags = query.split(' ').where(isMeaningfulTag).take(5);
    _add(tags, 2);
  }

  void onTagPreviewOpened(String tag, {Booru? booru}) {
    if (_refusesSource(booru)) return;
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

    // Tag types come from the app-wide store when the booru sent none —
    // shimmie-family sites type nothing, and without this every
    // character/artist/copyright pick below fails and the seed degrades to
    // whatever generic tag happens to be listed first ("3d, blender").
    TagType typeOf(Tag t) {
      if (t.tagType != TagType.none) return t.tagType;
      return TagHandler.instance.getTag(t.fullString).tagType;
    }

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

    pick((t) => typeOf(t).isCharacter, 2);
    pick((t) => typeOf(t).isArtist, 1);
    pick((t) => typeOf(t).isCopyright, 1);
    if (picked.isEmpty) {
      // Nothing typed anywhere: seed with the most DISTINCTIVE tags rather
      // than the first meaningful ones. Medium/format tags match half the
      // booru and recommend nothing in particular; the booru's own tag
      // counts (when the handler reports them) are the best rarity signal,
      // otherwise fall back to name specificity.
      final List<Tag> candidates = item.tagsList.where((t) {
        final String name = t.fullString.trim();
        if (name.isEmpty || !isMeaningfulTag(name)) return false;
        if (typeOf(t) == TagType.meta) return false;
        return !kGenericMediumTags.contains(normalizeTagName(name));
      }).toList()
        ..sort((a, b) {
          final int ca = a.count > 0 ? a.count : 1 << 30;
          final int cb = b.count > 0 ? b.count : 1 << 30;
          if (ca != cb) return ca.compareTo(cb);
          int spec(Tag t) => (t.fullString.contains('(') ? 2 : 0) + (t.fullString.contains('_') ? 1 : 0);
          final int bySpec = spec(b).compareTo(spec(a));
          if (bySpec != 0) return bySpec;
          return b.fullString.length.compareTo(a.fullString.length);
        });
      for (final t in candidates.take(2)) {
        if (picked.length >= limit) break;
        picked.add(t.fullString.trim());
      }
    }
    return picked;
  }
}
