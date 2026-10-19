part of '../search_handler.dart';

/// A lightweight record of a tab the user personally visited. Keeps a
/// snapshot (tags + booru) so it stays meaningful even after the underlying
/// tab is closed, plus the live tab id so we can jump straight back if it's
/// still open.
class TabVisit {
  TabVisit({
    required this.tabId,
    required this.tags,
    required this.booruName,
    required this.booruType,
    required this.visitedAt,
  });

  factory TabVisit.fromRow(Map<String, Object?> row) {
    final String? typeName = row['booruType'] as String?;
    BooruType? type;
    if (typeName != null) {
      for (final t in BooruType.values) {
        if (t.name == typeName) {
          type = t;
          break;
        }
      }
    }
    return TabVisit(
      tabId: (row['tabId'] as String?) ?? '',
      tags: (row['tags'] as String?) ?? '',
      booruName: (row['booruName'] as String?) ?? '',
      booruType: type,
      visitedAt: DateTime.fromMillisecondsSinceEpoch(
        (row['visitedAt'] as int?) ?? 0,
      ),
    );
  }

  final String tabId;
  final String tags;
  final String booruName;
  final BooruType? booruType;
  final DateTime visitedAt;
}
