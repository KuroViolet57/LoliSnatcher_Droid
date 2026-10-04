part of '../search_handler.dart';

/// The visited-tabs history (TabVisitHistory).
extension SearchTabVisits on SearchHandler {
  void recordTabVisit(SearchTab tab) {
    final visit = TabVisit(
      tabId: tab.id,
      tags: tab.tags,
      booruName: tab.selectedBooru.value.name ?? '',
      booruType: tab.selectedBooru.value.type,
      visitedAt: DateTime.now(),
    );
    // One entry per tab: drop any existing entry for this tab (same id) so the
    // tab moves to most-recent and reflects its current tags, instead of
    // adding a duplicate when its search changes or it's re-visited.
    visitedTabsHistory.removeWhere((v) => v.tabId == tab.id);
    visitedTabsHistory.add(visit);
    if (visitedTabsHistory.length > SearchHandler._maxVisitHistory) {
      visitedTabsHistory.removeRange(0, visitedTabsHistory.length - SearchHandler._maxVisitHistory);
    }
    // Persist so the history survives app restarts. Fire-and-forget.
    unawaited(_persistTabVisit(visit));
  }

  Future<void> _persistTabVisit(TabVisit visit) async {
    try {
      // Replace any prior persisted rows for this tab so the DB mirrors the
      // one-entry-per-tab, most-recent semantics of the in-memory list.
      await SettingsHandler.instance.dbHandler.deleteTabVisit(visit.tabId);
      await SettingsHandler.instance.dbHandler.addTabVisit(
        tabId: visit.tabId,
        tags: visit.tags,
        booruName: visit.booruName,
        booruType: visit.booruType?.name,
        visitedAt: visit.visitedAt.millisecondsSinceEpoch,
      );
      await SettingsHandler.instance.dbHandler.trimTabVisits(SearchHandler._maxVisitHistory);
    } catch (e, s) {
      Logger.Inst().log(
        'failed to persist tab visit: $e',
        'SearchHandler',
        '_persistTabVisit',
        LogTypes.exception,
        s: s,
      );
    }
  }

  Future<void> loadVisitedTabsHistory() async {
    try {
      final rows = await SettingsHandler.instance.dbHandler.getTabVisits();
      visitedTabsHistory.assignAll(rows.map(TabVisit.fromRow));
    } catch (e, s) {
      Logger.Inst().log(
        'failed to load tab visit history: $e',
        'SearchHandler',
        'loadVisitedTabsHistory',
        LogTypes.exception,
        s: s,
      );
    }
  }

  Future<void> clearVisitedTabsHistory() async {
    visitedTabsHistory.clear();
    try {
      await SettingsHandler.instance.dbHandler.clearTabVisits();
    } catch (_) {}
  }
}
