import 'package:lolisnatcher/models/pinned_tag.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';

/// "Following" state for artists (and, in principle, any tag). Persisted as
/// global pinned tags carrying the [followLabel] — so follows ride along in
/// backups — but presented in their own "Followed artists" screen, NOT in the
/// pinned-tags UIs (those filter follows out via [isFollowPin]). Kept
/// deliberately thin — the DB is the source of truth, this just wraps the
/// label convention.
class FollowedArtistsHandler {
  FollowedArtistsHandler._();

  static const String followLabel = 'followed';

  static SettingsHandler get _settings => SettingsHandler.instance;

  /// Whether a pinned-tag row is actually a follow (so pinned-tag UIs can
  /// leave it to the Followed artists screen).
  static bool isFollowPin(PinnedTag pin) => pin.labels.any((l) => l.toLowerCase() == followLabel);

  /// Whether [tagName] is currently followed.
  static Future<bool> isFollowed(String tagName) async {
    final list = await listFollowed();
    final String key = tagName.toLowerCase();
    return list.any((t) => t.toLowerCase() == key);
  }

  /// All followed tag names (global pins carrying the follow label).
  static Future<List<String>> listFollowed() async {
    try {
      final pins = await _settings.dbHandler.getAllPinnedTags();
      return [
        for (final p in pins)
          if (p.isGlobal && p.labels.any((l) => l.toLowerCase() == followLabel)) p.tagName,
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<void> follow(String tagName) async {
    try {
      await _settings.dbHandler.addPinnedTag(tagName, labels: const [followLabel]);
    } catch (_) {}
  }

  static Future<void> unfollow(String tagName) async {
    try {
      // Only the follow rows: a plain pin of the same tag on every source is
      // also a global pin with this name, and must stay. By id, so the
      // row's hides are forgotten with it (PinnedTag ids are reused).
      for (final PinnedTag p in await _settings.dbHandler.getAllPinnedTags()) {
        if (p.isGlobal && p.tagName == tagName && isFollowPin(p)) {
          await _settings.dbHandler.removePinnedTag(p.id);
        }
      }
    } catch (_) {}
  }

  /// Toggles follow state and returns the new state.
  static Future<bool> toggle(String tagName) async {
    final bool followed = await isFollowed(tagName);
    if (followed) {
      await unfollow(tagName);
      return false;
    }
    await follow(tagName);
    return true;
  }
}
