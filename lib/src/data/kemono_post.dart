import 'package:lolisnatcher/src/boorus/kemono_site.dart';
import 'package:lolisnatcher/src/data/site_profiles/kemono_profile.dart';

enum KemonoFileKind { image, video, other }

/// One file of a post, with what the site's post page knows about it.
class KemonoPostFile {
  const KemonoPostFile({
    required this.name,
    required this.path,
    required this.kind,
    required this.extension,
    this.server,
    this.site = KemonoSite.kemono,
  });

  /// The name the creator gave the file (`picture1.png`, `Pack.rar`).
  final String name;

  /// `/ab/cd/<sha256>.<stored ext>` — the stored extension can be `.bin` for
  /// an archive; [extension] is the real one.
  final String path;
  final KemonoFileKind kind;
  final String extension;

  /// The host the detail names for this file, when it does.
  final String? server;
  final KemonoSite site;

  String get url => site.fileUrl(path, server: server);

  String? get thumbUrl => kind == KemonoFileKind.image ? site.thumbUrl(path) : null;

  bool get isDisplayable => kind != KemonoFileKind.other;

  static String extensionOf(String nameOrPath) {
    final int dot = nameOrPath.lastIndexOf('.');
    if (dot < 0 || dot == nameOrPath.length - 1) return '';
    final String ext = nameOrPath.substring(dot + 1).toLowerCase();
    return RegExp(r'^[a-z0-9]{1,8}$').hasMatch(ext) ? ext : '';
  }

  static KemonoFileKind kindOf(String extension) {
    if (KemonoProfile.videoExtensions.contains(extension)) return KemonoFileKind.video;
    if (KemonoProfile.displayableExtensions.contains(extension)) return KemonoFileKind.image;
    return KemonoFileKind.other;
  }
}

class KemonoPostEmbed {
  const KemonoPostEmbed({this.url, this.subject, this.description});

  final String? url;
  final String? subject;
  final String? description;

  bool get isEmpty => (url ?? '').isEmpty && (subject ?? '').isEmpty && (description ?? '').isEmpty;
}

/// A post as the site's post page shows it: the detail envelope
/// (`post` + top-level `attachments`/`previews`/`videos`) decoded once.
class KemonoPost {
  const KemonoPost({
    required this.service,
    required this.user,
    required this.id,
    required this.title,
    required this.contentHtml,
    required this.files,
    required this.tags,
    this.embed,
    this.poll,
    this.published,
    this.edited,
    this.added,
    this.next,
    this.prev,
    this.hasFull,
    this.site = KemonoSite.kemono,
  });

  final String service;
  final String user;
  final String id;
  final String title;

  /// Raw HTML from the API; [contentForHtml] makes it renderable.
  final String contentHtml;

  /// Cover first, then the attachments in the post's order, each path once.
  final List<KemonoPostFile> files;
  final List<String> tags;
  final KemonoPostEmbed? embed;
  final Map<String, dynamic>? poll;
  final String? published;
  final String? edited;
  final String? added;
  final String? next;
  final String? prev;

  /// pawchive says whether it holds the full post; null where the site
  /// does not say (kemono).
  final bool? hasFull;
  final KemonoSite site;

  String get postUrl => site.postUrl(service, user, id);

  bool get isPreviewOnly => hasFull == false;

  String get serverId => '$service:$user:$id';

  List<KemonoPostFile> get images => files.where((f) => f.kind == KemonoFileKind.image).toList();

  List<KemonoPostFile> get videos => files.where((f) => f.kind == KemonoFileKind.video).toList();

  List<KemonoPostFile> get attachments => files.where((f) => f.kind == KemonoFileKind.other).toList();

  /// What the viewer can show, in order — the files overlay's list.
  List<KemonoPostFile> get displayable => files.where((f) => f.isDisplayable).toList();

  bool get hasContent => contentHtml.trim().isNotEmpty;

