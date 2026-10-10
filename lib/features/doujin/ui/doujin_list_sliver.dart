import 'package:flutter/material.dart';

import 'package:get/get.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import 'package:lolisnatcher/core/logging/perf_trace.dart';
import 'package:lolisnatcher/core/settings/source_settings_handler.dart';
import 'package:lolisnatcher/features/doujin/logic/doujin_data_handler.dart';
import 'package:lolisnatcher/features/doujin/ui/doujin_list_card.dart';
import 'package:lolisnatcher/features/viewer/logic/viewer_handler.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/sources/framework/booru_handler.dart';

/// The doujin feed in List view (r63): one [DoujinListCard] per gallery, all
/// at the same fixed extent.
///
/// 2026-10-10: a trace on the Thor showed every slow List-view frame
/// rebuilding every row the list had built (26 rows in one 22-37 ms frame).
/// Anything that rebuilt the list - a page appended, a loading flag, the
/// fling cache window opening or closing - rebuilt all its rows, about once
/// a second while flinging. Each row's widget is now kept while its gallery,
/// its place and its look are unchanged, so Flutter skips it; new rows, a
/// different gallery at a place, or a changed row height, cover width, cover
/// display or set of starred tags still build. Selection and the viewer
/// highlight update a row through its own listener, as before.
class DoujinListSliver extends StatefulWidget {
  const DoujinListSliver({
    required this.handler,
    required this.selected,
    required this.scrollController,
    required this.height,
    required this.coverWidth,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.onSelected,
    super.key,
  });

  final BooruHandler handler;
  final RxList<BooruItem> selected;
  final AutoScrollController scrollController;
  final double height;
  final double coverWidth;
  final void Function(int)? onTap;
  final void Function(int)? onDoubleTap;
  final void Function(int)? onLongPress;
  final void Function(int)? onSecondaryTap;
  final void Function(int)? onSelected;

  @override
  State<DoujinListSliver> createState() => _DoujinListSliverState();
}

class _DoujinListSliverState extends State<DoujinListSliver> {
  /// The row widget built for each place, with the gallery and look it shows.
  final Map<int, ({BooruItem item, Object look, Widget row})> _rows = {};

  @override
  void didUpdateWidget(DoujinListSliver oldWidget) {
    super.didUpdateWidget(oldWidget);
    // identical, not ==: GetX's RxList == compares its value to the other
    // list, and a plain list never equals an RxList, so == said "changed"
    // on every rebuild and dropped every kept row.
    if (!identical(oldWidget.handler, widget.handler) ||
        !identical(oldWidget.selected, widget.selected) ||
        !identical(oldWidget.scrollController, widget.scrollController)) {
      _rows.clear();
    }
  }

  /// Everything a row reads that has no listener of its own.
  Object _look() => (
    widget.height,
    widget.coverWidth,
    SourceSettingsHandler.instance.coverDisplay(widget.handler.booru),
    Object.hashAllUnordered(DoujinDataHandler.instance.starredTags),
  );

  Widget _rowAt(int index, BooruItem item, Object look) {
    final cached = _rows[index];
    if (cached != null && identical(cached.item, item) && cached.look == look) return cached.row;

    // The callbacks are read from the current widget when the row builds, so
    // a kept row never holds on to stale ones.
    final Widget row = Obx(() {
      final bool hasSelected = widget.selected.isNotEmpty;
      final int selectedIndex = widget.selected.indexOf(item);
      final bool isSelected = selectedIndex != -1;

      return DoujinListCard(
        index: index,
        item: item,
        handler: widget.handler,
        scrollController: widget.scrollController,
        height: widget.height,
        coverWidth: widget.coverWidth,
        isHighlighted: ViewerHandler.instance.current.value?.key == item.key,
        selectedIndex: isSelected ? selectedIndex : null,
        onSelected: hasSelected ? widget.onSelected : null,
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        onLongPress: widget.onLongPress,
        onSecondaryTap: widget.onSecondaryTap,
      );
    });
    _rows[index] = (item: item, look: look, row: row);
    return row;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<BooruItem>>(
      valueListenable: widget.handler.filteredFetched,
      builder: (context, items, _) {
        // On the trace's timeline: each of these used to rebuild every row.
        PerfTrace.instance.event('feed.list', '${items.length} items');
        final Object look = _look();
        _rows.removeWhere((index, _) => index >= items.length);
        // Every row is the same height, so the list is laid out at that fixed
        // extent instead of measuring each row as it scrolls in (2026-10-09).
        return SliverFixedExtentList.builder(
          itemExtent: DoujinListCard.rowExtent(widget.height),
          addAutomaticKeepAlives: false,
          itemCount: items.length,
          itemBuilder: (BuildContext context, int index) => _rowAt(index, items[index], look),
        );
      },
    );
  }
}
