import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/image_writer.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// What a doujin download IS on disk, and how it is read back.
///
/// Layout, the same for every source:
///
///     <download root>/Doujin/<host>_<gallery id>/001.<ext> … NNN.<ext>
///                                                 doujin.json   (manifest)
///
/// Before this, every source wrote its pages LOOSE into the download root as
/// `<source name>_<url tail>`: nhentai `nhentai_1.webp`, asmhentai
/// `asmhentai_1.jpg`, faccina `faccina_1`, niyaniya `niyaniya_001.webp`
/// (hitomi's hashed names were the one exception). Page 1 of every book on a
/// source therefore had the SAME file name, the second book's pages "already
/// existed" and were skipped while still being marked as snatched, and
/// nothing on disk said which book a file belonged to. Those loose files are
/// still listed here, grouped per source, so they are not lost.
///
/// The manifest carries what the list shows (cover, title, page count,
/// source) so a folder is self-describing; a folder without one (copied in
/// by hand) is listed from its image files alone.
class DoujinDownloadInfo {
  const DoujinDownloadInfo({
    required this.host,
    required this.serverId,
    required this.postURL,
    required this.title,
    required this.coverURL,
    required this.sourceName,
    required this.pages,
  });

  /// The gallery a detail page or card is about to save.
  factory DoujinDownloadInfo.fromGallery(BooruItem gallery, Booru booru, List<BooruItem> pages) {
    String host = DoujinDataHandler.hostOf(booru);
    if (host.isEmpty) host = Uri.tryParse(gallery.postURL)?.host ?? '';
    return DoujinDownloadInfo(
      host: host,
      serverId: gallery.serverId?.isNotEmpty == true ? gallery.serverId! : _idFromUrl(gallery.postURL),
      postURL: gallery.postURL,
      title: firstLine(gallery.description),
      coverURL: gallery.thumbnailURL,
      sourceName: booru.name ?? host,
      pages: pages,
    );
  }

  /// The book the reader is showing (it has no gallery item, only pages).
  factory DoujinDownloadInfo.fromPages(
    List<BooruItem> pages,
    Booru booru, {
    required String galleryId,
    required String title,
  }) {
    final String postURL = pages.isEmpty ? '' : pages.first.postURL;
    String host = DoujinDataHandler.hostOf(booru);
    if (host.isEmpty) host = Uri.tryParse(postURL)?.host ?? '';
    return DoujinDownloadInfo(
      host: host,
      serverId: galleryId.isNotEmpty ? galleryId : _idFromUrl(postURL),
      postURL: postURL,
      title: title,
      coverURL: pages.isEmpty ? '' : pages.first.thumbnailURL,
      sourceName: booru.name ?? host,
      pages: pages,
    );
  }

  final String host;
  final String serverId;
  final String postURL;
  final String title;
  final String coverURL;
  final String sourceName;

  /// Every page of the book, in order — a single saved page is numbered by
  /// its place in the book, not its place in the download queue.
  final List<BooruItem> pages;

  /// `<host>_<id>`, made safe for a file system.
  String get folderName => Tools.sanitize('${host}_$serverId', replacement: '_');

  static String firstLine(String? text) =>
      (text ?? '').split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '').trim();

  /// Last numeric-looking path segment of a gallery URL, as a stand-in id.
  static String _idFromUrl(String url) {
    final segments = Uri.tryParse(url)?.pathSegments.where((s) => s.isNotEmpty).toList() ?? const [];
    for (final s in segments.reversed) {
      if (RegExp(r'^\d+').hasMatch(s)) return RegExp(r'^\d+').firstMatch(s)!.group(0)!;
    }
    return segments.isEmpty ? Tools.sanitize(url, replacement: '_') : segments.last;
  }
}

/// Where a book's pages go: a plain directory (with trailing separator) or a
/// SAF directory URI.
class DoujinDownloadTarget {
  const DoujinDownloadTarget({required this.dir, required this.isSaf});

  final String dir;
  final bool isSaf;
}