  /// The content with the site's relative file links made absolute on the
  /// file hosts, so an `<img src="/data/…">` renders and a link opens.
  String contentForHtml() {
    return contentHtml.replaceAllMapped(
      RegExp('(src|href)=(["\'])/data(/[^"\']+)'),
      (m) => '${m[1]}=${m[2]}${site.fileUrl(m[3]!)}',
    );
  }

  /// kemono's envelope `{post, attachments, previews, videos}` or pawchive's
  /// bare post.
  static KemonoPost? fromDetail(Map detail, {KemonoSite site = KemonoSite.kemono}) {
    final dynamic wrapped = detail['post'];
    final Map? post = wrapped is Map ? wrapped : (detail['id'] != null ? detail : null);
    if (post == null) return null;
    final String service = post['service']?.toString() ?? '';
    final String user = post['user']?.toString() ?? '';
    final String id = post['id']?.toString() ?? '';
    if (service.isEmpty || user.isEmpty || id.isEmpty) return null;

    // The detail names a host and the real name/extension per file in its
    // top-level lists; the post's own `file`/`attachments` carry the order.
    final Map<String, String> servers = {};
    final Map<String, String> realExt = {};
    for (final key in ['attachments', 'previews', 'videos']) {
      final list = detail[key];
      if (list is! List) continue;
      for (final e in list) {
        if (e is! Map) continue;
        final String path = e['path']?.toString() ?? '';
        if (path.isEmpty) continue;
        final String server = e['server']?.toString() ?? '';
        if (server.isNotEmpty) servers[path] = server;
        final String ne = e['name_extension']?.toString() ?? '';
        if (ne.isNotEmpty) realExt[path] = ne.replaceFirst('.', '').toLowerCase();
      }
    }

    final List<KemonoPostFile> files = [];
    final Set<String> seen = {};
    void add(dynamic entry) {
      if (entry is! Map) return;
      final String path = entry['path']?.toString() ?? '';
      if (path.isEmpty || !seen.add(path)) return;
      final String name = entry['name']?.toString().trim() ?? '';
      final String ext = realExt[path] ?? (KemonoPostFile.extensionOf(name).isNotEmpty ? KemonoPostFile.extensionOf(name) : KemonoPostFile.extensionOf(path));
      files.add(
        KemonoPostFile(
          name: name.isEmpty ? path.substring(path.lastIndexOf('/') + 1) : name,
          path: path,
          kind: KemonoPostFile.kindOf(ext),
          extension: ext,
          server: servers[path],
          site: site,
        ),
      );
    }

    add(post['file']);
    final attachments = post['attachments'];
    if (attachments is List) attachments.forEach(add);

    KemonoPostEmbed? embed;
    final rawEmbed = post['embed'];
    if (rawEmbed is Map && rawEmbed.isNotEmpty) {
      embed = KemonoPostEmbed(
        url: rawEmbed['url']?.toString(),
        subject: rawEmbed['subject']?.toString(),
        description: rawEmbed['description']?.toString(),
      );
      if (embed.isEmpty) embed = null;
    }

    final rawPoll = post['poll'];
    final rawTags = post['tags'];
    return KemonoPost(
      service: service,
      user: user,
      id: id,
      title: post['title']?.toString().trim() ?? '',
      contentHtml: post['content']?.toString() ?? '',
      files: files,
      tags: rawTags is List ? [for (final t in rawTags) t.toString().trim()].where((t) => t.isNotEmpty).toList() : const [],
      embed: embed,
      poll: rawPoll is Map ? Map<String, dynamic>.from(rawPoll) : null,
      published: post['published']?.toString(),
      edited: post['edited']?.toString(),
      added: post['added']?.toString(),
      next: post['next']?.toString(),
      prev: post['prev']?.toString(),
      hasFull: post['has_full'] is bool ? post['has_full'] as bool : null,
      site: site,
    );
  }
}
