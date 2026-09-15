import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:get/get.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/theme_handler.dart';
import 'package:lolisnatcher/src/widgets/image/booru_favicon.dart';
import 'package:lolisnatcher/src/widgets/image/custom_network_image.dart';
import 'package:lolisnatcher/src/widgets/preview/flow_tab_carousel.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_selector.dart';

/// The tab pill (r38, experimental — Settings → User interface): a small
/// floating pill in the feed that says where you are ("3/45", with the
/// tab's cover) and is the quickest way to the tabs wherever the feed is
/// scrolled: tap for the tab strip in a sheet, swipe left or right to move
/// one tab over, long-press for the full tab manager. Borrowed from the
/// phone browsers' tab-count buttons and their swipe-the-address-bar tab
/// switching.
///
/// r40: it counts and swipes through the current tab's section only — the
/// doujin tabs from a doujin tab, the others from the rest, the tab
/// manager's own split — and, inside a [TabPillHost], a hold that turns into
/// a drag moves it.
class TabPill extends StatelessWidget {
  const TabPill({this.onMoveStart, this.onMoveUpdate, this.onMoveEnd, super.key});

  /// A hold began (set by [TabPillHost]).
  final VoidCallback? onMoveStart;

  /// The finger moved this far since the hold began.
  final ValueChanged<Offset>? onMoveUpdate;

  /// The finger was lifted.
  final VoidCallback? onMoveEnd;

  /// A hold that moved less than this is a plain long-press.
  static const double moveSlop = 12;

  static Future<void> openStrip(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (BuildContext ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 12),
          child: FlowTabCarousel(large: true, onPicked: () => Navigator.of(ctx).maybePop()),
        ),
      ),
    );
  }

  static void openManager(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TabManagerPage()));
  }

  void _step(int delta) {
    final SearchHandler searchHandler = SearchHandler.instance;
    final List<int> section = FlowTabCarousel.sectionIndexes(searchHandler.tabs, searchHandler.currentIndex);
    final int at = section.indexOf(searchHandler.currentIndex);
    if (at < 0) return;
    final int next = (at + delta).clamp(0, section.length - 1);
    if (next == at) return;
    ServiceHandler.vibrate(duration: 20);
    searchHandler.changeTabIndex(section[next], byUser: true);
  }

  @override
  Widget build(BuildContext context) {
    final SearchHandler searchHandler = SearchHandler.instance;
    final ThemeData theme = Theme.of(context);
    final bool movable = onMoveStart != null;
    return Obx(() {
      searchHandler.index.value;
      searchHandler.tabId.value;
      final List<SearchTab> tabs = searchHandler.tabs;
      if (tabs.isEmpty) return const SizedBox.shrink();
      final int index = searchHandler.currentIndex.clamp(0, tabs.length - 1);
      final SearchTab tab = tabs[index];
      final List<int> section = FlowTabCarousel.sectionIndexes(tabs, index);
      final String? cover = FlowTabCarousel.coverUrlOf(tab);
      return GestureDetector(
        key: const ValueKey('tab-pill'),
        behavior: HitTestBehavior.opaque,
        onTap: () => openStrip(context),
        onLongPress: movable
            ? null
            : () {
                ServiceHandler.vibrate(duration: 30);
                openManager(context);
              },
        onLongPressStart: movable
            ? (_) {
                ServiceHandler.vibrate(duration: 30);
                onMoveStart!();
              }
            : null,
        onLongPressMoveUpdate: movable ? (LongPressMoveUpdateDetails d) => onMoveUpdate?.call(d.offsetFromOrigin) : null,
        onLongPressEnd: movable ? (_) => onMoveEnd?.call() : null,
        onHorizontalDragEnd: (DragEndDetails d) {
          final double v = d.primaryVelocity ?? 0;
          if (v > 200) {
            _step(-1);
          } else if (v < -200) {
            _step(1);
          }
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
          decoration: BoxDecoration(
            color: ThemeHandler.flowSurface.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: ThemeHandler.flowBorderSoft),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: cover == null
                      ? BooruFavicon(tab.selectedBooru.value, size: 28)
                      : Image(
                          image: CustomNetworkImage(cover, withCache: SettingsHandler.instance.thumbnailCache, cacheFolder: 'thumbnails'),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => BooruFavicon(tab.selectedBooru.value, size: 28),
                        ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${section.indexOf(index) + 1}/${section.length}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface),
              ),
              const SizedBox(width: 4),
              Icon(Symbols.tab_rounded, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
            ],
          ),
        ),
      );
    });
  }
}

