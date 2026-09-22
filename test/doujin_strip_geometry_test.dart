import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/widgets/gallery/tag_view.dart';

/// Round 4, item 2: the Related / Recommended strips. Moving the strip's
/// open-in-new-tab action into the section header freed a row of vertical
/// space, but the cards kept their old fixed height and the strip kept its
/// own separately-written one, so the reclaimed room just became a gap.
void main() {
  test('the strip height is DERIVED from the card, not written separately', () {
    for (final hasHeaderRow in [true, false]) {
      expect(
        TagContentPreview.stripHeight(hasHeaderRow: hasHeaderRow),
        TagContentPreview.stripCardHeight(hasHeaderRow: hasHeaderRow) +
            TagContentPreview.stripListPadding,
        reason: 'strip and card heights must not be able to drift apart',
      );
    }
  });

  test('a strip with no header row gives that height to the cards', () {
    final double withRow = TagContentPreview.stripCardHeight(hasHeaderRow: true);
    final double withoutRow = TagContentPreview.stripCardHeight(hasHeaderRow: false);

    expect(withoutRow, greaterThan(withRow));
    expect(withoutRow - withRow, TagContentPreview.stripReclaimedHeight);
    // The reclaimed row was a compact icon button plus its spacing — the
    // cards should take back something of that order, not a token amount.
    expect(TagContentPreview.stripReclaimedHeight, greaterThanOrEqualTo(32));
  });

  test('the taller card grows the COVER, since the title is a fixed footer', () {
    // The cell is a Column of [Expanded(cover), title]; the title is capped at
    // two lines, so every reclaimed pixel lands on the thumbnail.
    final double extra = TagContentPreview.stripCardHeight(hasHeaderRow: false) -
        TagContentPreview.stripCardHeight(hasHeaderRow: true);
    expect(extra, TagContentPreview.stripReclaimedHeight);
  });

  test('cards stay portrait — width is unchanged, height only grows', () {
    expect(TagContentPreview.stripCardWidth, 148);
    expect(
      TagContentPreview.stripCardHeight(hasHeaderRow: false),
      greaterThan(TagContentPreview.stripCardWidth),
    );
  });

  test('a strip that still has its header row is left alone', () {
    // Booru strips still carry the source chip, so they reclaimed nothing and
    // must not change size.
    expect(TagContentPreview.stripCardHeight(hasHeaderRow: true), 220);
    expect(TagContentPreview.stripHeight(hasHeaderRow: true), 220 + 26);
  });
}
