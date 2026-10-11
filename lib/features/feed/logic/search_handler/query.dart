part of '../search_handler.dart';

/// The search text, the grid scroll position and the volume-key stream.
extension SearchQuery on SearchHandler {
  void sendToScrollStream(ScrollNotification notification) {
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
