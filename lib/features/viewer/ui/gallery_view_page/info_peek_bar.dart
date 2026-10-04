part of '../gallery_view_page.dart';

/// The collapsed "peek" bar at the bottom of the viewer: artist + tag-count
/// chips and a swipe-up hint. Tapping it opens the info sheet.
class _InfoPeekBar extends StatelessWidget {
  const _InfoPeekBar({required this.tab, required this.page, required this.onTap});

  final SearchTab tab;
  final ValueNotifier<int> page;
  final VoidCallback onTap;

  String? _artistOf(BooruItem item) => infoPeekBarArtistOf(item);

  Widget _chip(BuildContext context, IconData icon, String label, Color? color) {
    final Color fg = color ?? const Color(0xFFDDD5EA);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1622),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFF2E2940)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: page,
      builder: (context, p, _) {
        final items = tab.booruHandler.filteredFetched;
        if (items.isEmpty || p >= items.length) return const SizedBox.shrink();
        final item = items[p];
        final String? artist = _artistOf(item);
        final int tagCount = item.tagsList.length;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF0E0C13),
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              border: Border(top: BorderSide(color: Color(0xFF2E2940))),
            ),
            padding: EdgeInsets.fromLTRB(14, 6, 14, MediaQuery.viewPaddingOf(context).bottom + 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4.5,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A4260),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                Row(
                  children: [
                    if (artist != null) ...[
                      Flexible(
                        child: _chip(
                          context,
                          Symbols.brush_rounded,
                          artist.replaceAll('_', ' '),
                          TagType.artist.getColour(),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    _chip(context, Symbols.sell_rounded, '$tagCount tags', null),
                    const Spacer(),
                    const Text(
                      'swipe up',
                      style: TextStyle(color: Color(0xFF8A80A0), fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                    const Icon(Symbols.keyboard_arrow_up_rounded, size: 18, color: Color(0xFF8A80A0)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
