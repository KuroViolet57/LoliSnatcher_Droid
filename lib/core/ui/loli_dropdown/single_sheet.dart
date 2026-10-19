part of '../loli_dropdown.dart';

class LoliDropdownBottomSheet<T> extends StatefulWidget {
  const LoliDropdownBottomSheet({
    required this.value,
    required this.onChanged,
    required this.items,
    required this.itemBuilder,
    required this.labelText,
    this.itemExtent,
    this.clearable = false,
    this.searchable = false,
    this.searchCheck,
    this.controller,
    super.key,
  });

  final T? value;
  final void Function(T?) onChanged;
  final List<T> items;
  final Widget Function(T) itemBuilder;
  final String labelText;
  final double? itemExtent;
  final bool clearable;
  final bool searchable;
  final bool Function(String, T)? searchCheck;
  final ScrollController? controller;

  @override
  State<LoliDropdownBottomSheet<T>> createState() => _LoliDropdownBottomSheet();
}

class _LoliDropdownBottomSheet<T> extends State<LoliDropdownBottomSheet<T>> {
  late final ScrollController scrollController;
  final TextEditingController searchController = TextEditingController();

  final List<T> filteredItems = [];

  final List<GlobalKey> _keys = [];

  @override
  void initState() {
    super.initState();

    scrollController = widget.controller ?? ScrollController();

    filteredItems.addAll(widget.items);
    _keys.addAll(filteredItems.map((_) => GlobalKey()));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.value != null) {
        final index = filteredItems.indexOf(widget.value as T);
        // 1.0: a value that is not in the list (filtered out, a stale
        // instance) has nothing to scroll to.
        if (index == -1) {
          return;
        }
        if (_keys[index].currentContext != null) {
          Scrollable.ensureVisible(
            _keys[index].currentContext!,
            alignment: 0.5,
          );
        } else if (widget.itemExtent != null) {
          scrollController.jumpTo(
            min(
              scrollController.position.maxScrollExtent,
              widget.itemExtent! * index,
            ),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    // A draggable sheet hands in its own controller, which it disposes.
    if (widget.controller == null) {
      scrollController.dispose();
    }
    super.dispose();
  }

  void onItemSelect(T item) {
    if (widget.clearable && item == widget.value) {
      widget.onChanged(null);
    } else {
      widget.onChanged(item);
    }
    Navigator.of(context).pop(true);
  }

  void filterItems() {
    final search = searchController.text.toLowerCase().trim();
    if (search.isEmpty) {
      filteredItems.clear();
      filteredItems.addAll(widget.items);
    } else {
      filteredItems.clear();
      filteredItems.addAll(widget.items.where((item) => widget.searchCheck?.call(search, item) ?? true));
    }
    _keys.clear();
    _keys.addAll(filteredItems.map((_) => GlobalKey()));
    setState(() {});
  }

  Widget itemBuilder(BuildContext context, int index) {
    final item = filteredItems[index];

    return Material(
      key: _keys[index],
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onItemSelect(item),
        child: Row(
          children: [
            Expanded(
              child: widget.itemBuilder(item),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = Scrollbar(
      controller: scrollController,
      thumbVisibility: true,
      // use more performant buidler when there are a lot of items,
      // but we lose ability to scroll to the selected item on first render
      child: filteredItems.length > 500
          ? ListView.builder(
              controller: scrollController,
              shrinkWrap: widget.controller == null,
              itemCount: filteredItems.length,
              itemExtent: widget.itemExtent,
              itemBuilder: itemBuilder,
            )
          : ListView(
              controller: scrollController,
              shrinkWrap: widget.controller == null,
              itemExtent: widget.itemExtent,
              children: List.generate(filteredItems.length, (i) => itemBuilder(context, i)),
            ),
    );

    final bool isLeftHanded = SettingsHandler.instance.handSide.value.isLeft;

    List<Widget> actions = [
      const ReturnButton(
        withIcon: true,
        returnData: false,
      ),
      if (widget.clearable && widget.value != null)
        ClearButton(
          withIcon: true,
          action: () {
            widget.onChanged(null);
            Navigator.of(context).pop(true);
          },
        ),
    ];

    if (isLeftHanded) {
      actions = actions.reversed.toList();
    }

    return GestureDetector(
      // required to ignore taps on empty places inside the sheet while also allowing taps on the barrier
      onTap: () {},
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(width: 16),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      widget.labelText,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
                if (widget.searchable && widget.searchCheck != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: SizedBox(
                      width: 150,
                      height: kMinInteractiveDimension,
                      child: SearchBar(
                        controller: searchController,
                        hintText: context.loc.search,
                        trailing: const [
                          IgnorePointer(
                            child: Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Icon(Symbols.search_rounded),
                            ),
                          ),
                        ],
                        onChanged: (_) => filterItems(),
                      ),
                    ),
                  ),
                const SizedBox(width: 16),
                const CloseButton(),
                const SizedBox(width: 16),
              ],
            ),
            const SizedBox(height: 16),
            if (widget.controller == null) Flexible(child: body) else Expanded(child: body),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      direction: Axis.horizontal,
                      runSpacing: 12,
                      spacing: 12,
                      alignment: isLeftHanded ? WrapAlignment.start : WrapAlignment.end,
                      children: actions,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: MediaQuery.paddingOf(context).bottom + 12),
          ],
        ),
      ),
    );
  }
}
