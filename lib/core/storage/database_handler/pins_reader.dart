part of '../database_handler.dart';

/// Pinned tags (follows are pins with a label) and doujin reading progress.
extension DBPinsAndReader on DBHandler {
  Future<void> updateReaderProgress(String galleryKey, int page, int totalPages, int updatedAt) async {
    await db?.rawInsert(
      'INSERT OR REPLACE INTO ReaderProgress (galleryKey, page, totalPages, updatedAt) VALUES (?, ?, ?, ?)',
      [galleryKey, page, totalPages, updatedAt],
    );
  }

  ///////
  /// Pinned Tags methods

  /// Add a pinned tag (global or booru-specific)
  Future<int?> addPinnedTag(
    String tagName, {
    String? booruType,
    String? booruName,
    List<String> labels = const [],
    String? title,
  }) async {
    // Check if already pinned with same scope
    final existing = await db?.rawQuery(
      'SELECT id FROM PinnedTag WHERE tagName = ? AND (booruName IS ? OR (booruName = ? AND booruType = ?))',
      [tagName, booruName, booruName, booruType],
    );
    if (existing != null && existing.isNotEmpty) {
      return null; // Already pinned
    }

    final pinnedAt = DateTime.now().millisecondsSinceEpoch;
    final labelsString = labels.isNotEmpty ? labels.join(',') : null;
    final result = await db?.rawInsert(
      'INSERT INTO PinnedTag(tagName, booruType, booruName, pinnedAt, sortOrder, label, title) VALUES(?, ?, ?, ?, ?, ?, ?)',
      [tagName, booruType, booruName, pinnedAt, 0, labelsString, title],
    );
    return result;
  }

  /// Remove a pinned tag by id
  Future<void> removePinnedTag(int id) async {
    await db?.rawDelete('DELETE FROM PinnedTag WHERE id = ?', [id]);
    // r79: its hides go with it, or a new pin reusing the id is born hidden.
    try {
      PinnedTagVisibility.forgetId(id);
    } catch (_) {}
  }

  /// Remove a pinned tag by tagName and scope
  Future<void> removePinnedTagByName(String tagName, {String? booruType, String? booruName}) async {
    if (booruName == null) {
      await db?.rawDelete('DELETE FROM PinnedTag WHERE tagName = ? AND booruName IS NULL', [tagName]);
    } else {
      await db?.rawDelete(
        'DELETE FROM PinnedTag WHERE tagName = ? AND booruName = ? AND booruType = ?',
        [tagName, booruName, booruType],
      );
    }
  }

  /// Get all pinned tags (both global and booru-specific for the given booru)
  Future<List<PinnedTag>> getPinnedTags({String? booruType, String? booruName}) async {
    final List<Map<String, dynamic>>? result = await db?.rawQuery(
      'SELECT * FROM PinnedTag WHERE booruName IS NULL OR (booruName = ? AND booruType = ?) ORDER BY sortOrder ASC, pinnedAt DESC',
      [booruName, booruType],
    );

    if (result == null || result.isEmpty) {
      return [];
    }

    return result.map(PinnedTag.fromMap).toList();
  }

  /// Get all pinned tags (regardless of booru)
  Future<List<PinnedTag>> getAllPinnedTags() async {
    final List<Map<String, dynamic>>? result = await db?.rawQuery(
      'SELECT * FROM PinnedTag ORDER BY sortOrder ASC, pinnedAt DESC',
    );

    if (result == null || result.isEmpty) {
      return [];
    }

    return result.map(PinnedTag.fromMap).toList();
  }

  /// Check if a tag is pinned (either globally or for specific booru)
  Future<PinnedTag?> getPinnedTag(String tagName, {String? booruType, String? booruName}) async {
    // First check for booru-specific pin
    if (booruName != null) {
      final booruSpecific = await db?.rawQuery(
        'SELECT * FROM PinnedTag WHERE tagName = ? AND booruName = ? AND booruType = ?',
        [tagName, booruName, booruType],
      );
      if (booruSpecific != null && booruSpecific.isNotEmpty) {
        return PinnedTag.fromMap(booruSpecific.first);
      }
    }

    // Then check for global pin
    final global = await db?.rawQuery(
      'SELECT * FROM PinnedTag WHERE tagName = ? AND booruName IS NULL',
      [tagName],
    );
    if (global != null && global.isNotEmpty) {
      return PinnedTag.fromMap(global.first);
    }

    return null;
  }

  /// Batch update sort order for multiple pinned tags
  Future<void> updatePinnedTagsOrder(List<PinnedTag> tags) async {
    final batch = db?.batch();
    for (int i = 0; i < tags.length; i++) {
      batch?.rawUpdate('UPDATE PinnedTag SET sortOrder = ? WHERE id = ?', [i, tags[i].id]);
    }
    await batch?.commit(noResult: true);
  }

  /// Update labels for a pinned tag (stored as comma-separated string)
  Future<void> updatePinnedTagLabels(int id, List<String> labels) async {
    final labelsString = labels.join(',');
    await db?.rawUpdate('UPDATE PinnedTag SET label = ? WHERE id = ?', [labelsString, id]);
  }

  /// Edit a pin: its tags, its name and where it shows (r50).
  Future<void> updatePinnedTag(int id, {required String tagName, String? title, String? booruType, String? booruName}) async {
    await db?.rawUpdate(
      'UPDATE PinnedTag SET tagName = ?, title = ?, booruType = ?, booruName = ? WHERE id = ?',
      [tagName, title, booruType, booruName, id],
    );
  }

  /// Get all unique labels from pinned tags (parses comma-separated labels)
  Future<List<String>> getPinnedTagLabels({String? booruType, String? booruName}) async {
    final List<Map<String, dynamic>>? result = await db?.rawQuery(
      "SELECT DISTINCT label FROM PinnedTag WHERE label IS NOT NULL AND label != '' AND (booruName IS NULL OR (booruName = ? AND booruType = ?))",
      [booruName, booruType],
    );

    if (result == null || result.isEmpty) {
      return [];
    }

    // Parse comma-separated labels and collect unique ones
    final Set<String> uniqueLabels = {};
    for (final row in result) {
      final labelString = row['label'] as String;
      final labels = labelString.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
      uniqueLabels.addAll(labels);
    }

    final labelsList = uniqueLabels.toList()..sort();
    return labelsList;
  }
}
