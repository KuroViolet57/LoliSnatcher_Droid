import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/recommender/look_memory.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// r81: "Remember the looks of posts you open" (Settings → Recommendations
/// → Models → Looks model). A post you looked at for a moment has its look
/// saved when you leave it, so For You, boards and the learner find it
/// ready later. A video's look comes from the frames already taken (the
/// looks model reads memory and the database first), so nothing is read
/// twice.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LookMemory memory;
  late DateTime now;
  late List<String> remembered;
  late bool wanted;

  BooruItem post(String id, {String host = 'gelbooru.com', bool video = false}) => BooruItem(
    fileURL: 'https://img.$host/f/$id.${video ? 'mp4' : 'jpg'}',
    sampleURL: 'https://img.$host/s/$id.jpg',
    thumbnailURL: 'https://img.$host/t/$id.jpg',
    tagsList: [Tag('solo')],
    postURL: 'https://$host/index.php?page=post&s=view&id=$id',
  );

  Future<void> open(BooruItem? item) async {
    ViewerHandler.instance.current.value = item;
    await pumpEventQueue();
  }

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    ViewerHandler.instance.current.value = null;
    now = DateTime(2026, 9, 22, 12);
    remembered = [];
    wanted = true;
    memory = LookMemory()
      ..now = (() => now)
      ..wanted = (() => wanted)
      ..booruNow = (() => null)
      ..queue = ((String label, Future<void> Function() step) => step())
      ..remember = ((BooruItem item, Booru? booru) async => remembered.add(item.postURL));
    memory.attach();
  });

  tearDown(() {
    memory.detach();
    ViewerHandler.instance.current.value = null;
  });

  test('the switch is off until you turn it on', () {
    expect(SettingsHandler.instance.rememberLooks, isFalse);
    expect(LookMemory().wanted(), isFalse, reason: 'switch off, no looks model');
  });

  test('a post you looked at for 2.5 s or more is remembered when you leave it; a glance is not', () async {
    await open(post('a'));
    now = now.add(const Duration(seconds: 3));
    await open(post('b'));
    expect(remembered, [post('a').postURL]);

    now = now.add(const Duration(seconds: 1));
    await open(post('c'));
    expect(remembered, [post('a').postURL], reason: 'b was a glance');

    now = now.add(const Duration(seconds: 4));
    await open(null);
    expect(remembered, [post('a').postURL, post('c').postURL], reason: 'closing the viewer leaves c too');
  });

  test('a video is remembered the same way: its look comes from the frames already taken', () async {
    await open(post('v', video: true));
    now = now.add(const Duration(seconds: 10));
    await open(null);
    expect(remembered, [post('v', video: true).postURL]);
  });

  test('nothing with the switch or the looks model off, for a hidden post or a doujin item; a post once per run', () async {
    wanted = false;
    await open(post('a'));
    now = now.add(const Duration(seconds: 5));
    await open(null);
    expect(remembered, isEmpty);

    wanted = true;
    final BooruItem hidden = post('h')..hiddenInSource = true;
    await open(hidden);
    now = now.add(const Duration(seconds: 5));
    await open(post('n', host: 'nhentai.net'));
    now = now.add(const Duration(seconds: 5));
    await open(null);
    expect(remembered, isEmpty, reason: 'hidden, then a doujin item');

    await open(post('once'));
    now = now.add(const Duration(seconds: 5));
    await open(null);
    await open(post('once'));
    now = now.add(const Duration(seconds: 5));
    await open(null);
    expect(remembered, [post('once').postURL], reason: 'asked once per run');
  });
}
