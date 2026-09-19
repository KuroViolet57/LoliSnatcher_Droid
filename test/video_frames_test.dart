import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/settings/mpv_video_output.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/recommender/look_model_handler.dart';
import 'package:lolisnatcher/src/handlers/recommender/model_work.dart';
import 'package:lolisnatcher/src/handlers/recommender/video_frames.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';

/// r76: frames from the playing video. While a video is the one on screen,
/// mpv is asked (through media_kit's normal command call) to write the frame
/// it shows to a file; the frames replace the preview picture for the looks
/// model, "posts like this" and the tagger. The player here is a fake that
/// records what it was asked and writes a known picture.
class _FakeTarget implements FrameTarget {
  _FakeTarget(this.jpeg);

  final Uint8List jpeg;
  final List<List<String>> commands = [];
  final List<String> properties = [];
  @override
  bool disposed = false;
  @override
  bool playing = true;
  @override
  bool hasVideo = true;
  bool writeFile = true;
  Completer<void>? hang;

  /// mpv's answers; r77: a grab waits for 'current-vo' (not empty, not
  /// "null") and a current frame ('video-frame-info/interlaced').
  final Map<String, String> props = {
    'hwdec-current': 'no',
    'current-vo': 'gpu',
    'video-codec': 'h264',
    'video-frame-info/interlaced': 'no',
  };

  @override
  Future<void> command(List<String> args) async {
    commands.add(List<String>.of(args));
    final Completer<void>? h = hang;
    if (h != null) {
      await h.future;
      return;
    }
    if (writeFile && args.first == 'screenshot-to-file') File(args[1]).writeAsBytesSync(jpeg);
  }

  @override
  Future<String> getProperty(String name) async {
    properties.add(name);
    return props[name] ?? '';
  }
}

Uint8List halves(int w, int h) {
  final img.Image image = img.Image(width: w, height: h);
  for (final img.Pixel p in image) {
    if (p.x < w ~/ 2) {
      p
        ..r = 255
        ..g = 0
        ..b = 0;
    } else {
      p
        ..r = 0
        ..g = 0
        ..b = 255;
    }
  }
  return img.encodeJpg(image, quality: 95);
}

