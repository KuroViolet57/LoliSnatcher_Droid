import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/boorus/furaffinity_handler.dart';
import 'package:lolisnatcher/src/boorus/furaffinity_parser.dart';
import 'package:lolisnatcher/src/boorus/furaffinity_query.dart';
import 'package:lolisnatcher/src/boorus/linked_media.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/modular_ui.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/pages/gallery_view_page.dart';
import 'package:lolisnatcher/src/pages/linked_media_page.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';

/// Opens a link a post's description gives for its animation (r49).
class LinkedMediaOpener {
  const LinkedMediaOpener._();

  /// The one-off tab that finds a linked post by id (r52): its first page, as
  /// a new tab searches it, without the source's default filters ("Not found
  /// on e621" for a post that exists: the id lookup carried them).
  static SearchTab prepareTab(LinkedMedia media) {
    final SearchTab tab = SearchTab(media.booru!, null, media.searchTerm);
    tab.booruHandler
      ..applySourceSettings = false
      ..pageNum += 1;
    return tab;
  }

  /// A linked post the source hides (the "filter hated" setting) still opens;
  /// it stays blurred where the source blurs it.
  static void showFetched(BooruHandler handler) {
    if (handler.filteredFetched.isEmpty && handler.fetched.isNotEmpty) {
      handler.filteredFetched.addAll(handler.fetched);
    }
  }

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
    final SearchTab tab = prepareTab(media);
    try {
      await tab.booruHandler.search(media.searchTerm, null);
    } catch (_) {}
    showFetched(tab.booruHandler);
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
            title: Text(items[i].title, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(items[i].destination, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Badge(items[i].badge),
                const Icon(Symbols.chevron_right_rounded),
              ],
            ),
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
                const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 24), child: Text('The description has no media links.'))
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

/// The viewer's link button (r49; r52: for any post with media links, in the
/// share button's place).
class LinkedMediaButton {
  const LinkedMediaButton._();

  /// The post's description has been read and links to media: a GIF or a
  /// video can link its full or sound version too.
  static bool offerFor(BooruItem item) => ModularUi.isOn(ModularUi.viewerLinkedMedia) && LinkedMediaStore.hasLinks(item.postURL);

  /// The media links of [item]'s description, read once per session.
  static Future<List<LinkedMedia>> linksFor(FurAffinityHandler handler, BooruItem item) async {
    final List<LinkedMedia>? known = LinkedMediaStore.linksFor(item.postURL);
    if (known != null) return known;
    try {
      final FurAffinitySubmission? s = FurAffinityParser.submission(await handler.fetchPage(item.postURL));
      final List<LinkedMedia> links = s == null
          ? const []
          : LinkedMediaResolver.mediaLinksIn(
              s.descriptionHtml,
              SettingsHandler.instance.booruList,
              base: FurAffinityQuery.site,
              self: item.postURL,
            );
      LinkedMediaStore.remember(item.postURL, links);
      return links;
    } catch (_) {
      return const [];
    }
  }
}

/// What a link is, at a glance: In app, Video, Animation or Web (r50).
class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.onSecondaryContainer)),
    );
  }
}
