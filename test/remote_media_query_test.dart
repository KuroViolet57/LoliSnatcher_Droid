import 'package:flutter_test/flutter_test.dart';
import 'package:lolisnatcher/models/booru_type.dart';
import 'package:lolisnatcher/sources/framework/remote_media_query.dart';

void main() {
  test('only Danbooru has a checked media query, and it uses pipe OR', () {
    expect(remoteMediaClause(BooruType.Danbooru, 'all'), '');
    expect(remoteMediaClause(BooruType.Danbooru, 'video'), 'filetype:mp4|filetype:webm');
    expect(remoteMediaClause(BooruType.Danbooru, 'image'), 'filetype:jpg|filetype:png|filetype:gif');
    expect(remoteMediaClause(BooruType.Danbooru, 'sound'), isNull);
    expect(remoteMediaAsksSite(BooruType.Danbooru), isTrue);
    expect(remoteMediaChipValues(BooruType.Danbooru), ['all', 'image', 'video']);

    for (final BooruType type in BooruType.values) {
      if (type == BooruType.Danbooru) continue;
      expect(remoteMediaClause(type, 'video'), isNull, reason: type.name);
      expect(remoteMediaAsksSite(type), isFalse, reason: type.name);
    }
  });
}
