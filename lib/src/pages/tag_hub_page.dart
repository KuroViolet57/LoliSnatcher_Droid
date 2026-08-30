import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/followed_artists_handler.dart';
import 'package:lolisnatcher/src/handlers/doujin_data_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/gallery/tag_view.dart';
import 'package:lolisnatcher/src/widgets/image/booru_favicon.dart';

/// A dedicated page for any tag: how many matching posts are in your
/// favourites, and a per-booru strip of the tag's content across every
/// configured booru — each strip translating the tag into that booru's own
/// spelling via [TagContentPreview]'s cross-booru alias resolution, and
/// collapsing entirely when a booru has nothing for it.
///
/// Artist tags additionally get a Follow toggle ("Artist hub"); every other
/// type renders the same page as a plain "Tag hub".
///
/// Opened from the tag action sheet and the floating preview window.
class TagHubPage extends StatefulWidget {
  const TagHubPage({
    required this.tag,
    this.originBooru,
    super.key,
  });

  /// The tag as written on the booru it was tapped from.
  final String tag;

  /// The booru the tag came from — used as the translation origin.
  final Booru? originBooru;

  @override
  State<TagHubPage> createState() => _TagHubPageState();
}

class _TagHubPageState extends State<TagHubPage> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final SearchHandler searchHandler = SearchHandler.instance;

  bool _following = false;
  bool _followLoaded = false;
  int _favCount = 0;

  bool get _isArtist => TagHandler.instance.getTag(widget.tag).tagType.isArtist;

  // The origin tab drives TagContentPreview's alias translation (origin booru
  // vs each target booru). Reuses the current tab when available.
  SearchTab? get _originTab => searchHandler.tabs.isNotEmpty ? searchHandler.currentTab : null;

  // Real (non-virtual) boorus to show the tag across — in the ORIGIN's
  // domain only: a hub opened from a doujin source shows doujin sources, a
  // booru hub shows boorus. The two never mix.
  List<Booru> get _boorus => settingsHandler.booruList
      .where(
        (b) =>
            b.type != null &&
            !b.type!.isLocalDb &&
            !b.type!.isForYou &&
            !b.type!.isMerge &&
            DoujinDataHandler.isDoujinBooru(b) == _isDoujinOrigin,
      )
      .toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _isDoujinOrigin => DoujinDataHandler.isDoujinBooru(widget.originBooru);

  Future<void> _load() async {
    // Follows from a doujin source live in the doujin store, scoped to that
    // source — booru follows never mix in.
    final bool following = _isDoujinOrigin
        ? DoujinDataHandler.instance.isFollowed(widget.tag, widget.originBooru)
        : _isArtist && await FollowedArtistsHandler.isFollowed(widget.tag);
    // The booru favourites DB says nothing about a doujin tag, and the doujin
    // store keeps no tag index — so a doujin hub shows no favourites stat at
    // all rather than a booru-derived (or invented) number.
    int fav = 0;
    if (!_isDoujinOrigin) {
      try {
        fav = await settingsHandler.dbHandler.searchDBCount(widget.tag);
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _following = following;
        _followLoaded = true;
        _favCount = fav;
      });
    }
  }

  Future<void> _toggleFollow() async {
    final bool now = _isDoujinOrigin
        ? DoujinDataHandler.instance.toggleFollow(widget.tag, widget.originBooru)
        : await FollowedArtistsHandler.toggle(widget.tag);
    if (mounted) setState(() => _following = now);
  }

  IconData get _typeIcon {
    final TagType type = TagHandler.instance.getTag(widget.tag).tagType;
    switch (type) {
      case TagType.artist:
        return Symbols.brush_rounded;
      case TagType.character:
        return Symbols.person_rounded;
      case TagType.copyright:
        return Symbols.copyright_rounded;
      case TagType.species:
        return Symbols.pets_rounded;
      case TagType.meta:
        return Symbols.info_rounded;
      case TagType.none:
        return Symbols.sell_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String display = widget.tag.replaceAll('_', ' ');
    final Color typeColor = TagHandler.instance.getTag(widget.tag).getColour() ?? const Color(0xFFB9A0E8);
    final String typeName = TagHandler.instance.getTag(widget.tag).tagType.locName;
    final boorus = _boorus;

    return Scaffold(
      appBar: SettingsAppBar(title: _isArtist ? 'Artist hub' : 'Tag hub'),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // ── header card ──────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                        border: Border.all(color: typeColor.withValues(alpha: 0.5), width: 1.5),
                      ),
                      child: Icon(_typeIcon, color: typeColor, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            display,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            typeName,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    // Follow / Following toggle — artists only.
                    if (_isArtist) ...[
                      Expanded(
                        child: _FollowButton(
                          following: _following,
                          enabled: _followLoaded,
                          onTap: _toggleFollow,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    // Favourites stat (booru hubs only — see _load).
                    if (!_isDoujinOrigin) ...[
                      _StatChip(
                        icon: Symbols.favorite_rounded,
                        iconColor: const Color(0xFFF0708A),
                        label: _favCount == 1 ? '1 fav' : '$_favCount favs',
                      ),
                      const SizedBox(width: 8),
                    ],
                    _StatChip(
                      icon: Symbols.dns_rounded,
                      iconColor: theme.colorScheme.onSurfaceVariant,
                      label: '${boorus.length} boorus',
                    ),
                  ],
                ),
              ],
            ),
          ),
          // ── per-booru strips ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'ACROSS YOUR BOORUS',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (boorus.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No searchable boorus configured.',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else
            // The favicon+name header rides INSIDE the strip so a booru with
            // no results for this tag collapses away, header and all.
            for (final booru in boorus)
              TagContentPreview(
                key: ValueKey('taghub-${booru.name}-${booru.type}-${widget.tag}'),
                tag: widget.tag,
                boorus: [booru],
                parentTab: _originTab,
                compact: true,
                compactTitle: booru.name,
                hideWhenEmpty: true,
                header: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      BooruFavicon(booru, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        booru.name ?? '',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _FollowButton extends StatelessWidget {
  const _FollowButton({
    required this.following,
    required this.enabled,
    required this.onTap,
  });

  final bool following;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color bg = following ? theme.colorScheme.surfaceContainerHighest : theme.colorScheme.secondary;
    final Color fg = following ? theme.colorScheme.onSurface : theme.colorScheme.onSecondary;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: following ? theme.colorScheme.outlineVariant : theme.colorScheme.secondary,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                following ? Symbols.notifications_active_rounded : Symbols.add_rounded,
                size: 18,
                fill: following ? 1 : 0,
                color: fg,
              ),
              const SizedBox(width: 7),
              Text(
                following ? 'Following' : 'Follow',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.iconColor, required this.label});

  final IconData icon;
  final Color iconColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
