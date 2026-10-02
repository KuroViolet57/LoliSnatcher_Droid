import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/linked_media.dart';
import 'package:lolisnatcher/src/data/booru.dart';

/// r52: which links of a description are the post's media. The sample is the
/// FurAffinity post from the user's recording: the voice actor's site sat
/// among the media links (its domain now serves a news site), and the second
/// e621 link was plain text glued to the next line ("2197699Character(s):").
void main() {
  final Booru e621 = Booru('e621', BooruType.e621, '', 'https://e621.net', '');
  final Booru fa = Booru('FurAffinity', BooruType.FurAffinity, '', 'https://www.furaffinity.net', '');
  final List<Booru> installed = [e621, fa];

  const String description = '''
Special thanks to <a href="/user/dshooves/" class="iconusername">DShooves</a> <a class="auto_link" href="http://dshooves.live/">http://dshooves.live/</a> for providing her voice for Mal0 in the WEBM version of this animation.<br />
<br />
WEBM version with sound and blood: <a class="auto_link" href="https://e621.net/posts/2197695">https://e621.net/posts/2197695</a><br />
WEBM version with sound only: https://e621.net/posts/2197699Character(s): (SCP-Foundation) Mal0 | (Dragon-V0942) Zorphus Dragon<br />
Full res: <a href="https://www.furaffinity.net/view/24628539/">here</a> and <a href="https://www.furaffinity.net/view/99999/">this post</a><br />
Watch: <a href="https://www.youtube.com/watch?v=abc123">YouTube</a> · <a href="https://x.com/someone">my X</a> · <a href="https://x.com/someone/status/123456">clip</a><br />
<a href="https://www.patreon.com/someone">Patreon</a> <a href="https://www.patreon.com/posts/full-video-98765">Patreon post</a> <a href="https://e621.net/pools/4242">pool</a>
''';

  List<LinkedMedia> links() => LinkedMediaResolver.mediaLinksIn(
    description,
    installed,
    base: 'https://www.furaffinity.net',
    self: 'https://www.furaffinity.net/view/99999/',
  );

  test("only the post's media: other posts, files and media pages; not profiles, personal sites or the post itself", () {
    expect(links().map((l) => l.url).toList(), [
      'https://e621.net/posts/2197695',
      'https://e621.net/posts/2197699',
      'https://www.furaffinity.net/view/24628539/',
      'https://www.youtube.com/watch?v=abc123',
      'https://x.com/someone/status/123456',
      'https://www.patreon.com/posts/full-video-98765',
      'https://e621.net/pools/4242',
    ]);
  });

  test('a link without words of its own is named by its line; a link in plain text is found and cleaned', () {
    final List<LinkedMedia> l = links();
    expect(l[0].title, 'WEBM version with sound and blood');
    expect((l[1].kind, l[1].postId, l[1].title), (LinkedMediaKind.sourcePost, '2197699', 'WEBM version with sound only'));
    expect(l[2].title, 'Full res', reason: '"here" says nothing');
    expect(l[3].title, 'YouTube');
    expect(l[6].kind, LinkedMediaKind.page);
  });

  test('media pages by site and path', () {
    bool media(String url) => LinkedMediaResolver.isMediaPage(Uri.parse(url));
    expect(media('https://youtu.be/abc'), isTrue);
    expect(media('https://vimeo.com/123456'), isTrue);
    expect(media('https://twitter.com/a/status/1'), isTrue);
    expect(media('https://twitter.com/a'), isFalse);
    expect(media('https://www.newgrounds.com/portal/view/12345'), isTrue);
    expect(media('https://www.redgifs.com/watch/somegif'), isTrue);
    expect(media('https://mega.nz/file/abc#key'), isTrue);
    expect(media('https://drive.google.com/file/d/abc/view'), isTrue);
    expect(media('https://www.pixiv.net/en/artworks/123'), isTrue);
    expect(media('https://inkbunny.net/s/123'), isTrue);
    expect(media('https://ko-fi.com/someone'), isFalse);
    expect(media('https://linktr.ee/someone'), isFalse);
    expect(media('https://discord.gg/abc'), isFalse);
    expect(media('http://dshooves.live/'), isFalse);
  });

  test('the store keeps each post\'s links and says when they change', () {
    LinkedMediaStore.resetForTests();
    int changes = 0;
    void listener() => changes++;
    LinkedMediaStore.revision.addListener(listener);
    addTearDown(() => LinkedMediaStore.revision.removeListener(listener));
    expect(LinkedMediaStore.linksFor('https://www.furaffinity.net/view/1/'), isNull);
    LinkedMediaStore.remember('https://www.furaffinity.net/view/1/', links());
    expect(LinkedMediaStore.hasLinks('https://www.furaffinity.net/view/1/'), isTrue);
    LinkedMediaStore.remember('https://www.furaffinity.net/view/2/', const []);
    expect(LinkedMediaStore.hasLinks('https://www.furaffinity.net/view/2/'), isFalse);
    expect(changes, 2);
  });
}
