import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lolisnatcher/core/settings/settings_handler.dart';
import 'package:lolisnatcher/core/settings/source_settings_handler.dart';
import 'package:lolisnatcher/models/booru.dart';
import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/sources/booru/philomena_handler.dart';
import 'package:lolisnatcher/sources/framework/remote_media_query.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SettingsHandler.register();
    tempDir = Directory.systemTemp.createTempSync('remote_media_query');
    SettingsHandler.instance.path = '${tempDir.path}${Platform.pathSeparator}';
    SourceSettingsHandler.instance.resetForTests();
  });

  tearDown(() {
    SourceSettingsHandler.instance.resetForTests();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('Danbooru and e621 have checked media queries, and they use pipe OR', () {
    expect(remoteMediaClause(BooruType.Danbooru, 'all'), '');
    expect(remoteMediaClause(BooruType.Danbooru, 'video'), 'filetype:mp4|filetype:webm|filetype:gif');
    expect(remoteMediaClause(BooruType.Danbooru, 'image'), 'filetype:jpg|filetype:png');
    expect(remoteMediaClause(BooruType.Danbooru, 'sound'), isNull);
    expect(remoteMediaAsksSite(BooruType.Danbooru), isTrue);
    expect(remoteMediaChipValues(BooruType.Danbooru), ['all', 'image', 'video']);

    expect(remoteMediaClause(BooruType.e621, 'all'), '');
    expect(remoteMediaClause(BooruType.e621, 'video'), 'type:mp4|type:webm|type:gif');
    expect(remoteMediaClause(BooruType.e621, 'image'), 'type:jpg|type:png|type:webp');
    expect(remoteMediaClause(BooruType.e621, 'sound'), isNull);
    expect(remoteMediaAsksSite(BooruType.e621), isTrue);
    expect(remoteMediaChipValues(BooruType.e621), ['all', 'image', 'video']);

    for (final BooruType type in BooruType.values) {
      if (type == BooruType.Danbooru || type == BooruType.e621) continue;
      expect(remoteMediaClause(type, 'video'), isNull, reason: type.name);
      expect(remoteMediaAsksSite(type), isFalse, reason: type.name);
    }
  });

  test('Derpibooru asks the site, and a GIF is on Video', () {
    const String derpi = 'https://derpibooru.org';
    expect(remoteMediaClause(BooruType.Philomena, 'all', baseUrl: derpi), '');
    expect(
      remoteMediaClause(BooruType.Philomena, 'video', baseUrl: derpi),
      '"original_format:gif"|"original_format:webm"|animated:true',
    );
    expect(
      remoteMediaClause(BooruType.Philomena, 'image', baseUrl: derpi),
      'animated:false -"original_format:gif" -"original_format:webm"',
    );
    expect(remoteMediaClause(BooruType.Philomena, 'sound', baseUrl: derpi), isNull);
    expect(remoteMediaAsksSite(BooruType.Philomena, baseUrl: derpi), isTrue);
    expect(remoteMediaChipValues(BooruType.Philomena, baseUrl: derpi), ['all', 'image', 'video']);

    expect(remoteMediaClause(BooruType.Philomena, 'video'), isNull);
    expect(remoteMediaAsksSite(BooruType.Philomena), isFalse);
    expect(remoteMediaClause(BooruType.Philomena, 'video', baseUrl: 'https://ponybooru.org'), isNull);
    expect(remoteMediaAsksSite(BooruType.Philomena, baseUrl: 'https://ponerpics.org'), isFalse);

    final Booru booru = Booru('derpi', BooruType.Philomena, '', derpi, '');
    final PhilomenaHandler video = PhilomenaHandler(booru, 20)
      ..pageNum = 1
      ..mediaFilter = 'video';
    final String videoTags = video.validateTags(video.translateOrSyntax(video.sourceQuery('twilight_sparkle')).trim());
    final String videoUrl = video.makeURL(videoTags);
    expect(
      videoUrl,
      contains('q=twilight+sparkle,(original_format:gif || original_format:webm || animated:true)&'),
    );
    expect(Uri.parse(videoUrl).toString(), contains('original_format:gif%20%7C%7C%20original_format:webm%20%7C%7C%20animated:true'));

    final PhilomenaHandler image = PhilomenaHandler(booru, 20)
      ..pageNum = 1
      ..mediaFilter = 'image';
    final String imageTags = image.validateTags(image.translateOrSyntax(image.sourceQuery('')).trim());
    expect(image.makeURL(imageTags), contains('q=animated:false,-original_format:gif,-original_format:webm&'));

    final PhilomenaHandler pony = PhilomenaHandler(Booru('pony', BooruType.Philomena, '', 'https://ponybooru.org', ''), 20)
      ..mediaFilter = 'video';
    expect(pony.sourceQuery('cat'), 'cat');

    final PhilomenaHandler orGroup = PhilomenaHandler(booru, 20)..pageNum = 1;
    final String orTags = orGroup.validateTags(orGroup.translateOrSyntax(orGroup.sourceQuery('safe|explicit')).trim());
    expect(orGroup.makeURL(orTags), contains('q=(safe || explicit)&'));
    expect(orGroup.makeURL('pony score.gte:100 animated:true'), contains('q=pony,score.gte:100,animated:true&'));
  });
}
