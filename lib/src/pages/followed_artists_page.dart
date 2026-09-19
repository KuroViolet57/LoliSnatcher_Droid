import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/handlers/followed_artists_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/pages/tag_hub_page.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

/// The dedicated "Followed artists" screen: every tag you followed from an
/// artist hub, each row opening that artist's hub. Follows are stored as
/// labelled pinned tags (see [FollowedArtistsHandler]) but deliberately kept
/// out of the pinned-tags UIs — this page is their home.
class FollowedArtistsPage extends StatefulWidget {
  const FollowedArtistsPage({super.key});

  @override
  State<FollowedArtistsPage> createState() => _FollowedArtistsPageState();
}

class _FollowedArtistsPageState extends State<FollowedArtistsPage> {
  List<String> _followed = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await FollowedArtistsHandler.listFollowed();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (mounted) {
      setState(() {
        _followed = list;
        _loading = false;
      });
    }
  }

  Future<void> _unfollow(String tag) async {
    await FollowedArtistsHandler.unfollow(tag);
    await _load();
  }

  Future<void> _openHub(String tag) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TagHubPage(tag: tag)),
    );
    // Re-check on return — the hub's own Follow button may have unfollowed.
    await _load();
  }

  Widget _row(String tag) {
    final theme = Theme.of(context);
    final Color dot = TagHandler.instance.getTag(tag).getColour() ?? const Color(0xFFE890A5);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openHub(tag),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.only(left: 12, right: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: dot.withValues(alpha: 0.16),
                shape: BoxShape.circle,
                border: Border.all(color: dot.withValues(alpha: 0.5)),
              ),
              child: Icon(Symbols.brush_rounded, size: 16, color: dot),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  tag.replaceAll('_', ' '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Unfollow',
              icon: Icon(
                Symbols.notifications_off_rounded,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              onPressed: () => _unfollow(tag),
            ),
            Icon(Symbols.chevron_right_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: const SettingsAppBar(title: 'Followed artists'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _followed.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Symbols.artist_rounded,
                      size: 42,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No followed artists yet',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Open an artist tag's menu → Artist hub → Follow to keep them here.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [for (final tag in _followed) _row(tag)],
            ),
    );
  }
}
