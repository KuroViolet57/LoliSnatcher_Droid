part of '../search_handler.dart';

enum HasTabWithTagResult {
  onlyTag,
  onlyTagDifferentBooru,
  containsTag,
  noTag,
  ;

  bool get isOnlyTag => this == HasTabWithTagResult.onlyTag;
  bool get isOnlyTagDifferentBooru => this == HasTabWithTagResult.onlyTagDifferentBooru;
  bool get isContainsTag => this == HasTabWithTagResult.containsTag;
  bool get isNoTag => this == HasTabWithTagResult.noTag;
  bool get hasTagInAnyForm =>
      this == HasTabWithTagResult.onlyTag ||
      this == HasTabWithTagResult.onlyTagDifferentBooru ||
      this == HasTabWithTagResult.containsTag;

  String? locName(BuildContext context) => switch (this) {
    .onlyTag => context.loc.tagView.tabsWithOnlyTag,
    .onlyTagDifferentBooru => context.loc.tagView.tabsWithOnlyTagDifferentBooru,
    .containsTag => context.loc.tagView.tabsContainingTag,
    _ => null,
  };

  Color? color(BuildContext context) => switch (this) {
    onlyTag => Theme.of(context).colorScheme.onSurface,
    onlyTagDifferentBooru => Colors.yellow,
    containsTag => Colors.blue,
    _ => null,
  };
}

enum TabAddMode {
  prev,
  next,
  end,
  ;

  String locName(BuildContext context) {
    switch (this) {
      case prev:
        return context.loc.tabs.addModePrevTab;
      case next:
        return context.loc.tabs.addModeNextTab;
      case end:
        return context.loc.tabs.addModeListEnd;
    }
  }
}

enum SearchReaction {
  uoh,
  ;

  int get limit => switch (this) {
    uoh => 5,
  };
}