BooruItem video(String id, {String host = 'gelbooru.com'}) => BooruItem(
  fileURL: 'https://img.$host/v/$id.mp4',
  sampleURL: 'https://img.$host/s/$id.jpg',
  thumbnailURL: 'https://img.$host/t/$id.jpg',
  tagsList: [Tag('solo')],
  postURL: 'https://$host/index.php?page=post&s=view&id=$id',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late VideoFrames frames;
  late _FakeTarget target;
  late List<String> looked;
  late List<Float32List> stored;
  late bool showing;
  late bool onScreen;
  late bool quiet;
  final Uint8List bigFrame = halves(1024, 512);

  Future<void> waitFor(bool Function() done, {Duration timeout = const Duration(seconds: 5)}) async {
    final Stopwatch sw = Stopwatch()..start();
    while (!done() && sw.elapsed < timeout) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  setUp(() {
    ModelWork.resetForTests();
    SettingsHandler.register();
    ViewerHandler.register();
    tempDir = Directory.systemTemp.createTempSync('video_frames');
    SettingsHandler.instance
      ..path = '${tempDir.path}${Platform.pathSeparator}'
      ..videoFrames = true
      ..altVideoPlayerVO = MpvVideoOutput.gpu;
    ViewerHandler.instance.current.value = null;
    target = _FakeTarget(bigFrame);
    looked = [];
    stored = [];
    showing = true;
    onScreen = true;
    quiet = true;
    VideoFrames.unregister();
    frames = VideoFrames.register()
      ..frameDirOverride = Directory('${tempDir.path}${Platform.pathSeparator}frames')
      ..firstDelay = const Duration(milliseconds: 30)
      ..gap = const Duration(milliseconds: 40)
      ..tick = const Duration(milliseconds: 10)
      ..requestTimeout = const Duration(milliseconds: 300)
      ..waitGap = const Duration(milliseconds: 20)
      ..maxFrames = 3
      ..lookWanted = (() => true)
      ..taggerWanted = (() => false)
      ..lookup = ((String url) {
        looked.add(url);
        return (target: target, stillShowing: () => showing);
      })
      ..lookOf = ((Uint8List jpeg) async {
        // One distinct vector per frame, in order: [1,0], [0,1], [1,1].
        final int n = stored.length;
        return Float32List.fromList(n == 0 ? [1, 0] : (n == 1 ? [0, 1] : [1, 1]));
      })
      ..storeLook = ((BooruItem item, Float32List v) async => stored.add(v))
      ..onScreen = (() => onScreen)
      ..quiet = (() => quiet);
    frames.attach();
  });

  tearDown(() {
    frames.detach();
    VideoFrames.unregister();
    ModelWork.resetForTests();
    ViewerHandler.instance.current.value = null;
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('shrinkJpeg: a large frame comes back at 512 px on its long side with its colours in place; a small one comes back untouched', () {
    final Uint8List out = VideoFrames.shrinkJpeg((bigFrame, 512))!;
    final img.Image decoded = img.decodeJpg(out)!;
    expect(decoded.width, 512);
    expect(decoded.height, 256);
    final img.Pixel left = decoded.getPixel(100, 128);
    final img.Pixel right = decoded.getPixel(400, 128);
    expect(left.r, greaterThan(200));
    expect(left.b, lessThan(60));
    expect(right.b, greaterThan(200));
    expect(right.r, lessThan(60));
    final Uint8List small = halves(300, 200);
    expect(identical(VideoFrames.shrinkJpeg((small, 512)), small), isTrue);
    expect(VideoFrames.shrinkJpeg((Uint8List.fromList([1, 2, 3]), 512)), isNull);
  });

  test('the decoder line names software decoding plainly', () {
    expect(VideoFrames.decoderLine('no', 'gpu', 'h264'), 'decoder no (software) · output gpu · codec h264');
    expect(VideoFrames.decoderLine('mediacodec', 'gpu', 'hevc'), 'decoder mediacodec · output gpu · codec hevc');
    expect(VideoFrames.decoderLine('', '', ''), 'decoder no (software) · output ? · codec ?');
  });

  test('a playing video: frames are asked of the player showing it, with the exact mpv command, at most maxFrames; the average is stored', () async {
    final BooruItem v = video('1');
    ViewerHandler.instance.current.value = v;
    await waitFor(() => target.commands.length >= 3 && stored.length >= 3);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(target.commands, hasLength(3), reason: 'maxFrames');
    for (final List<String> c in target.commands) {
      expect(c, hasLength(3));
      expect(c[0], 'screenshot-to-file');
      expect(c[1], endsWith('.jpg'));
      expect(c[1], startsWith(frames.frameDirOverride!.path));
      expect(c[2], 'video');
    }
    expect(looked.toSet(), {v.fileURL}, reason: 'only the player showing this video is asked');
    // r77: every grab first checks mpv's output and current frame; the
    // decoder line is read once per video, after the first check passes.
    const List<String> ready = ['current-vo', 'video-frame-info/interlaced'];
    expect(target.properties.sublist(0, 5), [...ready, 'hwdec-current', 'current-vo', 'video-codec'], reason: 'the decoder line, once per video');
    expect(target.properties.sublist(5), [...ready, ...ready], reason: 'grabs 2 and 3 only check readiness');
    final List<Uint8List> kept = frames.framesOf(v);
    expect(kept, hasLength(3));
    expect(img.decodeJpg(kept.first)!.width, 512, reason: 'kept shrunk');
    expect(stored, hasLength(3));
    expect(stored[0], [1, 0]);
    expect(stored[1][0], closeTo(0.7071, 1e-4));
    expect(stored[1][1], closeTo(0.7071, 1e-4));
    final Float32List mean = LookModelHandler.meanOf([Float32List.fromList([1, 0]), Float32List.fromList([0, 1]), Float32List.fromList([1, 1])]);
    expect(stored[2], mean);
    expect(frames.frameDirOverride!.listSync(), isEmpty, reason: 'the temporary files are deleted');
  });

  test('nothing is asked: switch off, a picture, a hidden post, a doujin item, nothing to read frames, the mediacodec_embed output', () async {
    SettingsHandler.instance.videoFrames = false;
    ViewerHandler.instance.current.value = video('2');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(target.commands, isEmpty);

    SettingsHandler.instance.videoFrames = true;
    ViewerHandler.instance.current.value = BooruItem(fileURL: 'https://img.gelbooru.com/p.jpg', sampleURL: '', thumbnailURL: '', tagsList: const [], postURL: 'https://gelbooru.com/p/3');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(target.commands, isEmpty, reason: 'a picture');

    ViewerHandler.instance.current.value = video('4')..hiddenInSource = true;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(target.commands, isEmpty, reason: 'your blacklist hides it');

    ViewerHandler.instance.current.value = video('5', host: 'nhentai.net');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(target.commands, isEmpty, reason: 'doujin');

    frames.lookWanted = () => false;
    frames.taggerWanted = () => false;
    ViewerHandler.instance.current.value = video('6');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(target.commands, isEmpty, reason: 'nothing would read the frames');

    frames.lookWanted = () => true;
    SettingsHandler.instance.altVideoPlayerVO = MpvVideoOutput.mediacodecEmbed;
    ViewerHandler.instance.current.value = video('7');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(target.commands, isEmpty, reason: 'mpv cannot read the picture back from mediacodec_embed');
  });

  test('a video left before the first delay is not asked; a paused video gets no second frame', () async {
    frames.firstDelay = const Duration(milliseconds: 120);
    ViewerHandler.instance.current.value = video('8');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    ViewerHandler.instance.current.value = null;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(target.commands, isEmpty);

    frames.firstDelay = const Duration(milliseconds: 20);
    final BooruItem v = video('9');
    ViewerHandler.instance.current.value = v;
    await waitFor(() => target.commands.isNotEmpty && frames.framesOf(v).isNotEmpty);
    target.playing = false;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(target.commands, hasLength(1), reason: 'paused: the same picture again would teach nothing');
  });

  test('a player that moved on, a file never written or a reply that never comes: nothing kept, the next tick may try again', () async {
    showing = false;
    final BooruItem a = video('10');
    ViewerHandler.instance.current.value = a;
    await waitFor(() => target.commands.isNotEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(frames.framesOf(a), isEmpty, reason: 'the pool moved the player to another video');

    showing = true;
    target.writeFile = false;
    final BooruItem b = video('11');
    ViewerHandler.instance.current.value = b;
    final int before = target.commands.length;
    await waitFor(() => target.commands.length > before);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(frames.framesOf(b), isEmpty, reason: 'mpv wrote no file');

    target.writeFile = true;
    target.hang = Completer<void>();
    final BooruItem c = video('12');
    ViewerHandler.instance.current.value = c;
    final int before2 = target.commands.length;
    await waitFor(() => target.commands.length > before2);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(frames.framesOf(c), isEmpty, reason: 'timed out');
    target.hang!.complete();
    target.hang = null;
    await waitFor(() => frames.framesOf(c).isNotEmpty);
    expect(frames.framesOf(c), isNotEmpty, reason: 'a later tick tries again');
  });

  test('frameNow: a fresh frame from the player when it shows the video, else the newest kept one, else nothing; nothing with the switch off', () async {
    final BooruItem v = video('13');
    final Uint8List? fresh = await frames.frameNow(v);
    expect(fresh, isNotNull);
    expect(img.decodeJpg(fresh!)!.width, 512);
    expect(target.commands.single.first, 'screenshot-to-file');

    frames.lookup = (String url) => null;
    final Uint8List? kept = await frames.frameNow(v);
    expect(kept, same(frames.framesOf(v).last));

    expect(await frames.frameNow(video('14')), isNull);
    SettingsHandler.instance.videoFrames = false;
    frames.lookup = (String url) => (target: target, stillShowing: () => true);
    expect(await frames.frameNow(v), isNull);
  });

  test('r77: no grab under another page, with the app away, or while the user touches or scrolls; the grab comes once all is clear', () async {
    onScreen = false;
    final BooruItem v = video('20');
    ViewerHandler.instance.current.value = v;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(target.commands, isEmpty, reason: 'a page, dialog or sheet covers the viewer, or the app is in the background');

    onScreen = true;
    quiet = false;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(target.commands, isEmpty, reason: 'a touch or scroll less than 1.5 s ago');

    quiet = true;
    await waitFor(() => target.commands.isNotEmpty);
    expect(target.commands.first.first, 'screenshot-to-file');
    // No further grabs, and let the ones in flight finish inside this test.
    onScreen = false;
    await waitFor(() => stored.length >= frames.framesOf(v).length && stored.isNotEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 150));
  });

  test('r77: the looks run of a frame is a background step - frameNow hands the frame over without waiting for it', () async {
    final Completer<void> slowLook = Completer<void>();
    frames.lookOf = (Uint8List jpeg) async {
      await slowLook.future;
      return Float32List.fromList([1, 0]);
    };
    final BooruItem v = video('21');
    final Stopwatch sw = Stopwatch()..start();
    final Uint8List? got = await frames.frameNow(v);
    expect(got, isNotNull);
    expect(sw.elapsedMilliseconds, lessThan(2000));
    expect(stored, isEmpty, reason: 'the looks model is still reading it');
    slowLook.complete();
    await waitFor(() => stored.isNotEmpty);
    expect(stored.single, Float32List.fromList([1, 0]));
  });

  test('r77: a post hidden by the blacklist after its frame was grabbed gets no looks vector', () async {
    final Completer<void> slowLook = Completer<void>();
    final BooruItem v = video('22');
    // The queue is busy with another step while the frame waits its turn.
    unawaited(ModelWork.instance.run('busy', (bool lite) => slowLook.future));
    expect(await frames.frameNow(v), isNotNull);
    v.hiddenInSource = true;
    slowLook.complete();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(stored, isEmpty);
  });

  test('r77: no grab until mpv has a picture output and a current frame; then exactly one command', () async {
    target.props['current-vo'] = '';
    final BooruItem v = video('30');
    ViewerHandler.instance.current.value = v;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(target.commands, isEmpty, reason: 'no picture output at all (the emulator case)');

    target.props['current-vo'] = 'null';
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(target.commands, isEmpty, reason: 'the placeholder output while the surface is attached');

    target.props['current-vo'] = 'gpu';
    target.props['video-frame-info/interlaced'] = '';
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(target.commands, isEmpty, reason: 'the output has not drawn a frame yet');

    target.props['video-frame-info/interlaced'] = 'no';
    await waitFor(() => target.commands.isNotEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(target.commands, hasLength(1));
    expect(target.commands.single, ['screenshot-to-file', target.commands.single[1], 'video']);
    onScreen = false;
    await waitFor(() => stored.isNotEmpty);
  });

  test('r77: "no file written" means not ready yet: tried again with a growing gap, never a failure, 5 times a visit, and a new visit tries again', () async {
    frames.maxFrames = 1;
    target.writeFile = false;
    final BooruItem v = video('31');
    ViewerHandler.instance.current.value = v;
    await waitFor(() => target.commands.length >= VideoFrames.maxNotReadyPerVisit, timeout: const Duration(seconds: 3));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(target.commands, hasLength(VideoFrames.maxNotReadyPerVisit), reason: 'past the failure limit (4): these were not failures; then this visit stops');
    expect(frames.framesOf(v), isEmpty);
    target.writeFile = true;
    ViewerHandler.instance.current.value = null;
    ViewerHandler.instance.current.value = v;
    await waitFor(() => frames.framesOf(v).isNotEmpty);
    expect(frames.framesOf(v), hasLength(1), reason: 'the next visit tried again');
    onScreen = false;
    await waitFor(() => stored.isNotEmpty);
  });

  test('r77: a video that never shows a picture is left alone after 10 answers across visits', () async {
    target.writeFile = false;
    final BooruItem v = video('33');
    for (int visit = 0; visit < 3; visit++) {
      ViewerHandler.instance.current.value = null;
      ViewerHandler.instance.current.value = v;
      await Future<void>.delayed(const Duration(milliseconds: 900));
    }
    expect(target.commands, hasLength(VideoFrames.maxNotReady), reason: 'two visits of 5, then nothing');
  });

  test('r77: checks for the picture stop after 30 in one visit', () async {
    target.props['current-vo'] = '';
    final BooruItem v = video('34');
    ViewerHandler.instance.current.value = v;
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final int reads = target.properties.where((p) => p == 'current-vo').length;
    expect(reads, VideoFrames.maxWaitsPerVisit);
    expect(target.commands, isEmpty);
  });

  test('r77: frameNow asks for no frame while the output has none; the kept frame answers instead', () async {
    final BooruItem v = video('32');
    final Uint8List? first = await frames.frameNow(v);
    expect(first, isNotNull);
    await waitFor(() => stored.isNotEmpty);
    final int before = target.commands.length;
    target.props['video-frame-info/interlaced'] = '';
    final Uint8List? again = await frames.frameNow(v);
    expect(target.commands.length, before, reason: 'no command while no frame is drawn');
    expect(again, same(frames.framesOf(v).last));
  });
}
