part of '../loli_controls.dart';

class _PlaybackSpeedDialog extends StatefulWidget {
  const _PlaybackSpeedDialog({
    required this.speeds,
    required this.selected,
  });

  final List<double> speeds;
  final double selected;

  @override
  State<_PlaybackSpeedDialog> createState() => _PlaybackSpeedDialogState();
}

class _PlaybackSpeedDialogState extends State<_PlaybackSpeedDialog> {
  final ValueNotifier<int> selectedIndex = ValueNotifier(0);
  late final PageAutoScrollController controller;

  @override
  void initState() {
    super.initState();

    int initialIndex = widget.speeds.indexOf(widget.selected);
    if (initialIndex == -1) {
      initialIndex = widget.speeds.indexOf(1);
    }
    selectedIndex.value = initialIndex;
    controller = PageAutoScrollController(
      initialPage: initialIndex,
      viewportFraction: 0.33,
    );
  }

  void changeValue(int change) {
    int newIndex = selectedIndex.value + change;
    if (newIndex < 0) {
      newIndex = widget.speeds.length - 1;
    } else if (newIndex >= widget.speeds.length) {
      newIndex = 0;
    }

    selectedIndex.value = newIndex;
    controller.animateToPage(
      newIndex,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );
  }

  Future<void> resetValue() async {
    selectedIndex.value = widget.speeds.indexOf(1);
    controller.jumpToPage(
      selectedIndex.value,
    );
    confirmValue();
  }

  void confirmValue() {
    Navigator.of(context).pop(widget.speeds[selectedIndex.value]);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }

        confirmValue();
      },
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 58,
              child: Row(
                children: [
                  const SizedBox(width: 32),
                  Expanded(
                    child: Text(
                      'Video speed',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    onPressed: confirmValue,
                    icon: const Icon(Symbols.close_rounded),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 6,
              children: [
                IconButton(
                  onPressed: () => changeValue(-1),
                  icon: const Icon(
                    Symbols.keyboard_double_arrow_left_rounded,
                    size: 30,
                  ),
                ),
                IconButton(
                  onPressed: resetValue,
                  icon: const Icon(
                    Symbols.refresh_rounded,
                    size: 30,
                  ),
                ),
                IconButton(
                  onPressed: confirmValue,
                  icon: const Icon(
                    Symbols.check_rounded,
                    size: 30,
                  ),
                ),
                IconButton(
                  onPressed: () => changeValue(1),
                  icon: const Icon(
                    Symbols.keyboard_double_arrow_right_rounded,
                    size: 30,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder(
              valueListenable: selectedIndex,
              builder: (context, _, _) {
                return SizedBox(
                  height: 50,
                  child: Listener(
                    onPointerSignal: (event) {
                      if (event is PointerScrollEvent) {
                        changeValue(event.scrollDelta.dy > 0 ? 1 : -1);
                      }
                    },
                    child: PageView.builder(
                      itemCount: widget.speeds.length,
                      scrollDirection: Axis.horizontal,
                      controller: controller,
                      onPageChanged: (value) {
                        selectedIndex.value = value;
                      },
                      itemBuilder: (context, i) {
                        return GestureDetector(
                          onTap: () {
                            if (i != selectedIndex.value) {
                              changeValue(i - selectedIndex.value);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                '${widget.speeds[i].truncateTrailingZeroes(2)}x',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: i == selectedIndex.value ? Theme.of(context).colorScheme.secondary : null,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            SizedBox(height: MediaQuery.paddingOf(context).bottom),
          ],
        ),
      ),
    );
  }
}
