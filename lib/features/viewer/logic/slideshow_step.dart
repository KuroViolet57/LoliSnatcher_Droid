/// What a slideshow does when its timer fires, or when play is pressed.
enum SlideshowStep { advance, loadMore, stop }

/// [index] is the slide on screen. [loaded] is how many posts are already
/// in the viewer. [canLoadMore] is false on the last page, on an error,
/// while a reader is not the search list, or while a load is locked.
SlideshowStep slideshowStep({required int index, required int loaded, required bool canLoadMore}) {
  if (loaded <= 0 || index < 0 || index >= loaded) return SlideshowStep.stop;
  if (index < loaded - 1) return SlideshowStep.advance;
  if (canLoadMore) return SlideshowStep.loadMore;
  return SlideshowStep.stop;
}
