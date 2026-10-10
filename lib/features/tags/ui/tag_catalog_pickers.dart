import 'package:lolisnatcher/features/kemono/ui/kemono_artists_page.dart';
import 'package:lolisnatcher/sources/framework/tags/tag_catalog_source.dart';
import 'package:lolisnatcher/sources/kemono/kemono_tag_catalog.dart';

/// The page a namespace's chip opens in place of the generic list sheet.
/// Sources name the picker ([TagCatalogNamespace.pickerId]); the pages live
/// in the ui layer, so the ids are resolved here. Null = the generic sheet.
TagCatalogPicker? tagCatalogPicker(TagCatalogNamespace namespace) => switch (namespace.pickerId) {
  KemonoTagCatalog.artistsPicker => KemonoArtistsPage.pick,
  KemonoTagCatalog.creatorTagsPicker => KemonoCreatorTagsSheet.pick,
  _ => null,
};
