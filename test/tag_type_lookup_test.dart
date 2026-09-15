import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/gelbooru_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_type_lookup.dart';
import 'package:lolisnatcher/src/pages/tag_hub_page.dart';
import 'package:lolisnatcher/src/utils/hub_tag_query.dart';

/// r50: a tag's type as the post's own source reported it, even where the
/// app-wide tag store is not written (a strip's preview tab, the floating
/// preview) — e621's modelers sat in General there; the Artist hub follows
/// the same answer; and a hub asks other sources for the bare name, not the
/// namespace one site writes into its tags.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Booru fa = Booru('FurAffinity', BooruType.FurAffinity, '', 'https://www.furaffinity.net', '');
  final Booru e621 = Booru('e621', BooruType.e621, '', 'https://e621.net', '');
  final Booru dan = Booru('danbooru', BooruType.Danbooru, '', 'https://danbooru.donmai.us', '');
  final Booru derpi = Booru('derpi', BooruType.Philomena, '', 'https://derpibooru.org', '');
  late Directory tempDir;

  setUp(() {
    SettingsHandler.register();
    SearchHandler.register();
    TagHandler.register();
    NavigationHandler.register();
    tempDir = Directory.systemTemp.createTempSync('tag_type_lookup');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test("a source keeps the types it parsed for its own items, even when it does not write the app's store", () {
    final GelbooruHandler handler = GelbooruHandler(e621, 20)..storeTagsGlobally = false;
    handler.addTagsWithType(['Coel3D_(Modeler)'], TagType.contributor);
    handler.addTagsWithType(['drkrakkenn'], TagType.artist);
    handler.addTagsWithType(['fur'], TagType.none);
    expect(handler.ownTagType('coel3d_(modeler)'), TagType.contributor);
    expect(TagHandler.instance.hasTag('coel3d_(modeler)'), isFalse, reason: 'the app-wide store stays untouched');

    expect(TagTypeLookup.resolve(Tag('coel3d_(modeler)'), booru: e621, handler: handler), TagType.contributor);
    expect(TagTypeLookup.resolve(Tag('drkrakkenn'), booru: e621, handler: handler), TagType.artist);
    expect(TagTypeLookup.resolve(Tag('fur'), booru: e621, handler: handler), TagType.none);
    expect(
      TagTypeLookup.resolve(Tag('artist:someone', tagType: TagType.artist), booru: fa),
      TagType.artist,
      reason: 'the type the tag itself carries (FurAffinity artists)',
    );
  });

  test('a hub asks another source for the bare name; the origin, and sites whose tags carry the namespace, keep it', () {
    expect(HubTagQuery.forBooru('artist:drkrakkenn', origin: fa, target: e621), 'drkrakkenn');
    expect(HubTagQuery.forBooru('character:rouge_the_bat -species:bat solo', origin: fa, target: dan), 'rouge_the_bat -bat solo');
    expect(HubTagQuery.forBooru('artist:drkrakkenn', origin: fa, target: fa), 'artist:drkrakkenn');
    expect(HubTagQuery.forBooru('artist:foo_bar', origin: fa, target: derpi), 'artist:foo_bar', reason: "Derpibooru's artist tags are named artist:x");
    expect(HubTagQuery.forBooru('rating:safe', origin: fa, target: e621), 'rating:safe', reason: 'not a tag type namespace');
    expect(HubTagQuery.forBooru('drkrakkenn', origin: e621, target: dan), 'drkrakkenn');
  });

  test('the hub trusts the type the tag sheet resolved: an artist opens the Artist hub', () {
    expect(
      TagHubPage.typeFor('artist:drkrakkenn', originBooru: fa),
      TagType.none,
      reason: 'the shared store never stored it: the page called itself "Tag hub"',
    );
    expect(TagHubPage.typeFor('artist:drkrakkenn', originBooru: fa, knownType: TagType.artist), TagType.artist);
  });
}
