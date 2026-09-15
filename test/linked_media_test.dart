import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/linked_media.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/pages/linked_media_page.dart';

/// r49: many FurAffinity "animated" posts are a still picture whose
/// description links to the animation. Each link resolves to a post on one of
/// the person's own sources (opened in the app's viewer), a video or animation
/// file (played in the linked media player), or a page (opened in it).
/// The description markup follows FurAffinity's own auto links.
void main() {
  final Booru e621 = Booru('e621', BooruType.e621, '', 'https://e621.net', '');
  final Booru fa = Booru('FurAffinity', BooruType.FurAffinity, '', 'https://www.furaffinity.net', '');
  final Booru r34 = Booru('rule34xxx', BooruType.Gelbooru, '', 'https://rule34.xxx', '');
  final List<Booru> installed = [e621, fa, r34];

  const String description = '''
Animated! Full video: <a class="auto_link " href="https://e621.net/posts/4011234?q=fox"title="https://e621.net/posts/4011234" >https://e621.net/posts/4011234</a><br />
mp4: <a class="auto_link " href="https://files.example.com/anim/final.mp4?token=1" >link</a>.
also <a href="https://x.com/artist/status/17890">x.com</a>, <a href="https://www.furaffinity.net/view/54848615">part 1</a>
<a href="/user/ryan-the-fox" class="iconusername">ryan</a> <a href="https://e621.net/posts/4011234?q=fox">again</a>
<a href="https://rule34.xxx/index.php?page=post&amp;s=view&amp;id=998877">r34</a> <a href="javascript:void(0);">x</a>
<a href="https://static1.e621.net/data/aa/bb/cafe.webm">webm</a> <a href="https://media.example.org/loop.gif">gif</a>
''';

  test('the links of a description, each once, in order, without profile and script links', () {
    expect(LinkedMediaResolver.linksIn(description, base: 'https://www.furaffinity.net'), [
      'https://e621.net/posts/4011234?q=fox',
      'https://files.example.com/anim/final.mp4?token=1',
      'https://x.com/artist/status/17890',
      'https://www.furaffinity.net/view/54848615',
      'https://rule34.xxx/index.php?page=post&s=view&id=998877',
      'https://static1.e621.net/data/aa/bb/cafe.webm',
      'https://media.example.org/loop.gif',
    ]);
  });

  test('each link resolves to a post on an installed source, a file, or a page', () {
    LinkedMedia r(String url) => LinkedMediaResolver.resolve(url, installed);
    final LinkedMedia post = r('https://e621.net/posts/4011234?q=fox');
    expect((post.kind, post.booru, post.postId, post.searchTerm), (LinkedMediaKind.sourcePost, e621, '4011234', 'id:4011234'));
    expect(post.label, 'Open on e621');
    expect(r('https://www.furaffinity.net/view/54848615').postId, '54848615');
    expect(r('https://rule34.xxx/index.php?page=post&s=view&id=998877').booru, r34);
    final LinkedMedia video = r('https://files.example.com/anim/final.mp4?token=1');
    expect((video.kind, video.isImage, video.label), (LinkedMediaKind.media, false, 'Play the video'));
    expect(r('https://static1.e621.net/data/aa/bb/cafe.webm').kind, LinkedMediaKind.media, reason: "a file, even on a source's file host");
    expect(r('https://media.example.org/loop.gif').isImage, isTrue);
    final LinkedMedia page = r('https://x.com/artist/status/17890');
    expect((page.kind, page.label), (LinkedMediaKind.page, 'Open x.com'));
    expect(r('https://e621.net/pools/12').kind, LinkedMediaKind.page, reason: 'not a post');
    expect(LinkedMediaResolver.resolve('https://e621.net/posts/5', [fa]).kind, LinkedMediaKind.page, reason: 'e621 is not installed');
    expect(LinkedMediaResolver.searchTermFor(Booru('paheal', BooruType.Shimmie, '', 'https://rule34.paheal.net', ''), '7'), 'id=7');
  });

  test('the player plays a file in a video element and a GIF as an image; the address is escaped', () {
    expect(
      LinkedMediaPage.mediaHtml('https://files.example.com/a.mp4?x=1&y=2'),
      contains('<video src="https://files.example.com/a.mp4?x=1&amp;y=2" controls autoplay playsinline loop>'),
    );
    expect(LinkedMediaPage.mediaHtml('https://m.example.org/a.gif', image: true), contains('<img src="https://m.example.org/a.gif">'));
    expect(LinkedMediaPage.mediaHtml('https://x.invalid/"><script>.mp4'), isNot(contains('"><script>')));
  });
}
