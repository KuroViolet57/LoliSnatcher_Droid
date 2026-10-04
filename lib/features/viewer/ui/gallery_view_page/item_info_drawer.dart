part of '../gallery_view_page.dart';

class ItemInfoDrawer extends StatefulWidget {
  const ItemInfoDrawer({
    required this.tab,
    required this.pageController,
    required this.onVisibilityChanged,
    super.key,
  });

  final SearchTab tab;
  final PreloadPageController pageController;
  final ValueChanged<bool> onVisibilityChanged;

  @override
  State<ItemInfoDrawer> createState() => _ItemInfoDrawerState();
}

class _ItemInfoDrawerState extends State<ItemInfoDrawer> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final ViewerHandler viewerHandler = ViewerHandler.instance;

  final ValueNotifier<bool> isVisible = ValueNotifier(true);

  final ValueNotifier<int> page = ValueNotifier(0);

  @override
  void initState() {
    super.initState();

    page.value = widget.pageController.page?.round() ?? 0;
    widget.pageController.addListener(pageListener);
  }

  void pageListener() {
    page.value = widget.pageController.page?.round() ?? 0;
  }

  void toggleVisibility() {
    isVisible.value = !isVisible.value;
    widget.onVisibilityChanged(isVisible.value);
  }

  @override
  void dispose() {
    widget.pageController.removeListener(pageListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double maxDrawerWidth = MediaQuery.sizeOf(context).shortestSide * 0.8;

    final List<Widget> buttons = [
      // TODO fav/dl buttons?
      Expanded(
        child: ValueListenableBuilder(
          valueListenable: viewerHandler.isStopped,
          builder: (context, isStopped, child) {
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: isStopped
                  ? SizedBox.expand(
                      child: OutlinedButton(
                        onPressed: viewerHandler.forceLoadCurrentItem,
                        child: const Icon(Symbols.refresh_rounded),
                      ),
                    )
                  : null,
            );
          },
        ),
      ),
      Expanded(
        child: ValueListenableBuilder(
          valueListenable: isVisible,
          builder: (context, _, _) {
            return GestureDetector(
              onLongPressDown: (_) => toggleVisibility(),
              onLongPressUp: toggleVisibility,
              onLongPressCancel: toggleVisibility,
              child: OutlinedButton(
                onPressed: toggleVisibility,
                child: isVisible.value ? const Icon(Symbols.remove_red_eye_rounded) : const Icon(Symbols.remove_red_eye_rounded),
              ),
            );
          },
        ),
      ),
      Expanded(
        child: LongPressRepeater(
          onStart: () async {
            widget.pageController.jumpToPage(page.value - 1);
            await Future.delayed(const Duration(milliseconds: 100));
          },
          fasterAfter: 20,
          child: OutlinedButton(
            onPressed: () => widget.pageController.jumpToPage(page.value - 1),
            child: settingsHandler.galleryScrollDirection.isVertical
                ? const Icon(Symbols.arrow_upward_rounded)
                : const Icon(Symbols.arrow_back_rounded),
          ),
        ),
      ),
      Expanded(
        child: LongPressRepeater(
          onStart: () async {
            widget.pageController.jumpToPage(page.value + 1);
            await Future.delayed(const Duration(milliseconds: 100));
          },
          fasterAfter: 20,
          child: OutlinedButton(
            onPressed: () => widget.pageController.jumpToPage(page.value + 1),
            child: settingsHandler.galleryScrollDirection.isVertical
                ? const Icon(Symbols.arrow_downward_rounded)
                : const Icon(Symbols.arrow_forward_rounded),
          ),
        ),
      ),
    ];

    return RepaintBoundary(
      child: Theme(
        data: Theme.of(context).copyWith(
          // copy existing main app theme, but make background semitransparent
          drawerTheme: Theme.of(context).drawerTheme.copyWith(
            backgroundColor: Theme.of(context).canvasColor.withValues(alpha: 0.66),
          ),
        ),
        child: SizedBox(
          width: maxDrawerWidth + 66,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SafeArea(
                child: Container(
                  alignment: Alignment.bottomCenter,
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                  height: (50 * buttons.length) + (12 * (buttons.length - 1)),
                  width: 50,
                  child: ValueListenableBuilder(
                    valueListenable: isVisible,
                    builder: (context, isVisible, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          outlinedButtonTheme: OutlinedButtonThemeData(
                            style: OutlinedButtonTheme.of(context).style?.copyWith(
                              backgroundColor: WidgetStatePropertyAll(
                                Theme.of(context).canvasColor.withValues(alpha: isVisible ? 0.66 : 0.1),
                              ),
                              side: WidgetStatePropertyAll(
                                BorderSide(
                                  width: isVisible ? 1.5 : 0.5,
                                  color: Theme.of(context).colorScheme.secondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        child: Opacity(
                          opacity: isVisible ? 0.9 : 0.3,
                          child: child,
                        ),
                      );
                    },
                    child: Column(
                      spacing: 12,
                      children: buttons,
                    ),
                  ),
                ),
              ),

              ValueListenableBuilder(
                valueListenable: isVisible,
                builder: (context, isVisible, child) {
                  return AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: isVisible ? 1 : 0,
                    child: IgnorePointer(
                      ignoring: !isVisible,
                      child: child,
                    ),
                  );
                },
                child: Drawer(
                  width: maxDrawerWidth,
                  child: SafeArea(
                    child: ValueListenableBuilder(
                      valueListenable: page,
                      builder: (context, page, _) {
                        if (widget.tab.booruHandler.filteredFetched.isEmpty ||
                            page >= widget.tab.booruHandler.filteredFetched.length) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              spacing: 16,
                              children: [
                                Text(context.loc.galleryView.noItemSelected),
                                const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: CloseDialogButton(),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return TagView(
                          item: widget.tab.booruHandler.filteredFetched[page],
                          handler: widget.tab.booruHandler,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
