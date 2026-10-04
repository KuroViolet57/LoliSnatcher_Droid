part of '../tab_selector.dart';

/// The visited tabs inside the history dialog (r61).
///
/// The dialog scrolls its own content, so this list must not: a scrollable
/// inside a scrollable eats the drag - the inner list is built at full height
/// and has nothing to scroll, and the dialog never moves. That is why the
/// history would not scroll at all.
class VisitedTabsHistoryList extends StatelessWidget {
  const VisitedTabsHistoryList({
    required this.entries,
    required this.isStillOpen,
    required this.booruFor,
    required this.timeLabel,
    required this.onOpen,
    super.key,
  });

  final List<TabVisit> entries;
  final bool Function(TabVisit visit) isStillOpen;
  final Booru? Function(String booruName) booruFor;
  final String Function(DateTime visitedAt) timeLabel;
  final void Function(TabVisit visit) onOpen;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('No visited tabs yet.\nTabs you open by tapping them will show up here.'),
        ),
      );
    }
    return SizedBox(
      width: double.maxFinite,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final TabVisit visit = entries[i];
          final bool stillOpen = isStillOpen(visit);
          final Booru? booru = booruFor(visit.booruName);
          final String tagsLabel = visit.tags.trim().isEmpty ? '(empty search)' : visit.tags.trim();
          return ListTile(
            dense: true,
            leading: booru != null ? BooruFavicon(booru) : const Icon(Symbols.public_rounded, size: 20),
            title: Text(
              tagsLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${visit.booruName.isEmpty ? 'Unknown booru' : visit.booruName} · ${timeLabel(visit.visitedAt)}${stillOpen ? '' : ' · closed'}',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: Icon(
              stillOpen ? Symbols.open_in_new_rounded : Symbols.restart_alt_rounded,
              size: 18,
            ),
            onTap: () => onOpen(visit),
          );
        },
      ),
    );
  }
}
