import 'package:flutter_test/flutter_test.dart';
import 'package:lolisnatcher/models/booru_pool.dart';
import 'package:lolisnatcher/sources/booru/pools/pool_source.dart';

/// Captured 2026-10-07 in headless Chrome.
/// rule34.xxx pool list row and `<span class="thumb" id="p7637309">`.
/// gelbooru.com list row (icon link, then the named link) and
/// `<span class="" id="p14946467">` on the show page.
void main() {
  test('rule34 and gelbooru.com pool rows keep the name, creator and count', () {
    final List<BooruPool> rule34 = GelbooruHtmlPoolSource.poolsFromHtml('''
<table><tr>
<td><a href="index.php?page=pool&amp;s=show&amp;id=58940">great goony moogly</a></td>
<td><a href="index.php?page=account&amp;s=profile&amp;uname=canocoke">canocoke</a></td>
<td>4</td><td>No</td>
</tr></table>
''');
    expect(rule34, hasLength(1));
    expect(rule34.single.id, '58940');
    expect(rule34.single.name, 'great goony moogly');
    expect(rule34.single.creator, 'canocoke');
    expect(rule34.single.postCount, 4);

    final List<BooruPool> gelbooru = GelbooruHtmlPoolSource.poolsFromHtml('''
<table><tr>
<td><a href="index.php?page=pool&amp;s=show&amp;id=74221"><img alt="pool"></a></td>
<td>
  <div><a href="index.php?page=pool&amp;s=show&amp;id=74221">Hiqeui</a></div>
  <span>Created by <a href="index.php?page=account&amp;s=profile&amp;uname=Hiqeui">Hiqeui</a></span>
</td>
<td><b>3&nbsp;Images</b></td>
</tr></table>
''');
    expect(gelbooru, hasLength(1));
    expect(gelbooru.single.id, '74221');
    expect(gelbooru.single.name, 'Hiqeui');
    expect(gelbooru.single.creator, 'Hiqeui');
    expect(gelbooru.single.postCount, 3);
  });

  test('member ids come from thumb spans and from gelbooru empty-class spans', () {
    final List<String> ids = GelbooruHtmlPoolSource.postIdsFromHtml(
      '<span class="thumb" id="p7637309"></span>'
      '<span class="" id="p14946467"></span>'
      '<span class="thumbnail-preview" id="p1"></span>'
      '<div id="p2"></div>',
    );
    expect(ids, ['7637309', '14946467']);
  });
}
