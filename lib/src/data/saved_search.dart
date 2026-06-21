import 'dart:convert';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';

/// A bookmarked search query the user can re-open with a tap.
/// Stores everything needed to faithfully restore a merge-aware search:
/// the tag string, primary booru name, secondary booru names, and the
/// per-booru tag overrides / inherit flags introduced for the merge feature.
class SavedSearch {
  SavedSearch({
    required this.id,
    required this.name,
    required this.tags,
    required this.booru,
    required this.createdAt,
    this.secondaryBoorus = const [],
    this.tagOverrides = const {},
    this.inheritMainTags = const {},
  });

  final int? id;
  // User-facing label. Falls back to the tag string in displayLabel.
  final String name;
  final String tags;
  final String booru;
  final List<String> secondaryBoorus;
  final Map<String, String> tagOverrides;
  final Map<String, bool> inheritMainTags;
  final DateTime createdAt;

  String get displayLabel {
    if (name.trim().isNotEmpty) return name;
    if (tags.trim().isNotEmpty) return tags;
    return '(no tags)';
  }

  // Serialize the merge-shaped payload (everything except id/name/createdAt
  // which are stored as separate columns). Reuses TabBackup's compact JSON
  // schema so older / newer code paths can interop.
  String payloadJson() {
    final backup = TabBackup(
      tags: tags,
      booru: booru,
      secondaryBoorus: secondaryBoorus,
      tagOverrides: Map<String, String>.from(tagOverrides)..removeWhere((_, v) => v.trim().isEmpty),
      inheritMainTags: Map<String, bool>.from(inheritMainTags)..removeWhere((_, v) => v),
    );
    return jsonEncode(backup.toJson());
  }

  static SavedSearch? fromRow(Map<String, Object?> row) {
    final int? id = row['id'] as int?;
    final String name = (row['name'] as String?) ?? '';
    final String payload = (row['payload'] as String?) ?? '';
    final int? ts = row['createdAt'] as int?;
    if (payload.isEmpty) return null;
    try {
      final decoded = jsonDecode(payload) as Map<String, dynamic>;
      final backup = TabBackup.fromJson(decoded);
      if (backup == null) return null;
      return SavedSearch(
        id: id,
        name: name,
        tags: backup.tags,
        booru: backup.booru,
        secondaryBoorus: backup.secondaryBoorus,
        tagOverrides: Map<String, String>.from(backup.tagOverrides),
        inheritMainTags: Map<String, bool>.from(backup.inheritMainTags),
        createdAt: ts != null
            ? DateTime.fromMillisecondsSinceEpoch(ts)
            : DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  // Convenience for callers that want to spawn a SearchHandler tab from
  // this saved search. Resolves `secondaryBoorus` names through the settings
  // handler so deleted boorus are gracefully dropped.
  List<Booru>? resolveSecondaryBoorus(List<Booru> allBoorus) {
    if (secondaryBoorus.isEmpty) return null;
    final list = secondaryBoorus
        .map(
          (name) => allBoorus.firstWhere(
            (b) => b.name == name,
            orElse: Booru.unknown,
          ),
        )
        .where((b) => b.name != null)
        .toList();
    return list.isEmpty ? null : list;
  }
}
