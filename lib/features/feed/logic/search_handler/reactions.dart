part of '../search_handler.dart';

/// The search easter eggs (limited per app lifetime).
extension SearchReactions on SearchHandler {
  int getSearchReactionCount(SearchReaction r) => _reactionsCount[r] ?? 0;

  void incrementSearchReactionCount(SearchReaction r) => _reactionsCount[r] = (_reactionsCount[r] ?? 0) + 1;

  bool canSendSearchReaction(SearchReaction r) => getSearchReactionCount(r) < r.limit;

  Future<void> searchReactions(String text, Booru booru) async {
    final context = NavigationHandler.instance.navContext;

    // UOOOOOHHHHH
    if (text.toLowerCase().contains('loli') && canSendSearchReaction(.uoh)) {
      incrementSearchReactionCount(.uoh);
      await FlashElements.showSnackbar(
        duration: const Duration(seconds: 2),
        title: Text(
          context.loc.searchHandler.uoh,
          style: const TextStyle(fontSize: 20),
        ),
        // TODO replace with image asset to avoid system-to-system font differences
        overrideLeadingIconWidget: const Text(
          ' 😭 ',
          style: TextStyle(fontSize: 40),
        ),
        sideColor: Colors.pink,
      );
    }

    // Notify about ratings change on gelbooru and danbooru
    if (text.contains('rating:safe')) {
      final bool isOnBooruWhereRatingsChanged =
          (booru.type?.isGelbooru == true && booru.baseURL!.contains('gelbooru.com')) ||
          (booru.type?.isDanbooru == true && booru.baseURL!.contains('danbooru.donmai.us'));
      if (isOnBooruWhereRatingsChanged) {
        await FlashElements.showSnackbar(
          duration: null,
          title: Text(
            context.loc.searchHandler.ratingsChanged,
            style: const TextStyle(fontSize: 20),
          ),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.loc.searchHandler.ratingsChangedMessage(booruType: booru.type?.name ?? ''),
                style: const TextStyle(fontSize: 16),
              ),
              const Text(''),
              Text(
                context.loc.searchHandler.appFixedRatingAutomatically,
                style: const TextStyle(fontSize: 18),
              ),
            ],
          ),
          leadingIcon: Symbols.warning_amber_rounded,
          leadingIconColor: Colors.yellow,
          sideColor: Colors.red,
        );
      }
    }
  }
}
