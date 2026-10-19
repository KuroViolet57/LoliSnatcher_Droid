part of '../main_search_query_editor_page.dart';

/// The source a query-editor block builds for: the current tab's handler, or
/// a throwaway handler for an explicit booru, cached across rebuilds.
mixin _EditorSourceMixin<T extends StatefulWidget> on State<T> {
  Booru? get ownBooru;

  BooruHandler? _cachedHandler;
  Booru? _cachedFor;

  Booru get sourceBooru => ownBooru ?? SearchHandler.instance.currentBooru;

  BooruHandler get sourceHandler {
    final Booru? own = ownBooru;
    if (own == null) return SearchHandler.instance.currentBooruHandler;
    if (_cachedHandler == null || _cachedFor != own) {
      _cachedHandler = BooruHandlerFactory().getBooruHandler([own], null).booruHandler;
      _cachedFor = own;
    }
    return _cachedHandler!;
  }
}
