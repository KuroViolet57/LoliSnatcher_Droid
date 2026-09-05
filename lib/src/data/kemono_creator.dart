import 'package:lolisnatcher/src/boorus/kemono_site.dart';

/// One row of kemono's creator index (`/api/v1/creators`): who, on which
/// service, when the site last saw them, how many accounts favourited them.
class KemonoCreator {
  const KemonoCreator({
    required this.service,
    required this.id,
    required this.name,
    this.indexed = 0,
    this.updated = 0,
    this.favorited = 0,
    this.site = KemonoSite.kemono,
  });

  final String service;
  final String id;
  final String name;

  /// Unix seconds.
  final int indexed;
  final int updated;
  final int favorited;

  /// Which site's index the row came from (icons and banners live there).
  final KemonoSite site;

  String get key => '$service:$id';
  String get iconUrl => site.iconUrl(service, id);
  String get bannerUrl => site.bannerUrl(service, id);
  String get searchQuery => 'creator:$service:$id';
  DateTime get updatedAt => DateTime.fromMillisecondsSinceEpoch(updated * 1000);

  /// A row of the index (epoch ints) or of a live endpoint (ISO strings).
  static KemonoCreator? fromJson(Map row, {KemonoSite site = KemonoSite.kemono}) {
    final String service = row['service']?.toString() ?? '';
    final String id = row['id']?.toString() ?? '';
    if (service.isEmpty || id.isEmpty) return null;
    return KemonoCreator(
      service: service,
      id: id,
      name: row['name']?.toString() ?? '',
      indexed: epochOf(row['indexed']),
      updated: epochOf(row['updated']),
      favorited: int.tryParse(row['favorited']?.toString() ?? '') ?? 0,
      site: site,
    );
  }

  /// Seconds out of an epoch number or an ISO timestamp; 0 when neither.
  static int epochOf(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    final String text = value.toString();
    final int? asInt = int.tryParse(text);
    if (asInt != null) return asInt;
    final DateTime? parsed = DateTime.tryParse(text);
    return parsed == null ? 0 : parsed.millisecondsSinceEpoch ~/ 1000;
  }

  static KemonoCreator fromRow(Map<String, Object?> row, {KemonoSite site = KemonoSite.kemono}) => KemonoCreator(
    service: row['service']?.toString() ?? '',
    id: row['id']?.toString() ?? '',
    name: row['name']?.toString() ?? '',
    indexed: int.tryParse(row['indexed']?.toString() ?? '') ?? 0,
    updated: int.tryParse(row['updated']?.toString() ?? '') ?? 0,
    favorited: int.tryParse(row['favorited']?.toString() ?? '') ?? 0,
    site: site,
  );
}
