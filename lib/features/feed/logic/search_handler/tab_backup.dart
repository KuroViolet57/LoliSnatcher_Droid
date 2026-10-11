part of '../search_handler.dart';

// special strings used to separate parts of tab backup string
const String tabDivider = '|||', listDivider = '~~~';

List<List<String>> decodeBackupString(String input) {
  final List<List<String>> result = [];
  final List<String> splitInput = input.split(listDivider);
  for (final String str in splitInput) {
    final List<String> booruAndTags = str.split(tabDivider);
    result.add(booruAndTags);
  }
  return result;
}

class TabBackup {
  TabBackup({
    required this.tags,
    required this.booru,
    this.id,
    this.group,
    this.poolId,
    this.poolName,
    this.doujinPostURL,
    this.doujinTitle,
    this.doujinThumb,
    this.secondaryBoorus = const [],
    this.tagOverrides = const {},
    this.inheritMainTags = const {},
    this.selected = false,
  });
  final String tags;
  final String booru;
  // Stable tab id, so a restored tab keeps the same identity the visited-tabs
  // history recorded. Optional for backward-compat with older backups.
  final String? id;
  // Tab group name (null/absent = ungrouped).
  final String? group;
  // Pool this tab shows, when it is a pool tab. Persisted so a restored pool
  // tab still fetches pool contents (and still shows its chip) instead of
  // degrading into a plain — and broken — text search.
  final String? poolId;
  final String? poolName;
  // Doujin detail tab: this tab is one doujin's detail page. Persisted so a
  // restored tab comes back as a detail-page tab with its cover in the tab
  // manager, not as a plain search feed.
  final String? doujinPostURL;
  final String? doujinTitle;
  final String? doujinThumb;
  final List<String> secondaryBoorus;
  // Per-booru tag overrides used in merge mode. Keys are booru names; missing
  // entries (or older backups without this field) fall back to `tags`.
  final Map<String, String> tagOverrides;
  // Per-booru "do not inherit main tags" flags. Only false entries are
  // persisted (true is the default).
  final Map<String, bool> inheritMainTags;
  final bool selected;

  Map<String, dynamic> toJson() {
    return {
      't': tags,
      'b': booru,
      if (id != null) 'i': id,
      if (group != null && group!.isNotEmpty) 'g': group,
      if (poolId != null && poolId!.isNotEmpty) 'p': poolId,
      if (poolName != null && poolName!.isNotEmpty) 'pn': poolName,
      if (doujinPostURL != null && doujinPostURL!.isNotEmpty) 'dp': doujinPostURL,
      if (doujinTitle != null && doujinTitle!.isNotEmpty) 'dt': doujinTitle,
      if (doujinThumb != null && doujinThumb!.isNotEmpty) 'dth': doujinThumb,
      if (secondaryBoorus.isNotEmpty) 'sb': secondaryBoorus,
      if (tagOverrides.isNotEmpty) 'to': tagOverrides,
      if (inheritMainTags.isNotEmpty) 'in': inheritMainTags,
      if (selected) 's': selected, // only true matters, don't include on false
    };
  }

  static TabBackup? fromJson(Map<String, dynamic> json) {
    try {
      return TabBackup(
        tags: json['t'] as String,
        booru: json['b'] as String,
        id: json['i'] as String?,
        group: json['g'] as String?,
        poolId: json['p'] as String?,
        poolName: json['pn'] as String?,
        doujinPostURL: json['dp'] as String?,
        doujinTitle: json['dt'] as String?,
        doujinThumb: json['dth'] as String?,
        secondaryBoorus: (json['sb'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
        tagOverrides:
            (json['to'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v.toString())) ?? const {},
        inheritMainTags:
            (json['in'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v == true)) ?? const {},
        selected: (json['s'] as bool?) ?? false,
      );
    } catch (_) {
      try {
        return TabBackup(
          tags: json['t'] as String,
          booru: json['b'] as String,
        );
      } catch (e, s) {
        Logger.Inst().log(
          'Invalid tab backup',
          'TabBackup',
          'fromJson',
          LogTypes.exception,
          s: s,
        );
        throw Exception('Invalid tab backup: $json');
      }
    }
  }

  static List<TabBackup> fromJsonList(String json) {
    final jsonList = jsonDecode(json);

    if (jsonList is! List) {
      return [];
    }

    return jsonList.map((e) => fromJson(e as Map<String, dynamic>)).where((e) => e != null).cast<TabBackup>().toList();
  }
}
