import 'package:lolisnatcher/src/handlers/board_query.dart';
import 'package:lolisnatcher/src/handlers/reverse_image_search.dart';

/// A board (r73): a saved "find me posts like this" search. A description
/// in plain words and/or a reference image say what to look for; the
/// must-have tags are enforced on every result; the excluded tags never
/// appear; the sources name the boorus to ask (none = every eligible one).
class Board {
  Board({
    required this.id,
    required this.name,
    this.description = '',
    List<String>? mustTags,
    List<String>? excludeTags,
    List<String>? sourceNames,
    this.imagePath = '',
    this.imageUrl = '',
    this.imageBooru = '',
    List<ReverseMatch>? matches,
    this.matchedAt,
    this.matchedImage = '',
    List<WeightedTag>? pixelTags,
    this.pixelImage = '',
    this.hidden = false,
    List<double>? lookVector,
    this.lookImage = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : mustTags = List<String>.from(mustTags ?? const <String>[]),
       excludeTags = List<String>.from(excludeTags ?? const <String>[]),
       sourceNames = List<String>.from(sourceNames ?? const <String>[]),
       matches = matches == null ? null : List<ReverseMatch>.unmodifiable(matches),
       pixelTags = pixelTags == null ? null : List<WeightedTag>.unmodifiable(pixelTags),
       lookVector = lookVector == null ? null : List<double>.unmodifiable(lookVector),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  final String id;
  final String name;
  final String description;
  final List<String> mustTags;
  final List<String> excludeTags;

  /// Names of the boorus to ask; empty means every eligible source.
  final List<String> sourceNames;

  /// A copy of the reference image under the app's `boards/` folder.
  final String imagePath;

  /// The reference image's web address (a post's sample, or a pasted url).
  final String imageUrl;

  /// The booru the image came from: its headers fetch the copy.
  final String imageBooru;

  /// The reverse-image matches, cached with the image they were made from
  /// ([matchedImage] = [imageKey] at the time) so a tab re-opened later
  /// asks SauceNAO nothing.
  final List<ReverseMatch>? matches;
  final DateTime? matchedAt;
  final String matchedImage;

  /// r74: what the downloaded tagger read in the image, as seeds for the
  /// search, cached with the image and the model ([pixelImage] =
  /// [pixelKey] at the time).
  final List<WeightedTag>? pixelTags;
  final String pixelImage;

  /// r75: a board made by "Posts like this": kept out of the list and
  /// forgotten after [BoardsHandler.hiddenLifetime].
  final bool hidden;

  /// r75: the reference image through the looks model, cached with the
  /// image and the model ([lookImage] = [pixelKey] at the time).
  final List<double>? lookVector;
  final String lookImage;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasImage => imagePath.isNotEmpty || imageUrl.isNotEmpty;

  /// What the reverse-image search reads: the copy wins over the address.
  String get imageKey => imagePath.isNotEmpty ? 'file:$imagePath' : (imageUrl.isNotEmpty ? 'url:$imageUrl' : '');

  /// The cache holds for the same image; an EMPTY answer (an index down,
  /// a picture nobody indexed) is trusted for a day only.
  bool get hasFreshMatches {
    if (matches == null || matchedImage.isEmpty || matchedImage != imageKey) return false;
    if (matches!.isNotEmpty) return true;
    return matchedAt != null && DateTime.now().difference(matchedAt!) < const Duration(hours: 24);
  }

  /// The image and the model a set of pixel tags belongs to.
  String pixelKey(String modelId) => '$imageKey@$modelId';

  /// The cached pixel tags hold for the same image read by the same model.
  bool hasFreshPixelTags(String modelId) => pixelTags != null && modelId.isNotEmpty && pixelImage == pixelKey(modelId);

  /// The cached look vector holds for the same image read by the same model.
  bool hasFreshLook(String modelId) => lookVector != null && lookVector!.isNotEmpty && modelId.isNotEmpty && lookImage == pixelKey(modelId);

  /// Tags typed by hand: split on spaces and commas, lowercase, a leading
  /// `-` or `~` dropped (the field itself says whether the tag is wanted
  /// or excluded), duplicates removed.
  static List<String> parseTags(String text) {
    final List<String> out = [];
    for (final String raw in text.split(RegExp(r'[\s,]+'))) {
      String t = raw.trim().toLowerCase();
      while (t.startsWith('-') || t.startsWith('~')) {
        t = t.substring(1);
      }
      if (t.isEmpty || out.contains(t)) continue;
      out.add(t);
    }
    return out;
  }

  /// The first words of the description, for a board saved without a name.
  static String nameFromDescription(String description, {int words = 6}) {
    final List<String> parts = description.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (parts.isEmpty) return 'Board';
    return parts.take(words).join(' ');
  }

  Board copyWith({
    String? id,
    String? name,
    String? description,
    List<String>? mustTags,
    List<String>? excludeTags,
    List<String>? sourceNames,
    String? imagePath,
    String? imageUrl,
    String? imageBooru,
    List<ReverseMatch>? matches,
    DateTime? matchedAt,
    String? matchedImage,
    List<WeightedTag>? pixelTags,
    String? pixelImage,
    bool? hidden,
    List<double>? lookVector,
    String? lookImage,
    bool clearMatches = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Board(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    mustTags: mustTags ?? this.mustTags,
    excludeTags: excludeTags ?? this.excludeTags,
    sourceNames: sourceNames ?? this.sourceNames,
    imagePath: imagePath ?? this.imagePath,
    imageUrl: imageUrl ?? this.imageUrl,
    imageBooru: imageBooru ?? this.imageBooru,
    matches: clearMatches ? null : (matches ?? this.matches),
    matchedAt: clearMatches ? null : (matchedAt ?? this.matchedAt),
    matchedImage: clearMatches ? '' : (matchedImage ?? this.matchedImage),
    pixelTags: clearMatches ? null : (pixelTags ?? this.pixelTags),
    pixelImage: clearMatches ? '' : (pixelImage ?? this.pixelImage),
    hidden: hidden ?? this.hidden,
    lookVector: clearMatches ? null : (lookVector ?? this.lookVector),
    lookImage: clearMatches ? '' : (lookImage ?? this.lookImage),
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'mustTags': mustTags,
    'excludeTags': excludeTags,
    'sourceNames': sourceNames,
    'imagePath': imagePath,
    'imageUrl': imageUrl,
    'imageBooru': imageBooru,
    'matches': matches?.map((m) => m.toJson()).toList(),
    'matchedAt': matchedAt?.millisecondsSinceEpoch,
    'matchedImage': matchedImage,
    'pixelTags': pixelTags?.map((t) => {'tag': t.tag, 'weight': t.weight}).toList(),
    'pixelImage': pixelImage,
    'hidden': hidden,
    'lookVector': lookVector,
    'lookImage': lookImage,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  factory Board.fromJson(Map<String, dynamic> json) {
    List<String> strings(dynamic v) => v is List ? [for (final e in v) e.toString()] : const <String>[];
    DateTime? when(dynamic v) => v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
    return Board(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      mustTags: strings(json['mustTags']),
      excludeTags: strings(json['excludeTags']),
      sourceNames: strings(json['sourceNames']),
      imagePath: json['imagePath']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString() ?? '',
      imageBooru: json['imageBooru']?.toString() ?? '',
      matches: json['matches'] is List
          ? [for (final dynamic m in json['matches'] as List) if (m is Map) ReverseMatch.fromJson(Map<String, dynamic>.from(m))]
          : null,
      matchedAt: when(json['matchedAt']),
      matchedImage: json['matchedImage']?.toString() ?? '',
      pixelTags: json['pixelTags'] is List
          ? [
              for (final dynamic t in json['pixelTags'] as List)
                if (t is Map && t['tag'] != null) (tag: t['tag'].toString(), weight: (t['weight'] as num?)?.toDouble() ?? 0),
            ]
          : null,
      pixelImage: json['pixelImage']?.toString() ?? '',
      hidden: json['hidden'] == true,
      lookVector: json['lookVector'] is List ? [for (final dynamic x in json['lookVector'] as List) (x as num).toDouble()] : null,
      lookImage: json['lookImage']?.toString() ?? '',
      createdAt: when(json['createdAt']),
      updatedAt: when(json['updatedAt']),
    );
  }
}
