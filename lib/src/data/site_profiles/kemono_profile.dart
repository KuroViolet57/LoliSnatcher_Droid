import 'dart:convert';

import 'package:lolisnatcher/src/boorus/kemono_api.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/site_profile.dart';

/// kemono.cr's per-post file list: one post holds a cover `file` plus any
/// number of `attachments`, all named in the post detail
/// (`/api/v1/{service}/user/{id}/post/{post}`) together with the server that
/// holds each one. The app's handler carries the post's identity in
/// `serverId` as `service:user:post`.
class KemonoProfile extends SiteProfile {
  const KemonoProfile();

  @override
  Set<String> get hosts => const {'kemono.cr', 'kemono.su', 'kemono.party'};

  @override
  String get id => 'kemono';

  @override
  List<String>? animatedFilters() => const [];

  @override
  bool get hasMultipleFilesPerPost => true;

  /// The post detail needs the API's Accept header, not a browser's.
  @override
  Map<String, String> postFilesHeaders(Booru booru) => KemonoApi.headers(booru);

  static ({String service, String user, String post})? splitId(String? serverId) {
    if (serverId == null) return null;
    final List<String> parts = serverId.split(':');
    if (parts.length != 3 || parts.any((p) => p.isEmpty)) return null;
    return (service: parts[0], user: parts[1], post: parts[2]);
  }

  @override
  String? postFilesUrl(Booru booru, BooruItem item) {
    final ref = splitId(item.serverId);
    if (ref == null) return null;
    return '${KemonoApi.creatorPath(ref.service, ref.user)}/post/${ref.post}';
  }

  static const Set<String> videoExtensions = {'mp4', 'webm', 'm4v', 'mov', 'mkv', 'avi'};

  /// What the viewer can show (`MediaType.fromExtension`); the cover is the
  /// first such file, so a post whose main file is a zip or a psd still opens
  /// on its first picture.
  static const Set<String> displayableExtensions = {'jpg', 'jpeg', 'png', 'webp', 'avif', 'gif', 'mp4', 'webm'};

  static String coverPath(List<String> paths) {
    for (final String p in paths) {
      final int dot = p.lastIndexOf('.');
      if (dot >= 0 && displayableExtensions.contains(p.substring(dot + 1).toLowerCase())) return p;
    }
    return paths.first;
  }

  static bool isVideoPath(String path) {
    final int dot = path.lastIndexOf('.');
    if (dot < 0) return false;
    return videoExtensions.contains(path.substring(dot + 1).toLowerCase());
  }

  /// Cover first, then the attachments, each once. A file's server comes
  /// from the detail's `attachments`/`previews`/`videos` when named there,
  /// which skips the `/data` redirect hop.
  @override
  List<PostFile>? parsePostFiles(String body, Booru booru) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      return filesFromDetail(decoded);
    } catch (_) {
      return null;
    }
  }

  static List<PostFile>? filesFromDetail(Map detail) {
    final post = detail['post'];
    if (post is! Map) return null;
    final Map<String, String> servers = {};
    for (final key in ['attachments', 'previews', 'videos']) {
      final list = detail[key];
      if (list is! List) continue;
      for (final e in list) {
        if (e is! Map) continue;
        final String path = e['path']?.toString() ?? '';
        final String server = e['server']?.toString() ?? '';
        if (path.isNotEmpty && server.isNotEmpty) servers[path] = server;
      }
    }
    final List<String> paths = [];
    final Set<String> seen = {};
    void add(dynamic entry) {
      if (entry is! Map) return;
      final String path = entry['path']?.toString() ?? '';
      if (path.isEmpty || !seen.add(path)) return;
      paths.add(path);
    }

    add(post['file']);
    final attachments = post['attachments'];
    if (attachments is List) attachments.forEach(add);
    if (paths.isEmpty) return null;
    return [
      for (final String path in paths)
        PostFile(
          url: KemonoApi.fileUrl(path, server: servers[path]),
          isVideo: isVideoPath(path),
          thumbnailUrl: isVideoPath(path) ? null : KemonoApi.thumbUrl(path),
        ),
    ];
  }
}
