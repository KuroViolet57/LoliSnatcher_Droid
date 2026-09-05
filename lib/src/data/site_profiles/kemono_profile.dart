import 'dart:convert';

import 'package:lolisnatcher/src/boorus/kemono_api.dart';
import 'package:lolisnatcher/src/boorus/kemono_site.dart';
import 'package:lolisnatcher/src/data/kemono_post.dart';
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
  Set<String> get hosts => const {'kemono.cr', 'kemono.su', 'kemono.party', 'pawchive.pw'};

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
    return '${KemonoSite.of(booru).creatorPath(ref.service, ref.user)}/post/${ref.post}';
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
      return filesFromDetail(decoded, site: KemonoSite.of(booru));
    } catch (_) {
      return null;
    }
  }

  static List<PostFile>? filesFromDetail(Map detail, {KemonoSite site = KemonoSite.kemono}) {
    final KemonoPost? post = KemonoPost.fromDetail(detail, site: site);
    if (post == null || post.files.isEmpty) return null;
    return postFilesOf(post);
  }

  /// Every file of [post] as the viewer's [PostFile]s — the displayable ones
  /// in order for the carousel, the rest named so the post page lists them.
  static List<PostFile> postFilesOf(KemonoPost post) {
    return [
      for (final KemonoPostFile f in post.files)
        PostFile(
          url: f.url,
          isVideo: f.kind == KemonoFileKind.video,
          thumbnailUrl: f.thumbUrl,
          name: f.name,
          isDisplayable: f.isDisplayable,
        ),
    ];
  }
}
