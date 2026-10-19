part of '../tab_selector.dart';

enum TabSortingMode {
  none,
  alphabet,
  alphabetReverse,
  booru,
  booruReverse,
  booruOpenOrder,
  booruOpenOrderReverse,
  ;

  bool get isNone => this == TabSortingMode.none;
  bool get isAlphabet => this == TabSortingMode.alphabet;
  bool get isAlphabetReverse => this == TabSortingMode.alphabetReverse;
  bool get isBooru => this == TabSortingMode.booru;
  bool get isBooruReverse => this == TabSortingMode.booruReverse;
  bool get isBooruOpenOrder => this == TabSortingMode.booruOpenOrder;
  bool get isBooruOpenOrderReverse => this == TabSortingMode.booruOpenOrderReverse;

  bool get isAnyBooru => isBooru || isBooruReverse || isBooruOpenOrder || isBooruOpenOrderReverse;
  // True for modes that keep original (open-order) tab order within each booru group.
  bool get isAnyBooruOpenOrder => isBooruOpenOrder || isBooruOpenOrderReverse;
  bool get isAnyReverse => isAlphabetReverse || isBooruReverse || isBooruOpenOrderReverse;

  bool get isAnyAlphabet => isAlphabet || isAlphabetReverse;
}

class TabSortingIcon extends StatelessWidget {
  const TabSortingIcon(
    this.sortingMode, {
    this.withBorder = false,
    super.key,
  });

  final TabSortingMode sortingMode;
  final bool withBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: withBorder ? const EdgeInsets.all(3) : null,
      decoration: BoxDecoration(
        borderRadius: withBorder ? BorderRadius.circular(10) : null,
        border: withBorder ? Border.all(color: Theme.of(context).colorScheme.secondary, width: 2) : null,
      ),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationX((sortingMode.isAnyReverse || sortingMode.isNone) ? 0 : pi),
            child: Icon(
              sortingMode.isNone
                  ? Symbols.sort_by_alpha_rounded
                  : sortingMode.isAnyBooruOpenOrder
                  ? Symbols.schedule_rounded
                  : Symbols.sort_rounded,
            ),
          ),
          if (sortingMode.isAnyBooru)
            Positioned(
              bottom: -10,
              child: Text(context.loc.tabs.byBooru, style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
