import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/features/downloads/logic/image_writer.dart';
import 'package:lolisnatcher/models/booru_item.dart';
import 'package:lolisnatcher/models/tag.dart';

/// Settings → Save & cache → write image data to JSON on save: the .json next
/// to a download in a picked folder (Android 12 and later).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(SettingsHandler.register);

  test('1.0: Japanese tags and titles reach the JSON file as UTF-8, not cut to one byte per character', () {
    final BooruItem item = BooruItem(
      fileURL: 'https://img3.gelbooru.com/images/aa/bb/1.jpg',
      sampleURL: 'https://img3.gelbooru.com/samples/aa/bb/1.jpg',
      thumbnailURL: 'https://img3.gelbooru.com/thumbnails/aa/bb/1.jpg',
      tagsList: [Tag('東方'), Tag('博麗霊夢'), Tag('reimu')],
      postURL: 'https://gelbooru.com/index.php?page=post&s=view&id=1',
      md5String: '霊夢 — 🌸',
    );

    final String written = utf8.decode(ImageWriter.jsonSidecarBytes(item));

    expect(written, jsonEncode(item.toJson()));
    expect(written, contains('博麗霊夢'));
    expect((jsonDecode(written) as Map)['md5String'], '霊夢 — 🌸');
  });
}
