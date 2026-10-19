part of '../settings_handler.dart';

/// The configured sources (boorus/*.json) and the app's own virtual sources.
extension SettingsBoorus on SettingsHandler {
  Future<bool> loadBoorus() async {
    final List<Booru> tempList = [];
    try {
      if (path == '') {
        await setConfigDir();
      }

      final Directory directory = Directory(boorusPath);
      List<FileSystemEntity> files = [];
      if (await directory.exists()) {
        files = await directory.list().toList();
      }

      if (files.isNotEmpty) {
        for (int i = 0; i < files.length; i++) {
          if (files[i].path.contains('.json')) {
            // && files[i].path != 'settings.json'
            // print(files[i].toString());
            final File booruFile = files[i] as File;
            final Booru booruFromFile = Booru.fromJSON(await booruFile.readAsString());
            final bool isAllowed = BooruType.saveable.contains(booruFromFile.type);
            if (isAllowed) {
              tempList.add(booruFromFile);
            } else {
              await booruFile.delete();
            }

            if (booruFromFile.type?.isHydrus == true) {
              hasHydrus = true;
            }
          }
        }
      }

      if (dbEnabled && tempList.isNotEmpty) {
        // Virtual, DB-backed boorus. Added unconditionally (like Favourites /
        // Downloads) so a restored Collections / For You tab always finds its
        // booru after a restart, and so no per-launch DB round-trip is needed.
        tempList.add(Booru(loc.favourites, BooruType.Favourites, '', '', ''));
        tempList.add(Booru(loc.downloads, BooruType.Downloads, '', '', ''));
        tempList.add(Booru('For You', BooruType.ForYou, '', '', ''));
        tempList.add(Booru('For You (doujin)', BooruType.ForYouDoujin, '', '', ''));
        tempList.add(Booru('Boards', BooruType.Board, '', '', ''));
        tempList.add(Booru('Collections', BooruType.Collections, '', '', ''));
        tempList.add(Booru('History', BooruType.History, '', '', ''));
      }
    } catch (e, s) {
      Logger.Inst().log(
        'Failed to load boorus $e',
        'SettingsHandler',
        'loadBoorus',
        LogTypes.exception,
        s: s,
      );
    }

    booruList.value = tempList
        .where((element) => !booruList.contains(element))
        .toList(); // filter due to possibility of duplicates

    if (tempList.isNotEmpty) {
      unawaited(sortBooruList());
    }
    return true;
  }

  /// Returns the virtual Collections booru, adding it to the list on first use
  /// (it's created lazily so it only appears once the user has a collection).
  Booru ensureCollectionsBooru() {
    for (final b in booruList) {
      if (b.type?.isCollections == true) return b;
    }
    final Booru b = Booru('Collections', BooruType.Collections, '', '', '');
    booruList.add(b);
    return b;
  }

  /// Returns the virtual "For You" recommender booru, adding it to the list on
  /// first use.
  Booru ensureForYouBooru() {
    for (final b in booruList) {
      if (b.type?.isForYou == true) return b;
    }
    final Booru b = Booru('For You', BooruType.ForYou, '', '', '');
    booruList.add(b);
    return b;
  }

  /// Returns the virtual doujin For You booru (r33), adding it to the list
  /// on first use.
  Booru ensureForYouDoujinBooru() {
    for (final b in booruList) {
      if (b.type?.isForYouDoujin == true) return b;
    }
    final Booru b = Booru('For You (doujin)', BooruType.ForYouDoujin, '', '', '');
    booruList.add(b);
    return b;
  }

  /// The virtual source behind board tabs (r73).
  Booru ensureBoardsBooru() {
    for (final b in booruList) {
      if (b.type?.isBoard == true) return b;
    }
    final Booru b = Booru('Boards', BooruType.Board, '', '', '');
    booruList.add(b);
    return b;
  }

  /// Returns the virtual viewing-history booru, adding it to the list on
  /// first use.
  Booru ensureHistoryBooru() {
    for (final b in booruList) {
      if (b.type?.isHistory == true) return b;
    }
    final Booru b = Booru('History', BooruType.History, '', '', '');
    booruList.add(b);
    return b;
  }

  Future<void> sortBooruList() async {
    final List<Booru> sorted = [
      ...booruList,
    ]; // spread the array just in case, to guarantee that we don't affect the original value
    sorted.sort((a, b) {
      // sort alphabetically
      return a.name!.toLowerCase().compareTo(b.name!.toLowerCase());
    });

    int prefIndex = 0;
    for (int i = 0; i < sorted.length; i++) {
      if (sorted[i].name == prefBooru && prefBooru.isNotEmpty) {
        prefIndex = i;
        // print("prefIndex is" + prefIndex.toString());
      }
    }
    if (prefIndex != 0) {
      // move default booru to top
      // print("Booru pref found in booruList");
      final Booru tmp = sorted.elementAt(prefIndex);
      sorted.remove(tmp);
      sorted.insert(0, tmp);
      // print("booruList is");
      // print(sorted);
    }

    final int favsIndex = sorted.indexWhere((el) => el.type?.isFavourites == true);
    if (favsIndex != -1) {
      // move favourites to the end
      final Booru tmp = sorted.elementAt(favsIndex);
      sorted.remove(tmp);
      sorted.add(tmp);
    }

    final int dlsIndex = sorted.indexWhere((el) => el.type?.isDownloads == true);
    if (dlsIndex != -1) {
      // move downloads to the end
      final Booru tmp = sorted.elementAt(dlsIndex);
      sorted.remove(tmp);
      sorted.add(tmp);
    }

    // Keep the other virtual boorus grouped after Favourites / Downloads.
    for (final isType in [
      (Booru b) => b.type?.isForYou == true,
      (Booru b) => b.type?.isForYouDoujin == true,
      (Booru b) => b.type?.isBoard == true,
      (Booru b) => b.type?.isCollections == true,
      (Booru b) => b.type?.isHistory == true,
    ]) {
      final int idx = sorted.indexWhere(isType);
      if (idx != -1) {
        final Booru tmp = sorted.elementAt(idx);
        sorted.remove(tmp);
        sorted.add(tmp);
      }
    }

    booruList.value = sorted;
  }

  Future saveBooru(Booru booru, {bool onlySave = false}) async {
    if (path == '') {
      await setConfigDir();
    }

    await Directory(boorusPath).create(recursive: true);
    final File booruFile = File('$boorusPath${booru.name}.json');
    final writer = booruFile.openWrite();
    writer.write(jsonEncode(booru.toJson()));
    await writer.close();

    if (!onlySave) {
      // used only to avoid duplication after migration to json format
      // TODO remove condition when migration logic is removed
      booruList.add(booru);
      unawaited(sortBooruList());
    }
    return true;
  }

  Future<bool> deleteBooru(Booru booru) async {
    final File booruFile = File('$boorusPath${booru.name}.json');
    if (await booruFile.exists()) {
      await booruFile.delete();
    }
    if (prefBooru == booru.name) {
      prefBooru = '';
      await saveSettings(restate: true);
    }
    booruList.remove(booru);
    unawaited(sortBooruList());
    return true;
  }
}
