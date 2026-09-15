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
}
