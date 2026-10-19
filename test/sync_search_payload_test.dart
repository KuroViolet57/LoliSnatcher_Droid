import 'package:flutter_test/flutter_test.dart';
import 'package:lolisnatcher/features/sync/logic/sync_search_payload.dart';
import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/models/history_item.dart';
import 'package:lolisnatcher/models/saved_search.dart';

void main() {
  test('a search this phone already has is left, and a favourite marks it', () {
    expect(
      decideHistoryMerge(
        booruNamed: true,
        alreadyThere: true,
        alreadyFavourite: false,
        incomingFavourite: false,
      ),
      HistoryMergeAction.skip,
    );
    expect(
      decideHistoryMerge(
        booruNamed: true,
        alreadyThere: true,
        alreadyFavourite: true,
        incomingFavourite: false,
      ),
      HistoryMergeAction.skip,
      reason: 'a plain copy must not clear a favourite',
    );
    expect(
      decideHistoryMerge(
        booruNamed: true,
        alreadyThere: true,
        alreadyFavourite: false,
        incomingFavourite: true,
      ),
      HistoryMergeAction.upgradeFavourite,
    );
    expect(
      decideHistoryMerge(
        booruNamed: true,
        alreadyThere: false,
        alreadyFavourite: false,
        incomingFavourite: true,
      ),
      HistoryMergeAction.insert,
    );
    expect(
      decideHistoryMerge(
        booruNamed: false,
        alreadyThere: false,
        alreadyFavourite: false,
        incomingFavourite: true,
      ),
      HistoryMergeAction.skip,
    );
  });

  test('history on the wire trims the search and drops a row with no booru', () {
    final SyncHistoryRow? kept = SyncHistoryRow.fromHistoryItem(
      HistoryItem(1, '  少女 🌸  ', BooruType.Danbooru, '  Gelbooru  ', true, '2026-10-07 12:00:00'),
    );
    expect(kept?.searchText, '少女 🌸');
    expect(kept?.booruName, 'Gelbooru');
    expect(kept?.booruType, 'Danbooru');
    expect(kept?.favourite, isTrue);
    expect(SyncHistoryRow.fromJson(kept!.toJson())?.searchText, '少女 🌸');
    expect(SyncHistoryRow.fromHistoryItem(HistoryItem(2, '1girl', BooruType.Danbooru, '  ', false, '')), isNull);
    expect(SyncHistoryRow.fromJson({'searchText': '1girl', 'booruName': ''}), isNull);
    expect(historyIdentity('1girl ', 'Danbooru', 'Main'), historyIdentity('1girl', 'Danbooru', 'Main'));
    expect(historyIdentity('1girl', 'Danbooru', 'Main'), isNot(historyIdentity('1girls', 'Danbooru', 'Main')));
  });

  test('the same saved search is one bookmark even when the label differs', () {
    SavedSearch entry({
      String name = '',
      String tags = '1girl',
      List<String> secondaries = const [],
    }) => SavedSearch(
      id: 1,
      name: name,
      tags: tags,
      booru: 'Gelbooru',
      secondaryBoorus: secondaries,
      createdAt: DateTime.utc(2026, 10, 7),
    );

    expect(savedSearchIdentity(entry(name: 'later')), savedSearchIdentity(entry(name: '')));
    expect(savedSearchIdentity(entry(secondaries: ['B', 'A'])), savedSearchIdentity(entry(secondaries: ['A', 'B'])));
    expect(savedSearchIdentity(entry(tags: '1girl')), isNot(savedSearchIdentity(entry(tags: '1girls'))));
    expect(
      decideSavedSearchMerge(payloadOk: true, booruNamed: true, alreadyThere: true),
      SavedSearchMergeAction.skip,
    );
    expect(
      decideSavedSearchMerge(payloadOk: true, booruNamed: true, alreadyThere: false),
      SavedSearchMergeAction.insert,
    );
    expect(
      decideSavedSearchMerge(payloadOk: false, booruNamed: true, alreadyThere: false),
      SavedSearchMergeAction.skip,
    );
    expect(
      decideSavedSearchMerge(payloadOk: true, booruNamed: false, alreadyThere: false),
      SavedSearchMergeAction.skip,
    );

    final SyncSavedSearchRow? wire = SyncSavedSearchRow.fromSavedSearch(entry(name: 'keep me'));
    final SavedSearch? back = wire!.toSavedSearch();
    expect(back?.name, 'keep me');
    expect(back?.tags, '1girl');
    expect(savedSearchIdentity(back!), savedSearchIdentity(entry()));
    expect(SyncSavedSearchRow.fromJson({'name': 'x', 'payload': 'not json'}), isNotNull);
    expect(SyncSavedSearchRow.fromJson({'name': 'x', 'payload': 'not json'})!.toSavedSearch(), isNull);
  });
}