/// Where the tab pill sits in the feed (r40): its default corner until it is
/// moved — press and hold it, then drag — and where it was left after that,
/// kept as fractions of the feed's size (so it survives a rotation) in its
/// own small file. Covers the feed but takes no touches outside the pill.
class TabPillHost extends StatefulWidget {
  const TabPillHost({required this.bottomInset, required this.alignLeft, super.key});

  /// The default place: this far from the bottom, 12 from the left or right.
  final double bottomInset;
  final bool alignLeft;

  static const String fileName = 'tab_pill.json';

  static File get _file => File('${SettingsHandler.instance.path}$fileName');

  static Offset? loadPosition() {
    try {
      final File file = _file;
      if (!file.existsSync()) return null;
      final dynamic json = jsonDecode(file.readAsStringSync());
      if (json is Map && json['x'] is num && json['y'] is num) {
        return Offset((json['x'] as num).toDouble(), (json['y'] as num).toDouble());
      }
    } catch (_) {}
    return null;
  }

  static void savePosition(Offset? fraction) {
    try {
      final File file = _file;
      if (fraction == null) {
        if (file.existsSync()) file.deleteSync();
        return;
      }
      file.writeAsStringSync(jsonEncode({'x': fraction.dx, 'y': fraction.dy}));
    } catch (_) {}
  }

  @override
  State<TabPillHost> createState() => _TabPillHostState();
}

class _TabPillHostState extends State<TabPillHost> {
  final GlobalKey _pillKey = GlobalKey();

  /// The pill's top-left as fractions of the feed; null = the default place.
  Offset? _fraction;

  /// The pill's top-left when the hold began, while it is being moved.
  Offset? _dragStart;
  Offset _dragOffset = Offset.zero;
  Size _area = Size.zero;

  @override
  void initState() {
    super.initState();
    _fraction = TabPillHost.loadPosition();
  }

  Size get _pillSize => (_pillKey.currentContext?.findRenderObject() as RenderBox?)?.size ?? const Size(110, 40);

  Offset _clamp(Offset p) {
    final Size s = _pillSize;
    return Offset(
      p.dx.clamp(0.0, math.max(0.0, _area.width - s.width)),
      p.dy.clamp(0.0, math.max(0.0, _area.height - s.height)),
    );
  }

  void _start() {
    final RenderBox? pill = _pillKey.currentContext?.findRenderObject() as RenderBox?;
    final RenderBox? host = context.findRenderObject() as RenderBox?;
    if (pill == null || host == null) return;
    setState(() {
      _dragStart = pill.localToGlobal(Offset.zero, ancestor: host);
      _dragOffset = Offset.zero;
    });
  }

  void _update(Offset offsetFromOrigin) {
    if (_dragStart == null) return;
    setState(() => _dragOffset = offsetFromOrigin);
  }

  void _end() {
    final Offset? start = _dragStart;
    if (start == null) return;
    if (_dragOffset.distance < TabPill.moveSlop) {
      setState(() => _dragStart = null);
      TabPill.openManager(context);
      return;
    }
    final Offset p = _clamp(start + _dragOffset);
    setState(() {
      _dragStart = null;
      _fraction = _area.width > 0 && _area.height > 0 ? Offset(p.dx / _area.width, p.dy / _area.height) : null;
    });
    TabPillHost.savePosition(_fraction);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _area = constraints.biggest;
        final Widget pill = KeyedSubtree(
          key: _pillKey,
          child: TabPill(onMoveStart: _start, onMoveUpdate: _update, onMoveEnd: _end),
        );
        Offset? at;
        if (_dragStart != null) {
          at = _clamp(_dragStart! + _dragOffset);
        } else if (_fraction != null) {
          at = _clamp(Offset(_fraction!.dx * _area.width, _fraction!.dy * _area.height));
        }
        return Stack(
          children: [
            if (at == null)
              Positioned(
                bottom: widget.bottomInset,
                left: widget.alignLeft ? 12 : null,
                right: widget.alignLeft ? null : 12,
                child: pill,
              )
            else
              Positioned(left: at.dx, top: at.dy, child: pill),
          ],
        );
      },
    );
  }
}
