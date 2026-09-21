import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/pinned_tag.dart';
import 'package:lolisnatcher/src/handlers/source_settings_handler.dart';

/// Pins hidden on one source (r52): a pin that takes too much room there
/// keeps its place everywhere else and on the pinned tags page. Kept in that
/// source's own settings, one key a line: `id:N` for a database pin, `tag:x`
/// for a doujin pin (which has no id).
class PinnedTagVisibility {
  const PinnedTagVisibility._();

  static String keyOf(PinnedTag pin) => pin.id > 0 ? 'id:${pin.id}' : 'tag:${pin.tagName}';

  static Set<String> _keys(String? stored) => (stored ?? '').split('\n').where((k) => k.isNotEmpty).toSet();

  static bool isHidden(PinnedTag pin, Booru booru) =>
      _keys(SourceSettingsHandler.instance.settingsFor(booru).hiddenPins).contains(keyOf(pin));

  static void setHidden(PinnedTag pin, Booru booru, bool hidden) {
    SourceSettingsHandler.instance.update(booru, (s) {
      final Set<String> keys = _keys(s.hiddenPins);
      if (hidden) {
        keys.add(keyOf(pin));
      } else {
        keys.remove(keyOf(pin));
      }
      s.hiddenPins = keys.isEmpty ? null : keys.join('\n');
    });
  }

  /// [pins] without the ones hidden on [booru].
  static List<PinnedTag> visible(List<PinnedTag> pins, Booru booru) {
    final Set<String> hidden = _keys(SourceSettingsHandler.instance.settingsFor(booru).hiddenPins);
    return pins.where((p) => !hidden.contains(keyOf(p))).toList();
  }

  /// r79: a deleted database pin's hides go with it, on every source. SQLite
  /// hands a freed id out again (the table has no AUTOINCREMENT), so a hide
  /// left behind would hide the next new pin - which the sidebar shows since
  /// r79 honours hides.
  static void forgetId(int id) {
    if (id <= 0) return;
    SourceSettingsHandler.instance.dropHiddenPins((String key) => key == 'id:$id');
  }

  /// r79: hides of database pins that no longer exist (deleted before r79),
  /// given every database pin there is. Doujin pins (`tag:` keys) live in
  /// their own store and are left alone.
  static void forgetMissing(List<PinnedTag> allDatabasePins) {
    final Set<String> alive = {
      for (final PinnedTag p in allDatabasePins)
        if (p.id > 0) 'id:${p.id}',
    };
    SourceSettingsHandler.instance.dropHiddenPins((String key) => key.startsWith('id:') && !alive.contains(key));
  }
}
