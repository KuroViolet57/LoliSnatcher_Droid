/// The feed's bottom bar as the app shell and the feed drive it (show it on
/// scroll up, hide it on scroll down). WaterfallBottomBarState implements it,
/// so NavigationHandler reaches the bar without importing the feed UI.
abstract interface class BottomBarVisibility {
  void show();

  void hide();
}
