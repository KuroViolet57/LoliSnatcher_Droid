part of '../database_handler.dart';

/// The Tag table (types for colouring) and the ImageTag links of saved posts.
extension DBTags on DBHandler {
  Future<List<Tag>> getAllTags() async {
    final List? result = await db?.rawQuery('SELECT name, tagType, updatedAt FROM Tag');
    final List<Tag> tags = [];
    if (result != null && result.isNotEmpty) {
      for (int i = 0; i < result.length; i++) {
        final currentItem = result[i];
        if (currentItem != null && currentItem.isNotEmpty) {
          tags.add(Tag.fromJson(currentItem));
        }
      }
    }
    return tags;
  }

  /// Adds tags for a BooruItem to the database
  Future<void> updateTags(List<String> tags, String? itemID) async {
    if (itemID == null) {
      return;
    }
    String? id = '';
    // TODO rewrite using batch
    for (final tag in tags) {
      id = await getTagID(tag);
      if (id.isEmpty) {
        final result = await db?.rawInsert('INSERT INTO Tag(name) VALUES(?)', [tag]);
        id = result?.toString();
      }
      await db?.rawInsert('INSERT INTO ImageTag(tagID, booruItemID) VALUES(?,?)', [id, itemID]);
    }
  }

  /// Adds tags for a BooruItem to the database
  Future<void> updateTagsFromObjects(List<Tag> tags) async {
    String? id = '';
    // TODO rewrite using batch
    for (final tag in tags) {
      id = await getTagID(tag.fullString);
      if (id.isEmpty) {
        final result = await db?.rawInsert('INSERT INTO Tag(name, tagType, updatedAt) VALUES(?,?,?)', [
          tag.fullString,
          tag.tagType.name,
          tag.updatedAt,
        ]);
        id = result?.toString();
      } else {
        await db?.rawUpdate('UPDATE Tag SET tagType = ?,updatedAt = ? WHERE id = ?', [
          tag.tagType.name,
          tag.updatedAt,
          id,
        ]);
      }
    }
    return;
  }

  /// Gets a tag id from the database
  Future<String> getTagID(String tagName) async {
    // TODO rewrite using batch
    final result = await db?.rawQuery('SELECT id FROM Tag WHERE name IN (?)', [tagName]);
    if (result != null && result.isNotEmpty) {
      return result.first['id'].toString();
    } else {
      return '';
    }
  }

  /// Get tags sorted by usage count (how many items they're attached to)
  /// If [queryStr] is provided, filters tags that start with the query
  /// Returns a list of maps with 'name' and 'count' keys
  Future<List<({String name, int count})>> getTagsByUsageCount(String? queryStr, int limit) async {
    final List<({String name, int count})> tags = [];

    String query;
    List<Object?> args;

    if (queryStr != null && queryStr.isNotEmpty) {
      query = '''
        SELECT t.name, COUNT(it.booruItemID) as count
        FROM Tag t
        LEFT JOIN ImageTag it ON t.id = it.tagID
        WHERE lower(t.name) LIKE (?)
        GROUP BY t.id
        ORDER BY count DESC
        LIMIT ?
      ''';
      args = ['${queryStr.toLowerCase()}%', limit];
    } else {
      query = '''
        SELECT t.name, COUNT(it.booruItemID) as count
        FROM Tag t
        LEFT JOIN ImageTag it ON t.id = it.tagID
        GROUP BY t.id
        ORDER BY count DESC
        LIMIT ?
      ''';
      args = [limit];
    }

    final result = await db?.rawQuery(query, args);
    if (result != null && result.isNotEmpty) {
      for (final row in result) {
        final name = row['name']?.toString() ?? '';
        final count = row['count'] as int? ?? 0;
        if (name.isNotEmpty) {
          tags.add((name: name, count: count));
        }
      }
    }
    return tags;
  }
}
