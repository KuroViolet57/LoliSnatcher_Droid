import 'dart:convert';
import 'dart:io';

import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/doujin/logic/doujin_download_handler.dart';
import 'package:lolisnatcher/features/downloads/logic/snatch_handler.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/tag.dart';

/// The snatch queue on disk. One JSON snapshot, not settings.json and not
/// store.db. A booru's api key and user id are left out; the caller matches
/// the source back onto the configured booru.
///
/// Writes go to a temp file and then replace the snapshot, so a torn write
/// leaves the previous file. If the snapshot is missing, a leftover temp
/// file is read instead.
class SnatchQueueJournal {
  SnatchQueueJournal(this.file);

  factory SnatchQueueJournal.forSettings() {
    return SnatchQueueJournal(File('${SettingsHandler.instance.path}snatch-queue.json'));
  }

  final File file;
  Future<void> _chain = Future<void>.value();

  /// Completes once every save queued so far has landed.
  Future<void> get flushed => _chain;

  void save(List<SnatchItem> items) {
    final String encoded = jsonEncode({
      'items': [for (final SnatchItem item in items) _snatchToJson(item)],
    });
    _chain = _chain.then((_) async {
      try {
        await _replace(encoded);
      } catch (_) {}
    });
  }

  Future<List<SnatchItem>> load({Booru? Function(String name, String baseUrl)? lookup}) async {
    final String? raw = await _read();
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return [];
      final List<SnatchItem> items = [];
      for (final dynamic entry in decoded['items'] as List? ?? []) {
        final SnatchItem? item = _snatchFrom(entry, lookup);
        if (item != null) items.add(item);
      }
      return items;
    } catch (_) {
      return [];
    }
  }

  Future<void> _replace(String encoded) async {
    final File tmp = File('${file.path}.tmp');
    await tmp.writeAsString(encoded, flush: true);
    if (file.existsSync()) await file.delete();
    await tmp.rename(file.path);
  }

  Future<String?> _read() async {
    if (file.existsSync()) return file.readAsString();
    final File tmp = File('${file.path}.tmp');
    if (tmp.existsSync()) return tmp.readAsString();
    return null;
  }
}

Map<String, dynamic> _snatchToJson(SnatchItem item) {
  final Map<String, dynamic> booru = item.booru.toJson();
  booru.remove('apiKey');
  booru.remove('userID');
  return {
    'cooldown': item.cooldown,
    'ignoreExists': item.ignoreExists,
    'booru': booru,
    'items': [for (final BooruItem page in item.booruItems) _itemToJson(page)],
    if (item.doujin != null) 'doujin': _doujinToJson(item.doujin!),
  };
}

Map<String, dynamic> _itemToJson(BooruItem item) {
  final Map<String, dynamic> json = item.toJson();
  json['tags'] = [for (final Tag tag in item.tagsList) tag.fullString];
  return json;
}

Map<String, dynamic> _doujinToJson(DoujinDownloadInfo info) {
  return {
    'host': info.host,
    'serverId': info.serverId,
    'postURL': info.postURL,
    'title': info.title,
    'coverURL': info.coverURL,
    'sourceName': info.sourceName,
    'pages': [for (final BooruItem page in info.pages) _itemToJson(page)],
    'missingPages': info.missingPages,
  };
}

SnatchItem? _snatchFrom(dynamic raw, Booru? Function(String name, String baseUrl)? lookup) {
  if (raw is! Map) return null;
  final List<BooruItem> items = [
    for (final dynamic entry in raw['items'] as List? ?? [])
      if (_itemFrom(entry) case final BooruItem item) item,
  ];
  if (items.isEmpty) return null;
  final dynamic booruRaw = raw['booru'];
  if (booruRaw is! Map) return null;
  final Booru parsed = Booru.fromMap(Map<String, dynamic>.from(booruRaw));
  final Booru booru = lookup?.call(parsed.name ?? '', parsed.baseURL ?? '') ?? parsed;
  return SnatchItem(
    items,
    raw['cooldown'] is int ? raw['cooldown'] as int : int.tryParse('${raw['cooldown']}') ?? 0,
    booru,
    raw['ignoreExists'] == true,
    doujin: raw['doujin'] is Map ? _doujinFrom(raw['doujin']) : null,
  );
}

BooruItem? _itemFrom(dynamic raw) {
  if (raw is! Map) return null;
  final Map<String, dynamic> json = Map<String, dynamic>.from(raw);
  if (json['fileURL'] == null || json['postURL'] == null) return null;
  json['sampleURL'] ??= json['thumbnailURL'] ?? json['fileURL'];
  json['thumbnailURL'] ??= json['fileURL'];
  json['tags'] = [
    for (final dynamic tag in json['tags'] as List? ?? [])
      if (tag is String) tag else if (tag is Map) tag['fullString']?.toString() ?? '',
  ];
  try {
    final BooruItem item = BooruItem.fromMap(json);
    final String? ext = json['fileExt']?.toString();
    if (ext != null && ext.isNotEmpty && ext != 'null') {
      item.fileExt = ext.toLowerCase();
      item.mediaType.value = MediaType.fromExtension(item.fileExt);
    }
    final String? md5 = json['md5String']?.toString();
    if (md5 != null && md5 != 'null') item.md5String = md5;
    final String? named = json['downloadFileName']?.toString();
    if (named != null && named != 'null') item.downloadFileName = named;
    final String? serverId = json['serverId']?.toString();
    if (serverId != null && serverId != 'null') item.serverId = serverId;
    final String? extras = json['fileNameExtras']?.toString();
    if (extras != null && extras != 'null') item.fileNameExtras = extras;
    return item;
  } catch (_) {
    return null;
  }
}

DoujinDownloadInfo? _doujinFrom(dynamic raw) {
  if (raw is! Map) return null;
  final List<BooruItem> pages = [
    for (final dynamic entry in raw['pages'] as List? ?? [])
      if (_itemFrom(entry) case final BooruItem page) page,
  ];
  return DoujinDownloadInfo(
    host: raw['host']?.toString() ?? '',
    serverId: raw['serverId']?.toString() ?? '',
    postURL: raw['postURL']?.toString() ?? '',
    title: raw['title']?.toString() ?? '',
    coverURL: raw['coverURL']?.toString() ?? '',
    sourceName: raw['sourceName']?.toString() ?? '',
    pages: pages,
    missingPages: [
      for (final dynamic n in raw['missingPages'] as List? ?? [])
        if (n is int) n else if (int.tryParse('$n') != null) int.parse('$n'),
    ],
  );
}
