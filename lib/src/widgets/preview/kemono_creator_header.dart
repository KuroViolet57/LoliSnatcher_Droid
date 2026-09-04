import 'dart:async';

import 'package:flutter/material.dart';

import 'package:get/get.dart' hide ContextExt, FirstWhereOrNullExt;
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/boorus/kemono_api.dart';
import 'package:lolisnatcher/src/boorus/kemono_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/kemono_creator.dart';
import 'package:lolisnatcher/src/handlers/kemono_creator_store.dart';
import 'package:lolisnatcher/src/handlers/kemono_session_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/pages/kemono_artists_page.dart';
import 'package:lolisnatcher/src/pages/kemono_messages_pages.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';

/// The creator's card above a creator tab's grid — banner, avatar, name,
/// service, post count, last update — with the site's per-creator actions:
/// favourite, announcements, DMs, tags. Empty on every other tab.
class KemonoCreatorHeader extends StatelessWidget {
  const KemonoCreatorHeader({required this.tab, super.key});

  final SearchTab tab;

  @override
  Widget build(BuildContext context) {
    final handler = tab.booruHandler;
    if (handler is! KemonoHandler) return const SizedBox.shrink();
    final creator = handler.currentCreator;
    if (creator == null) return const SizedBox.shrink();
    return _KemonoCreatorHeaderBody(handler: handler, booru: tab.selectedBooru.value, creator: creator);
  }
}

class _KemonoCreatorHeaderBody extends StatefulWidget {
  const _KemonoCreatorHeaderBody({required this.handler, required this.booru, required this.creator});

  final KemonoHandler handler;
  final Booru booru;
  final ({String service, String id}) creator;

  @override
  State<_KemonoCreatorHeaderBody> createState() => _KemonoCreatorHeaderBodyState();
}

class _KemonoCreatorHeaderBodyState extends State<_KemonoCreatorHeaderBody> {
  KemonoCreator? _indexed;

  bool get _signedIn => KemonoSessionHandler.instance.hasSession(widget.booru);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant _KemonoCreatorHeaderBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.creator != widget.creator) unawaited(_load());
  }

  Future<void> _load() async {
    _indexed = await KemonoCreatorStore.instance.get(widget.creator.service, widget.creator.id);
    if (_signedIn) await widget.handler.loadFavouriteCreatorKeys();
    if (mounted) setState(() {});
  }

  Future<void> _toggleFavourite(bool now) async {
    final (bool ok, String message) = await widget.handler.setCreatorFavourite(
      widget.creator.service,
      widget.creator.id,
      now,
    );
    if (!mounted) return;
    FlashElements.showSnackbar(
      context: context,
      title: Text(ok ? (now ? 'Favourited' : 'Unfavourited') : 'kemono did not accept that'),
      content: Text(message),
      sideColor: ok ? Colors.green : Colors.red,
      duration: const Duration(seconds: 3),
    );
  }

  Future<void> _pickTag() async {
    final String? term = await KemonoCreatorTagsSheet.pick(context, widget.booru);
    if (term == null || term.isEmpty) return;
    final SearchHandler search = SearchHandler.instance;
    search.addTagToSearch(term);
    unawaited(search.searchAction(search.searchTextController.text, null));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.creator;
    final String key = '${c.service}:${c.id}';
    return Obx(() {
      final Map<String, dynamic>? profile = widget.handler.creatorProfile.value;
      final bool favourite = widget.handler.favouriteCreatorKeys.contains(key);
      final String name = profile?['name']?.toString() ?? _indexed?.name ?? key;
      final int posts = int.tryParse(profile?['post_count']?.toString() ?? '') ?? 0;
      final int updated = KemonoCreator.epochOf(profile?['updated']) != 0
          ? KemonoCreator.epochOf(profile?['updated'])
          : (_indexed?.updated ?? 0);
      final String updatedText = updated == 0
          ? ''
          : DateFormat.yMMMd().format(DateTime.fromMillisecondsSinceEpoch(updated * 1000));
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: ColoredBox(
          color: theme.colorScheme.surfaceContainer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 110,
                width: double.infinity,
                child: Image.network(
                  KemonoApi.bannerUrl(c.service, c.id),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => DecoratedBox(
                    decoration: BoxDecoration(color: theme.colorScheme.primaryContainer),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                          foregroundImage: NetworkImage(KemonoApi.iconUrl(c.service, c.id)),
                          onForegroundImageError: (_, _) {},
                          child: Text(name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?'),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                              Text(
                                [
                                  KemonoCreatorCard.serviceInitials[c.service] ?? c.service,
                                  if (posts > 0) '${posts.toShortString()} posts',
                                  if ((_indexed?.favorited ?? 0) > 0) '${_indexed!.favorited.toShortString()} favourites',
                                  if (updatedText.isNotEmpty) 'updated $updatedText',
                                ].join(' · '),
                                maxLines: 2,
                                style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (_signedIn)
                          ActionChip(
                            avatar: Icon(favourite ? Symbols.favorite_rounded : Symbols.favorite_border_rounded, fill: favourite ? 1 : 0, size: 18, color: const Color(0xFFF0708A)),
                            label: Text(favourite ? 'Favourited' : 'Favourite'),
                            onPressed: () => unawaited(_toggleFavourite(!favourite)),
                          ),
                        ActionChip(
                          avatar: const Icon(Symbols.campaign_rounded, size: 18),
                          label: const Text('Announcements'),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => KemonoAnnouncementsPage(booru: widget.booru, service: c.service, id: c.id)),
                          ),
                        ),
                        ActionChip(
                          avatar: const Icon(Symbols.mail_rounded, size: 18),
                          label: const Text('DMs'),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => KemonoDmsPage(booru: widget.booru, creator: c)),
                          ),
                        ),
                        ActionChip(
                          avatar: const Icon(Symbols.sell_rounded, size: 18),
                          label: const Text('Tags'),
                          onPressed: () => unawaited(_pickTag()),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
