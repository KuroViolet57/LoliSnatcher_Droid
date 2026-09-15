import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/boorus/furaffinity_handler.dart';
import 'package:lolisnatcher/src/boorus/furaffinity_parser.dart';
import 'package:lolisnatcher/src/boorus/furaffinity_query.dart';
import 'package:lolisnatcher/src/boorus/linked_media.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/pages/flash_player_page.dart';
import 'package:lolisnatcher/src/pages/gallery_view_page.dart';
import 'package:lolisnatcher/src/pages/linked_media_page.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';

/// Opens a link a post's description gives for its animation (r49).
class LinkedMediaOpener {
  const LinkedMediaOpener._();

  /// A post on an installed source opens in the app's viewer, on top of the
  /// current page (searched by id, the way the floating tag preview opens
  /// its own viewer); a file or any other page opens in the linked media
  /// player. A post the source does not find opens as a page.
  static Future<void> open(BuildContext context, LinkedMedia media, {String? title}) async {
    if (media.kind != LinkedMediaKind.sourcePost) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => LinkedMediaPage(media: media, title: title)));
      return;
    }
    final Booru booru = media.booru!;
    final SearchTab tab = SearchTab(booru, null, media.searchTerm);
    tab.booruHandler.pageNum++;
    try {
      await tab.booruHandler.search(media.searchTerm, null);
    } catch (_) {}
    if (!context.mounted) return;
    if (tab.booruHandler.filteredFetched.isEmpty) {
      FlashElements.showSnackbar(
        context: context,
        title: Text('Not found on ${booru.name ?? media.host}'),
        content: const Text('Opening the link instead.'),
      );
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LinkedMediaPage(media: LinkedMedia(url: media.url, kind: LinkedMediaKind.page), title: title),
        ),
      );
      return;
    }
    final GlobalKey viewerKey = GlobalKey(debugLabel: 'viewer-linked-${booru.name}-${media.postId}');
    ViewerHandler.instance.addViewer(viewerKey);
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GalleryViewPage(key: viewerKey, tab: tab, initialIndex: 0, canSelect: false)),
    );
  }
}

/// The linked media of a post as tappable rows.
class LinkedMediaList extends StatelessWidget {
  const LinkedMediaList({required this.items, this.title, this.onOpen, super.key});

  final List<LinkedMedia> items;
  final String? title;

  /// Replaces the default opening (a sheet closes itself first).
  final ValueChanged<LinkedMedia>? onOpen;

  static IconData iconFor(LinkedMedia media) => switch (media.kind) {
    LinkedMediaKind.sourcePost => Symbols.photo_library_rounded,
    LinkedMediaKind.media => media.isImage ? Symbols.animated_images_rounded : Symbols.play_circle_rounded,
    LinkedMediaKind.page => Symbols.public_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < items.length; i++)
          ListTile(
            key: ValueKey('linked-media-$i'),
            leading: Icon(iconFor(items[i])),
            title: Text(items[i].label),
            subtitle: Text(items[i].url, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Symbols.chevron_right_rounded),
            onTap: () => onOpen != null ? onOpen!(items[i]) : LinkedMediaOpener.open(context, items[i], title: title),
          ),
      ],
    );
  }
}

/// The linked media of a post in a bottom sheet (the viewer's link button).
class LinkedMediaSheet {
  const LinkedMediaSheet._();

  static Future<void> show(BuildContext context, List<LinkedMedia> items, {String? title}) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Linked media', style: Theme.of(sheet).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ),
              if (items.isEmpty)
                const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 24), child: Text('The description has no links.'))
              else
                LinkedMediaList(
                  items: items,
                  title: title,
                  onOpen: (LinkedMedia media) {
                    Navigator.of(sheet).pop();
                    LinkedMediaOpener.open(context, media, title: title);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The viewer's link button for FurAffinity (r49).
class LinkedMediaButton {
  const LinkedMediaButton._();

  /// A post tagged as animated whose file is a still picture: its animation
  /// is usually behind a link in the description. A GIF, a video or a Flash
  /// post already is the animation.
  static bool offerFor(BooruItem item) {
    final MediaType type = item.mediaType.value;
    if (type.isVideo || type.isAnimation) return false;
    if (FlashPlayerPage.isFlash(item)) return false;
    return item.tagsList.any((t) => t.fullString.toLowerCase().contains('animat'));
  }

  static final Map<String, List<LinkedMedia>> _cache = {};

  /// The resolved links of [item]'s description, read once per session.
  static Future<List<LinkedMedia>> linksFor(FurAffinityHandler handler, BooruItem item) async {
    final List<LinkedMedia>? known = _cache[item.postURL];
    if (known != null) return known;
    try {
      final FurAffinitySubmission? s = FurAffinityParser.submission(await handler.fetchPage(item.postURL));
      return _cache[item.postURL] = [
        for (final String url in LinkedMediaResolver.linksIn(s?.descriptionHtml ?? '', base: FurAffinityQuery.site))
          LinkedMediaResolver.resolve(url, SettingsHandler.instance.booruList),
      ];
    } catch (_) {
      return const [];
    }
  }
}
