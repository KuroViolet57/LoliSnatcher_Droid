part of '../search_handler.dart';

/// The search text, the grid scroll stream and the volume-key stream.
extension SearchQuery on SearchHandler {
  Stream<ScrollNotification>? get scrollStream => _scrollStream?.stream;

  void sendToScrollStream(ScrollNotification notification) {
    _scrollStream?.sink.add(notification);

    scrollOffset.value = gridScrollController.offset;
    currentTab.scrollPosition = gridScrollController.offset;
  }

  void addTagToSearch(String tag) {
    if (tag.isNotEmpty) {
      if (currentBooru.type?.isHydrus == true) {
        searchTextController.text += ', $tag';
      } else {
        searchTextController.text += ' $tag';
      }
    }
  }

  List<String> get searchTextControllerTags =>
      searchTextController.text.trim().split(' ').where((t) => t.isNotEmpty).toList();

  void removeTagFromSearch(String tag) {
    if (tag.isNotEmpty) {
      // Whole tags only (`blue` leaves `blue_eyes` and `navy-blue` alone),
      // with their -, ~ and N# forms. A tag ends at a space, or at a comma
      // in Hydrus' comma-separated queries.
      searchTextController.text = searchTextController.text.replaceAll(
        RegExp(r'(?<=^|\s|,)(?:(?:-|~)?\d+#)?(?:-|~)?' + tag.regexpEscape() + r'(?=$|\s|,)'),
        '',
      );
    }
  }

  Stream<String>? get volumeStream => _volumeStreamController?.stream;

  void setRootRestate(VoidCallback? rootSetStateCallback) => rootRestate = rootSetStateCallback;
}
