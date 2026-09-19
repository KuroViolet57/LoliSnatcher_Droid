import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/recommender/image_tagger_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/pixel_tags.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

/// r76: "Tag reactions with the picture" reads a video's frames when the
/// player gave some (the first, the middle and the last), merging their tags
/// by best confidence; otherwise the preview picture, as in r74.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SettingsHandler.register();
    PixelTags.resetForTests();
  });
  tearDown(PixelTags.resetForTests);

  BooruItem post() => BooruItem(fileURL: 'https://img.x/v.mp4', sampleURL: '', thumbnailURL: 'https://img.x/t.jpg', tagsList: const [], postURL: 'https://x/p/1');

  PixelTag c(String t, double p) => (tag: t, confidence: p, character: true);
  PixelTag g(String t, double p) => (tag: t, confidence: p, character: false);

  test('three frames of five are read (first, middle, last) and their tags merged: characters first, each tag at its best confidence', () async {
    final List<Uint8List> kept = [for (int i = 0; i < 5; i++) Uint8List.fromList([i, i, i])];
    final List<Uint8List> asked = [];
    final Map<int, TaggerResult> answers = {
      0: TaggerResult(general: [g('beach', 0.6), g('solo', 0.5)], characters: [c('hatsune_miku', 0.9)], rating: 'general', ratingConfidence: 0.8),
      2: TaggerResult(general: [g('beach', 0.8), g('night', 0.4)], characters: const [], rating: 'general', ratingConfidence: 0.8),
      4: TaggerResult(general: [g('solo', 0.7)], characters: [c('hatsune_miku', 0.95), c('kagamine_rin', 0.88)], rating: 'general', ratingConfidence: 0.8),
    };
    PixelTags.taggerReady = () => true;
    PixelTags.framesFor = (BooruItem item) => kept;
    PixelTags.tagBytes = (Uint8List bytes) async {
      asked.add(bytes);
      return answers[bytes.first]!;
    };
    PixelTags.thumbnail = (BooruItem item, Booru? booru) async => throw StateError('the preview picture must not be read when frames exist');
    final List<String> names = await PixelTags.forItem(post(), null);
    expect(asked, hasLength(3));
    expect(asked[0], same(kept[0]));
    expect(asked[1], same(kept[2]));
    expect(asked[2], same(kept[4]));
    expect(names, ['hatsune_miku', 'kagamine_rin', 'beach', 'solo', 'night']);
  });

  test('one or two frames are each read once; no frames: the preview picture, as before; no tagger: nothing', () async {
    final List<Uint8List> asked = [];
    PixelTags.taggerReady = () => true;
    PixelTags.tagBytes = (Uint8List bytes) async {
      asked.add(bytes);
      return TaggerResult(general: [g('t${bytes.first}', 0.5)], characters: const [], rating: 'general', ratingConfidence: 0.5);
    };
    PixelTags.framesFor = (BooruItem item) => [Uint8List.fromList([7]), Uint8List.fromList([8])];
    expect(await PixelTags.forItem(post(), null), ['t7', 't8']);
    expect(asked, hasLength(2));

    asked.clear();
    final Uint8List thumb = Uint8List.fromList([9]);
    PixelTags.framesFor = (BooruItem item) => const [];
    PixelTags.thumbnail = (BooruItem item, Booru? booru) async => thumb;
    expect(await PixelTags.forItem(post(), null), ['t9']);
    expect(asked.single, same(thumb));

    PixelTags.taggerReady = () => false;
    expect(await PixelTags.forItem(post(), null), isEmpty);
  });
}