/// One saved book as the downloads list shows it.
class DoujinDownloadEntry {
  const DoujinDownloadEntry({
    required this.title,
    required this.host,
    required this.serverId,
    required this.postURL,
    required this.sourceName,
    required this.location,
    required this.isSaf,
    required this.pages,
    required this.savedAt,
    this.isLoose = false,
  });

  final String title;
  final String host;
  final String serverId;
  final String postURL;
  final String sourceName;

  /// The folder: a path (plain) or a directory URI (SAF). For loose groups,
  /// the download root.
  final String location;
  final bool isSaf;

  /// Page addresses in reading order, as `file://` URLs or `content://`
  /// document URIs.
  final List<String> pages;
  final int savedAt;

  /// Pages saved before folders existed, grouped by source name.
  final bool isLoose;

  int get pageCount => pages.length;
  String get cover => pages.isEmpty ? '' : pages.first;

  /// The list is built from local files: the reader opens them directly.
  List<BooruItem> toPageItems() => [
    for (final p in pages)
      BooruItem(
        fileURL: p,
        sampleURL: p,
        thumbnailURL: p,
        tagsList: const [],
        postURL: postURL,
        fileExt: _extOf(p),
      ),
  ];

  static String _extOf(String url) {
    final String name = Uri.decodeComponent(url.split('/').last);
    final int dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(dot + 1).toLowerCase() : 'jpg';
  }
}

class DoujinDownloadHandler {
  DoujinDownloadHandler._();

  static final DoujinDownloadHandler instance = DoujinDownloadHandler._();

  static const String folderName = 'Doujin';
  static const String manifestName = 'doujin.json';
  static const int manifestVersion = 1;

