import 'package:lolisnatcher/src/data/tag_type.dart';

/// Where a tag's type came from, **for one specific booru**.
///
/// The app has always stored one type per tag string, globally. That is fine
/// until two sites disagree — rule34.xxx calls `pokemon` a copyright, another
/// site files the same string under general — at which point whichever site
/// you browsed last silently repaints the other one. This enum is the missing
/// piece of information: not just "what type", but "who says so".
enum TagTypeOrigin {
  /// You set it by hand for this booru. Wins over everything, and the pair is
  /// permanently excluded from automatic correction.
  manual,

  /// This booru's own API reported it.
  reported,

  /// Carried over from an imported snapshot, or from the app's global tag
  /// store (i.e. some *other* booru classified it). Shown with a dashed
  /// outline so a guess never looks like a fact.
  inferred,

  /// Nothing knows.
  unknown;

  bool get isManual => this == manual;
  bool get isReported => this == reported;
  bool get isInferred => this == inferred;
  bool get isUnknown => this == unknown;

  String get label => switch (this) {
    manual => 'yours',
    reported => 'reported',
    inferred => 'inferred',
    unknown => 'untyped',
  };
}

/// One tag as a single booru knows it.
class BooruTagEntry {
  const BooruTagEntry({
    required this.name,
    required this.tagType,
    this.count = 0,
    this.origin = TagTypeOrigin.reported,
    this.updatedAt = 0,
  });

  factory BooruTagEntry.fromJson(Map<String, dynamic> json) {
    return BooruTagEntry(
      name: (json['n'] ?? json['name'] ?? '').toString(),
      tagType: TagType.fromString((json['t'] ?? json['tagType'] ?? 'none').toString()),
      count: int.tryParse((json['c'] ?? json['count'] ?? 0).toString()) ?? 0,
      origin: TagTypeOrigin.values.firstWhere(
        (o) => o.name == (json['o'] ?? json['origin'])?.toString(),
        orElse: () => TagTypeOrigin.reported,
      ),
      updatedAt: int.tryParse((json['u'] ?? json['updatedAt'] ?? 0).toString()) ?? 0,
    );
  }

  final String name;
  final TagType tagType;
  final int count;
  final TagTypeOrigin origin;
  final int updatedAt;

  /// Short keys: a snapshot is tens of thousands of rows and gets shipped
  /// around as a file, so the field names are half its size otherwise.
  Map<String, dynamic> toJson() => {
    'n': name,
    't': tagType.name,
    if (count > 0) 'c': count,
    if (origin != TagTypeOrigin.reported) 'o': origin.name,
  };

  String get displayName => name.replaceAll('_', ' ');

  BooruTagEntry copyWith({TagType? tagType, int? count, TagTypeOrigin? origin, int? updatedAt}) {
    return BooruTagEntry(
      name: name,
      tagType: tagType ?? this.tagType,
      count: count ?? this.count,
      origin: origin ?? this.origin,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
