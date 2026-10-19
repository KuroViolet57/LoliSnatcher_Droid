part of '../thumbnail.dart';

/// Returns true if successful, false on error and null on skip
Future<bool?> tryToLoadAndUpdateItem(
  BooruItem item,
  CancelToken? cancelToken,
) async {
  try {
    final itemFileHost = Uri.tryParse(item.fileURL)?.host;
    final itemPostHost = Uri.tryParse(item.postURL)?.host;
    final Booru? possibleBooru = SettingsHandler.instance.booruList.firstWhereOrNull((e) {
      final booruHost = Uri.tryParse(e.baseURL ?? '')?.host;

      return (itemPostHost?.isNotEmpty == true &&
              booruHost?.isNotEmpty == true &&
              (itemPostHost! == booruHost! ||
                  switch (e.type) {
                    BooruType.IdolSankaku => IdolSankakuHandler.knownUrls.contains(itemPostHost),
                    BooruType.Sankaku => SankakuHandler.knownPostUrls.contains(itemPostHost),
                    _ => false,
                  })) ||
          (itemFileHost?.isNotEmpty == true && booruHost?.isNotEmpty == true && itemFileHost! == booruHost!);
    });

    // The request runs with the caller's token, so the caller can cancel it
    // (a thumbnail that went away); without one it gets its own.
    final CancelToken token = cancelToken ?? CancelToken();
    if (possibleBooru != null) {
      final handler = BooruHandlerFactory().getBooruHandler([possibleBooru], null).booruHandler;
      if (handler.hasLoadItemSupport) {
        final result = await handler.loadItem(
          item: item,
          cancelToken: token,
          withCapcthaCheck: true,
        );

        if (!result.failed &&
            result.item != null &&
            (result.item?.isSnatched.value == true || result.item?.isFavourite.value == true)) {
          unawaited(
            SettingsHandler.instance.dbHandler.updateBooruItem(
              result.item!,
              BooruUpdateMode.urlUpdate,
            ),
          );
          return true;
        } else {
          return false;
        }
      }
    }
    return null;
  } catch (_) {}
  return null;
}
