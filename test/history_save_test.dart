import 'package:flutter_test/flutter_test.dart';
import 'package:lolisnatcher/features/history/logic/history_save.dart';

void main() {
  HistorySaveDecision decide({
    bool booruKnown = true,
    bool doujin = false,
    bool dbEnabled = true,
    String searchText = 'cat girl',
    String booruName = 'Gel',
  }) {
    return decideHistorySave(
      booruKnown: booruKnown,
      doujin: doujin,
      dbEnabled: dbEnabled,
      searchText: searchText,
      booruName: booruName,
    );
  }

  test('a known history row becomes a saved search, and a blocked row does not', () {
    final HistorySaveDecision saved = decide();
    expect(saved.block, isNull);
    expect(saved.request, isNotNull);
    expect(saved.request!.doujin, isFalse);
    expect(saved.request!.tags, 'cat girl');
    expect(saved.request!.booruName, 'Gel');

    expect(decide(searchText: '').request!.tags, '');

    final HistorySaveDecision unknown = decide(booruKnown: false);
    expect(unknown.request, isNull);
    expect(unknown.block, HistorySaveBlock.unknownBooru);

    final HistorySaveDecision noDb = decide(dbEnabled: false);
    expect(noDb.request, isNull);
    expect(noDb.block, HistorySaveBlock.databaseOff);

    final HistorySaveDecision doujin = decide(dbEnabled: false, doujin: true, booruName: 'nHentai');
    expect(doujin.block, isNull);
    expect(doujin.request!.doujin, isTrue);
    expect(doujin.request!.booruName, 'nHentai');
    expect(doujin.request!.tags, 'cat girl');
  });
}