  static const Set<String> _imageExts = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'avif', 'jxl', 'bmp'};

  /// Source names whose loose root files are grouped (before folders).
  static const Set<String> legacySourceNames = {'nhentai', 'niyaniya', 'asmhentai', 'eahentai', 'faccina', 'hitomi', 'hentalk', 'hentaipaw'};

  bool get isSaf => Platform.isAndroid && SettingsHandler.instance.extPathOverride.isNotEmpty;

  /// The download root every write goes under: the SAF folder picked in
  /// Settings → Snatching, or the default Pictures/LoliSnatcher.
  Future<String> rootLocation() async {
    final writer = ImageWriter();
    await writer.setPaths();
    return writer.path;
  }

  /// Human-readable root for reports and the empty state.
  Future<String> describeRoot() async {
    final String root = await rootLocation();
    if (isSaf) return '${Uri.decodeComponent(root)}  (chosen storage folder)';
    return root;
  }

  /// `001.webp` — the page's place in its BOOK, not in the queue.
  static String pageFileName(DoujinDownloadInfo info, BooruItem page, int queueIndex) {
    int index = info.pages.indexWhere((p) => p.fileURL == page.fileURL);
    if (index < 0) index = queueIndex;
    final String ext = (page.fileExt?.isNotEmpty == true) ? page.fileExt! : 'jpg';
    return '${(index + 1).toString().padLeft(3, '0')}.$ext';
  }

  /// Creates `<root>/Doujin/<host>_<id>/` and returns it, or null when the
  /// storage cannot be written (the caller then saves loose, as before).
  Future<DoujinDownloadTarget?> prepare(DoujinDownloadInfo info) async {
    try {
      final String root = await rootLocation();
      if (isSaf) {
        final String? doujinDir = await ServiceHandler.getOrCreateSAFDirectory(root, folderName);
        if (doujinDir == null) return _fail('could not create $folderName under the SAF root');
        final String? bookDir = await ServiceHandler.getOrCreateSAFDirectory(doujinDir, info.folderName);
        if (bookDir == null) return _fail('could not create ${info.folderName} under $folderName');
        _log('book folder (SAF): ${info.folderName}');
        return DoujinDownloadTarget(dir: bookDir, isSaf: true);
      }
      final String sep = Platform.pathSeparator;
      final String base = root.endsWith(sep) || root.endsWith('/') ? root : '$root$sep';
      final Directory dir = Directory('$base$folderName$sep${info.folderName}$sep');
      await dir.create(recursive: true);
      _log('book folder: ${dir.path}');
      return DoujinDownloadTarget(dir: dir.path, isSaf: false);
    } catch (e, s) {
      Logger.Inst().log('prepare failed: $e', 'DoujinDownloadHandler', 'prepare', LogTypes.exception, s: s);
      return null;
    }
  }

  DoujinDownloadTarget? _fail(String why) {
    _log('$why — pages will be saved loose in the download root');
    return null;
  }

  Map<String, dynamic> manifestFor(DoujinDownloadInfo info) => {
    'version': manifestVersion,
    'host': info.host,
    'serverId': info.serverId,
    'postURL': info.postURL,
    'title': info.title,
    'sourceName': info.sourceName,
    'coverURL': info.coverURL,
    'pageCount': info.pages.length,
    'pages': [for (int i = 0; i < info.pages.length; i++) pageFileName(info, info.pages[i], i)],
    'savedAt': DateTime.now().millisecondsSinceEpoch,
  };

  /// Writes (or rewrites) the folder's manifest.
  Future<void> writeManifest(DoujinDownloadTarget target, DoujinDownloadInfo info) async {
    try {
      final String json = jsonEncode(manifestFor(info));
      if (target.isSaf) {
        // createFile would make "doujin (1).json" beside an old one.
        await ServiceHandler.deleteFileFromSAFDirectory(target.dir, manifestName);
        final String? stream = await ServiceHandler.createFileStreamFromSAFDirectory(
          manifestName.replaceAll('.json', ''),
          'application/json',
          'json',
          target.dir,
        );
        if (stream == null) return _log('manifest could not be created (SAF)');
        await ServiceHandler.writeStreamToFileFromSAFDirectory(stream, Uint8List.fromList(utf8.encode(json)));
        await ServiceHandler.closeStreamToFileFromSAFDirectory(stream);
      } else {
        await File('${target.dir}$manifestName').writeAsString(json, flush: true);
      }
      _log('manifest written for ${info.folderName} (${info.pages.length} pages)');
    } catch (e, s) {
      Logger.Inst().log('manifest failed: $e', 'DoujinDownloadHandler', 'writeManifest', LogTypes.exception, s: s);
    }
  }

  // ───────────────────────────── reading back ─────────────────────────────

  /// Everything saved: one entry per book folder, plus one per source for
  /// loose pages saved before folders existed. Newest first.
  Future<List<DoujinDownloadEntry>> scan() async {
    final List<DoujinDownloadEntry> entries = [];
    try {
      final String root = await rootLocation();
      if (isSaf) {
        await _scanSaf(root, entries);
      } else {
        await _scanPlain(root, entries);
      }
    } catch (e, s) {
      Logger.Inst().log('scan failed: $e', 'DoujinDownloadHandler', 'scan', LogTypes.exception, s: s);
    }
    entries.sort((a, b) {
      if (a.isLoose != b.isLoose) return a.isLoose ? 1 : -1;
      return b.savedAt.compareTo(a.savedAt);
    });
    _log('scan: ${entries.length} entries (${entries.where((e) => e.isLoose).length} loose groups)');
    return entries;
  }

  Future<void> _scanPlain(String root, List<DoujinDownloadEntry> out) async {
    final String sep = Platform.pathSeparator;
    final String base = root.endsWith(sep) || root.endsWith('/') ? root : '$root$sep';
    final Directory rootDir = Directory(base);
    if (!await rootDir.exists()) {
      _log('download root does not exist: $base');
      return;
    }
    final Directory doujinDir = Directory('$base$folderName');
    if (await doujinDir.exists()) {
      await for (final entity in doujinDir.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final List<FileSystemEntity> children = await entity.list(followLinks: false).toList();
        final Map<String, String> byName = {
          for (final c in children)
            if (c is File) c.path.split(sep).last: Uri.file(c.path).toString(),
        };
        Map<String, dynamic>? manifest;
        if (byName.containsKey(manifestName)) {
          try {
            manifest = jsonDecode(await File('${entity.path}$sep$manifestName').readAsString()) as Map<String, dynamic>;
          } catch (_) {}
        }
        int savedAt = 0;
        try {
          savedAt = (await entity.stat()).modified.millisecondsSinceEpoch;
        } catch (_) {}
        final entry = entryFromFolder(
          folderName: entity.path.split(sep).where((s) => s.isNotEmpty).last,
          filesByName: byName,
          manifest: manifest,
          location: '${entity.path}$sep',
          isSaf: false,
          savedAt: savedAt,
        );
        if (entry != null) out.add(entry);
      }
    }
    // Loose pages from before folders.
    final Map<String, String> rootFiles = {};
    await for (final entity in rootDir.list(followLinks: false)) {
      if (entity is File) rootFiles[entity.path.split(sep).last] = Uri.file(entity.path).toString();
    }
    out.addAll(looseGroups(rootFiles, location: base, isSaf: false));
  }

  Future<void> _scanSaf(String root, List<DoujinDownloadEntry> out) async {
    final List<Map<String, dynamic>> rootEntries = await ServiceHandler.listSAFDirectory(root);
    if (rootEntries.isEmpty) _log('SAF root listed no entries (unreachable or empty): $root');
    final Map<String, dynamic>? doujinDir = rootEntries.cast<Map<String, dynamic>?>().firstWhere(
      (e) => e!['isDir'] == true && e['name'] == folderName,
      orElse: () => null,
    );
    if (doujinDir != null) {
      for (final book in await ServiceHandler.listSAFDirectory(doujinDir['uri'] as String)) {
        if (book['isDir'] != true) continue;
        final List<Map<String, dynamic>> files = await ServiceHandler.listSAFDirectory(book['uri'] as String);
        final Map<String, String> byName = {
          for (final f in files)
            if (f['isDir'] != true) f['name'] as String: f['uri'] as String,
        };
        Map<String, dynamic>? manifest;
        if (byName.containsKey(manifestName)) {
          try {
            final bytes = await ServiceHandler.getSAFFile(byName[manifestName]!);
            if (bytes != null) manifest = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
          } catch (_) {}
        }
        final entry = entryFromFolder(
          folderName: book['name'] as String,
          filesByName: byName,
          manifest: manifest,
          location: book['uri'] as String,
          isSaf: true,
          savedAt: (book['modified'] as num?)?.toInt() ?? 0,
        );
        if (entry != null) out.add(entry);
      }
    }
    final Map<String, String> rootFiles = {
      for (final e in rootEntries)
        if (e['isDir'] != true) e['name'] as String: e['uri'] as String,
    };
    out.addAll(looseGroups(rootFiles, location: root, isSaf: true));
  }

  /// One folder → one entry. Pure, so it is testable without a device.
  @visibleForTesting
  static DoujinDownloadEntry? entryFromFolder({
    required String folderName,
    required Map<String, String> filesByName,
    required Map<String, dynamic>? manifest,
    required String location,
    required bool isSaf,
    required int savedAt,
  }) {
    List<String> pageNames;
    if (manifest != null && manifest['pages'] is List) {
      pageNames = [
        for (final p in manifest['pages'] as List)
          if (filesByName.containsKey(p.toString())) p.toString(),
      ];
    } else {
      pageNames = [];
    }
    if (pageNames.isEmpty) {
      pageNames = filesByName.keys.where(_isImageName).toList()..sort(naturalCompare);
    }
    if (pageNames.isEmpty) return null;

    String host = manifest?['host']?.toString() ?? '';
    String serverId = manifest?['serverId']?.toString() ?? '';
    if (host.isEmpty || serverId.isEmpty) {
      final int split = folderName.lastIndexOf('_');
      if (split > 0) {
        host = host.isEmpty ? folderName.substring(0, split) : host;
        serverId = serverId.isEmpty ? folderName.substring(split + 1) : serverId;
      } else {
        host = host.isEmpty ? folderName : host;
      }
    }
    return DoujinDownloadEntry(
      title: manifest?['title']?.toString().trim().isNotEmpty == true ? manifest!['title'].toString().trim() : folderName,
      host: host,
      serverId: serverId,
      postURL: manifest?['postURL']?.toString() ?? '',
      sourceName: manifest?['sourceName']?.toString() ?? host,
      location: location,
      isSaf: isSaf,
      pages: [for (final n in pageNames) filesByName[n]!],
      savedAt: (manifest?['savedAt'] as num?)?.toInt() ?? savedAt,
    );
  }

  /// Files named `<source>_<n>.<ext>` in the download root, one entry per
  /// source, pages in numeric order. These predate folders and cannot be
  /// told apart by book — that information was never written.
  @visibleForTesting
  static List<DoujinDownloadEntry> looseGroups(
    Map<String, String> rootFilesByName, {
    required String location,
    required bool isSaf,
  }) {
    final Set<String> names = {
      ...legacySourceNames,
      for (final b in _configuredDoujinNames()) b,
    };
    final Map<String, List<(int, String)>> groups = {};
    final RegExp pattern = RegExp(r'^(.+?)_(\d+)\.([A-Za-z0-9]+)$');
    for (final name in rootFilesByName.keys) {
      final m = pattern.firstMatch(name);
      if (m == null) continue;
      final String source = m.group(1)!;
      if (!names.contains(source.toLowerCase())) continue;
      if (!_imageExts.contains(m.group(3)!.toLowerCase())) continue;
      groups.putIfAbsent(source, () => []).add((int.parse(m.group(2)!), name));
    }
    return [
      for (final e in groups.entries)
        DoujinDownloadEntry(
          title: '${e.key} — loose pages (saved before folders)',
          host: e.key,
          serverId: '',
          postURL: '',
          sourceName: e.key,
          location: location,
          isSaf: isSaf,
          pages: [for (final p in (e.value..sort((a, b) => a.$1.compareTo(b.$1)))) rootFilesByName[p.$2]!],
          savedAt: 0,
          isLoose: true,
        ),
    ];
  }

  static Iterable<String> _configuredDoujinNames() {
    try {
      return [
        for (final b in SettingsHandler.instance.booruList)
          if (DoujinDataHandler.isDoujinBooru(b) && (b.name?.isNotEmpty ?? false)) b.name!.toLowerCase(),
      ];
    } catch (_) {
      return const [];
    }
  }

  static bool _isImageName(String name) {
    final int dot = name.lastIndexOf('.');
    return dot > 0 && _imageExts.contains(name.substring(dot + 1).toLowerCase());
  }

  /// `2.jpg` before `10.jpg`.
  @visibleForTesting
  static int naturalCompare(String a, String b) {
    final RegExp num = RegExp(r'\d+');
    final int? na = int.tryParse(num.firstMatch(a)?.group(0) ?? '');
    final int? nb = int.tryParse(num.firstMatch(b)?.group(0) ?? '');
    if (na != null && nb != null && na != nb) return na.compareTo(nb);
    return a.compareTo(b);
  }

  /// Removes a book folder. Loose groups are not deleted from here (they
  /// share the root with every other download).
  Future<bool> delete(DoujinDownloadEntry entry) async {
    if (entry.isLoose) return false;
    try {
      if (entry.isSaf) return await ServiceHandler.deleteSAFTree(entry.location);
      final Directory dir = Directory(entry.location);
      if (await dir.exists()) await dir.delete(recursive: true);
      return true;
    } catch (e, s) {
      Logger.Inst().log('delete failed: $e', 'DoujinDownloadHandler', 'delete', LogTypes.exception, s: s);
      return false;
    }
  }

  /// The configured source an entry belongs to, or a stand-in so the reader
  /// can still open it after the source was removed.
  Booru booruFor(DoujinDownloadEntry entry) {
    for (final b in SettingsHandler.instance.booruList) {
      if (DoujinDataHandler.isDoujinBooru(b) && DoujinDataHandler.hostOf(b) == entry.host) return b;
    }
    for (final b in SettingsHandler.instance.booruList) {
      if (DoujinDataHandler.isDoujinBooru(b) && (b.name ?? '').toLowerCase() == entry.sourceName.toLowerCase()) return b;
    }
    return Booru(entry.sourceName, null, '', entry.host.contains('.') ? 'https://${entry.host}' : '', '');
  }

  void _log(String message) =>
      Logger.Inst().log('doujin downloads: $message', 'DoujinDownloadHandler', 'log', LogTypes.booruHandlerInfo);
}
