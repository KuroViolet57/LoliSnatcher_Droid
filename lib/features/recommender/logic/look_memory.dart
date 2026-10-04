import 'dart:async';
import 'dart:collection';

import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/features/recommender/logic/model_tasks.dart';
import 'package:lolisnatcher/features/doujin/logic/doujin_data_handler.dart';
import 'package:lolisnatcher/features/recommender/logic/ml/look_model_handler.dart';
import 'package:lolisnatcher/features/recommender/logic/model_work.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/core/logging/logger.dart';

/// r81: "Remember the looks of posts you open" (Settings → Recommendations
/// → Models → Looks model; off until switched on). When you leave a post you
/// looked at for [minLook] or more, its look is saved in the vectors'
/// database, so For You, boards and the learner find it ready later.
///
/// Nothing is read twice: the looks model answers from memory and the
/// database first, so a video whose frames were taken keeps their average,
/// and a post For You already read keeps its vector. Only a post with
/// neither has its thumbnail read, once, as a background step (the looks
/// model's background thread count, at a quiet moment).
class LookMemory {
  LookMemory();

  static final LookMemory instance = LookMemory();

  /// Looked at for less than this: a glance, not remembered.
  static const Duration minLook = Duration(milliseconds: 2500);

  /// Posts already asked for in this run, most recent last.
  static const int keepAsked = 5000;

  // Seams, replaced in tests.
  DateTime Function() now = DateTime.now;
  bool Function() wanted = _defaultWanted;
  Booru? Function() booruNow = _defaultBooru;
  Future<void> Function(String label, Future<void> Function() step) queue = _defaultQueue;
  Future<void> Function(BooruItem item, Booru? booru) remember = _defaultRemember;

  void Function()? _unlisten;
  BooruItem? _current;
  Booru? _currentBooru;
  DateTime _since = DateTime.now();
  final LinkedHashSet<String> _asked = LinkedHashSet<String>();

  static String keyOf(BooruItem item) => item.postURL.isNotEmpty ? item.postURL : item.fileURL;

  /// Follows the viewer's current post, as VideoFrames does.
  void attach() {
    _unlisten?.call();
    final current = ViewerHandler.instance.current;
    _unlisten = current.addListener(() => _onCurrent(current.value));
    _current = null;
    _onCurrent(current.value);
  }

  void detach() {
    _unlisten?.call();
    _unlisten = null;
    _current = null;
  }

  /// A post with a picture to read, not a doujin item, not hidden.
  static bool eligible(BooruItem item) =>
      (item.thumbnailURL.isNotEmpty || item.sampleURL.isNotEmpty) && !DoujinDataHandler.isDoujinItem(item) && !item.isHidden;

  void _onCurrent(BooruItem? item) {
    final BooruItem? left = _current;
    if (left != null && item != null && keyOf(left) == keyOf(item)) return;
    if (left != null) _left(left, _currentBooru, now().difference(_since));
    _current = item;
    _since = now();
    _currentBooru = item == null ? null : booruNow();
  }

  void _left(BooruItem item, Booru? booru, Duration looked) {
    if (looked < minLook || !wanted() || !eligible(item)) return;
    final String key = keyOf(item);
    if (key.isEmpty || _asked.contains(key)) return;
    _asked.add(key);
    while (_asked.length > keepAsked) {
      _asked.remove(_asked.first);
    }
    // A step skipped because the app went away read nothing: the post is
    // asked for again the next time it is left.
    bool ran = false;
    unawaited(
      queue('remember look', () {
        ran = true;
        return remember(item, booru);
      }).whenComplete(() {
        if (!ran) _asked.remove(key);
      }),
    );
  }

  // ── defaults ──

  static bool _defaultWanted() => SettingsHandler.instance.rememberLooks && (LookModelHandler.maybe?.enabled ?? false);

  static Booru? _defaultBooru() {
    try {
      return SearchHandler.instance.currentBooru;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _defaultQueue(String label, Future<void> Function() step) => ModelWork.instance.run(label, (bool lite) async {
    // With the app away, a thumbnail is not worth a run; the post is
    // remembered the next time it is opened.
    if (!lite) await step();
  });

  static Future<void> _defaultRemember(BooruItem item, Booru? booru) async {
    final LookModelHandler? l = LookModelHandler.maybe;
    if (l == null || !l.enabled) return;
    try {
      await l.imageVectors([item], booru: booru, use: ModelUse.background);
    } catch (e) {
      Logger.Inst().log('look: a post could not be remembered: $e', 'LookMemory', 'remember', LogTypes.booruHandlerInfo);
    }
  }
}
