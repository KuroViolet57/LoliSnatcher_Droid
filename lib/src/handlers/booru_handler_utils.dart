// Small pure helpers shared by booru handlers. Kept narrow and side-effect
// free so they can be folded into any handler without pulling extra
// dependencies; tested in practice by the handlers that consume them.

/// Splits a whitespace-separated tag string into a clean tag list.
/// Drops empty / whitespace-only entries — several boorus return empty
/// `tag_string_*` fields when a category has no tags, and `String.split(' ')`
/// then produces `['']`, which the rest of the app turned into a `Tag('')`.
List<String> splitTagsClean(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  return raw
      .split(RegExp(r'\s+'))
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList(growable: false);
}

/// Drops the trailing `±HH:MM` timezone suffix from an ISO-ish date string,
/// guarded so the substring math never throws on short or unexpected input.
/// Returns null if the string can't be safely trimmed.
String? safeIsoDateMinusTimezone(Object? raw) {
  if (raw == null) return null;
  final String s = raw.toString();
  if (s.length <= 6) return null;
  return s.substring(0, s.length - 6);
}

/// Normalises the wildly inconsistent shape booru APIs use for `source` /
/// `sources`. Accepts:
///   - null                  -> null
///   - "" / "null"           -> null
///   - String                -> single-entry list
///   - `List<dynamic>`       -> `List<String>` with null/blank/"null" entries dropped
/// Returns null when nothing meaningful is present so callers don't end up
/// with `["null"]` or `[""]` polluting the sources list.
List<String>? cleanSourceList(Object? raw) {
  if (raw == null) return null;
  Iterable<String> entries;
  if (raw is List) {
    entries = raw.map((e) => e?.toString() ?? '');
  } else {
    entries = [raw.toString()];
  }
  final cleaned = entries
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty && e.toLowerCase() != 'null')
      .toList(growable: false);
  return cleaned.isEmpty ? null : cleaned;
}

/// Boorusama-flavoured tag normalisation used by Philomena / BooruOnRails:
/// underscores become `+`, but tags wrapped in double quotes keep their
/// internal underscores (just stripped of the quotes). Used when building
/// search URLs for sites that consume comma-separated `tag+with+plus` tags.
String formatTagsWithUnderscoresPhilomena(String tags) {
  final List<String> tagsList = tags.split(' ');
  for (int i = 0; i < tagsList.length; i++) {
    final String tag = tagsList[i];
    if (tag.contains('"')) {
      tagsList[i] = tag.replaceAll('"', '');
    } else {
      tagsList[i] = tag.replaceAll('_', '+');
    }
  }
  return tagsList.join(' ');
}
