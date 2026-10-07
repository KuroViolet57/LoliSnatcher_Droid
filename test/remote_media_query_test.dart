import 'package:flutter_test/flutter_test.dart';
import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/sources/framework/remote_media_query.dart';

void main() {
  test('Danbooru and e621 have checked media queries, and they use pipe OR', () {
    expect(remoteMediaClause(BooruType.Danbooru, 'all'), '');
    expect(remoteMediaClause(BooruType.Danbooru, 'video'), 'filetype:mp4|filetype:webm');
    expect(remoteMediaClause(BooruType.Danbooru, 'image'), 'filetype:jpg|filetype:png|filetype:gif');
    expect(remoteMediaClause(BooruType.Danbooru, 'sound'), isNull);
    expect(remoteMediaAsksSite(BooruType.Danbooru), isTrue);
    expect(remoteMediaChipValues(BooruType.Danbooru), ['all', 'image', 'video']);

    expect(remoteMediaClause(BooruType.e621, 'all'), '');
    expect(remoteMediaClause(BooruType.e621, 'video'), 'type:mp4|type:webm');
    expect(remoteMediaClause(BooruType.e621, 'image'), 'type:jpg|type:png|type:gif|type:webp');
    expect(remoteMediaClause(BooruType.e621, 'sound'), isNull);
    expect(remoteMediaAsksSite(BooruType.e621), isTrue);
    expect(remoteMediaChipValues(BooruType.e621), ['all', 'image', 'video']);

    for (final BooruType type in BooruType.values) {
      if (type == BooruType.Danbooru || type == BooruType.e621) continue;
      expect(remoteMediaClause(type, 'video'), isNull, reason: type.name);
      expect(remoteMediaAsksSite(type), isFalse, reason: type.name);
    }
  });
}
