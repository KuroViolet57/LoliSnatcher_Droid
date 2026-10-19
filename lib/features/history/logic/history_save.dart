import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/core/logging/logger.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/storage/database_handler.dart';
import 'package:lolisnatcher/core/ui/flash_elements.dart';
import 'package:lolisnatcher/features/doujin/logic/doujin_data_handler.dart';
import 'package:lolisnatcher/features/feed/logic/search_handler.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/saved_search.dart';

/// Why a history row was not turned into a saved search.
enum HistorySaveBlock { unknownBooru, databaseOff }

/// The saved-search write a history row maps onto.
///
/// A history row has no merge secondaries, so the saved search does not
/// invent any. An empty label shows the tags, the same as a blank label
/// from the search bar.
class HistorySaveRequest {
  const HistorySaveRequest({
    required this.doujin,
    required this.tags,
    required this.booruName,
  });

  final bool doujin;
  final String tags;
  final String booruName;
}

class HistorySaveDecision {
  const HistorySaveDecision._({this.request, this.block});

  const HistorySaveDecision.request(HistorySaveRequest value) : this._(request: value);

  const HistorySaveDecision.blocked(HistorySaveBlock reason) : this._(block: reason);

  final HistorySaveRequest? request;
  final HistorySaveBlock? block;
}

/// A known booru row uses the booru saved-search table. A doujin row uses
/// the doujin store even when the database is off. An unknown booru, or a
/// booru row while the database is off, writes nothing.
HistorySaveDecision decideHistorySave({
  required bool booruKnown,
  required bool doujin,
  required bool dbEnabled,
  required String searchText,
  required String booruName,
}) {
  if (!booruKnown || booruName.trim().isEmpty) {
    return const HistorySaveDecision.blocked(HistorySaveBlock.unknownBooru);
  }
  if (!doujin && !dbEnabled) {
    return const HistorySaveDecision.blocked(HistorySaveBlock.databaseOff);
  }
  return HistorySaveDecision.request(
    HistorySaveRequest(
      doujin: doujin,
      tags: searchText,
      booruName: booruName.trim(),
    ),
  );
}

Future<bool> persistHistorySave(HistorySaveRequest request, {required Booru booru}) async {
  if (request.doujin) {
    DoujinDataHandler.instance.addSavedSearch(
      name: '',
      query: request.tags,
      booru: booru,
    );
  } else {
    final int? id = await SettingsHandler.instance.dbHandler.addSavedSearch(
      SavedSearch(
        id: null,
        name: '',
        tags: request.tags,
        booru: request.booruName,
        createdAt: DateTime.now(),
      ),
    );
    if (id == null) return false;
    await SearchHandler.instance.reloadSavedSearches();
  }
  Logger.Inst().log(
    'Saved a history search for ${request.booruName}',
    'HistorySave',
    'persistHistorySave',
    LogTypes.settingsLoad,
  );
  return true;
}

/// Shared by the history page and the search-window history sheet.
Future<void> runHistorySave({
  required BuildContext context,
  required String searchText,
  required Booru? booru,
  required bool dbEnabled,
}) async {
  final String named = booru?.name?.trim() ?? '';
  final HistorySaveDecision decision = decideHistorySave(
    booruKnown: named.isNotEmpty,
    doujin: booru != null && DoujinDataHandler.isDoujinBooru(booru),
    dbEnabled: dbEnabled,
    searchText: searchText,
    booruName: named,
  );
  final HistorySaveRequest? request = decision.request;
  if (request == null || booru == null) {
    final bool database = decision.block == HistorySaveBlock.databaseOff;
    FlashElements.showSnackbar(
      context: context,
      title: Text(
        database ? 'The database is off, so this search was not saved' : context.loc.history.unknownBooruType,
        style: const TextStyle(fontSize: 20),
      ),
      leadingIcon: Symbols.warning_amber_rounded,
      leadingIconColor: Colors.red,
      sideColor: Colors.red,
    );
    return;
  }
  final bool saved = await persistHistorySave(request, booru: booru);
  if (!context.mounted) return;
  FlashElements.showSnackbar(
    context: context,
    duration: const Duration(seconds: 2),
    title: Text(
      saved ? 'Search saved' : 'Failed to save search',
      style: const TextStyle(fontSize: 20),
    ),
    leadingIcon: Symbols.bookmark_rounded,
    sideColor: saved ? Colors.green : Colors.red,
  );
  if (saved) Navigator.of(context).pop();
}
