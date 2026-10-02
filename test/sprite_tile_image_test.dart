import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/doujin_cover_aspect_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/widgets/image/custom_network_image.dart';
import 'package:lolisnatcher/src/widgets/image/sprite_tile_image.dart';

/// r32: e-hentai serves page thumbnails as one sprite strip per block of 20
/// pages. A tile is the strip's URL with a media fragment, `#xywh=x,y,w,h`,
/// and [SpriteTileImage] paints just that rectangle, sharing one decode of
/// the strip between every tile cut from it.

/// A provider that counts how often its bytes were decoded, and can hold the
/// decode back until the test lets it through.
class _CountingImage extends ImageProvider<_CountingImage> {
  _CountingImage(this.bytes, {this.gate, this.failOnce = false});

  final Uint8List bytes;
  final Completer<void>? gate;

  /// The first load fails the way a dead strip link does; like
  /// CustomNetworkImage, the provider then evicts itself so a later request
  /// tries the network again.
  final bool failOnce;
  int loads = 0;

  @override
  Future<_CountingImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture<_CountingImage>(this);

  @override
  ImageStreamCompleter loadImage(_CountingImage key, ImageDecoderCallback decode) {
    loads++;
    if (failOnce && loads == 1) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      return MultiFrameImageStreamCompleter(codec: Future<ui.Codec>.error(StateError('the strip is gone')), scale: 1);
    }
    final Future<void> open = gate?.future ?? Future<void>.value();
    return MultiFrameImageStreamCompleter(
      codec: open.then((_) => ui.ImmutableBuffer.fromUint8List(bytes)).then(decode),
      scale: 1,
    );
  }
}

/// A 400×300 strip: the left half red, the right half blue.
Future<Uint8List> twoColourStrip() async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 200, 300), Paint()..color = const Color(0xFFFF0000));
  canvas.drawRect(const Rect.fromLTWH(200, 0, 200, 300), Paint()..color = const Color(0xFF0000FF));
  final ui.Image image = await recorder.endRecording().toImage(400, 300);
  final ByteData? png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return png!.buffer.asUint8List();
}

Future<ImageInfo> resolveOnce(ImageProvider provider) {
  final Completer<ImageInfo> done = Completer<ImageInfo>();
  final ImageStream stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (ImageInfo info, bool sync) {
      if (!done.isCompleted) done.complete(info);
      stream.removeListener(listener);
    },
    onError: (Object e, StackTrace? s) {
      if (!done.isCompleted) done.completeError(e, s ?? StackTrace.current);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return done.future;
}

/// RGBA of the pixel at (x, y).
Future<List<int>> pixelAt(ui.Image image, int x, int y) async {
  final ByteData raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final int offset = (y * image.width + x) * 4;
  return [for (int i = 0; i < 4; i++) raw.getUint8(offset + i)];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SettingsHandler.register();
    ViewerHandler.register();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    SpriteTileImage.resetForTests();
    BooruHandlerFactory.clearMediaHeaderCache();
  });

  group('SpriteTile', () {
    test('a media fragment names the strip and the rectangle; anything else is not a tile', () {
      final SpriteTile tile = SpriteTile.parse('https://h.hath.network/c2/k/1-0.webp#xywh=200,0,200,277')!;
      expect(tile.sheetUrl, 'https://h.hath.network/c2/k/1-0.webp');
      expect(tile.rect, const Rect.fromLTWH(200, 0, 200, 277));
      expect(tile.encode(), 'https://h.hath.network/c2/k/1-0.webp#xywh=200,0,200,277');
      expect(SpriteTile.parse('https://h/x.webp#xywh=pixel:0,0,100,141')!.rect, const Rect.fromLTWH(0, 0, 100, 141));
      expect(SpriteTile.parse('https://h/x.webp?v=2#xywh=0,0,1,1')!.sheetUrl, 'https://h/x.webp?v=2', reason: 'the query belongs to the strip');
      expect(SpriteTile.parse('https://h/x.webp'), isNull);
      expect(SpriteTile.parse('https://e-hentai.org/g/1/a/?p=1#page-21'), isNull, reason: "a placeholder's own fragment is not a tile");
      expect(SpriteTile.parse('https://h/x.webp#xywh=percent:0,0,50,50'), isNull);
      expect(SpriteTile.parse('https://h/x.webp#xywh=a,b,c,d'), isNull);
      expect(SpriteTile.parse('https://h/x.webp#xywh=0,0,200'), isNull);
      expect(SpriteTile.parse('https://h/x.webp#xywh=0,0,0,10'), isNull, reason: 'an empty rectangle');
      expect(SpriteTile.parse('https://h/x.webp#xywh=-1,0,10,10'), isNull);
      expect(SpriteTile.parse(''), isNull);
    });
  });

  group('SpriteTileImage', () {
    test('paints only its rectangle of the strip, at the declared size', () async {
      final _CountingImage strip = _CountingImage(await twoColourStrip());
      final ImageInfo right = await resolveOnce(SpriteTileImage(sheet: strip, rect: const Rect.fromLTWH(200, 0, 200, 277)));
      expect(right.image.width, 200);
      expect(right.image.height, 277);
      expect(await pixelAt(right.image, 0, 0), [0, 0, 255, 255], reason: 'the tile starts where the blue half starts');
      expect(await pixelAt(right.image, 199, 276), [0, 0, 255, 255]);
      final ImageInfo left = await resolveOnce(SpriteTileImage(sheet: strip, rect: const Rect.fromLTWH(0, 0, 200, 300)));
      expect(await pixelAt(left.image, 100, 150), [255, 0, 0, 255]);
      right.dispose();
      left.dispose();
    });

    test('a rectangle past the strip is clamped to it; one entirely outside is an error, not a crash', () async {
      final _CountingImage strip = _CountingImage(await twoColourStrip());
      final ImageInfo clamped = await resolveOnce(SpriteTileImage(sheet: strip, rect: const Rect.fromLTWH(300, 0, 200, 400)));
      expect(clamped.image.width, 100);
      expect(clamped.image.height, 300);
      clamped.dispose();
      await expectLater(
        resolveOnce(SpriteTileImage(sheet: strip, rect: const Rect.fromLTWH(400, 0, 200, 300))),
        throwsA(isA<Object>()),
      );
    });

    test('twenty tiles cut from one strip decode the strip once', () async {
      final _CountingImage strip = _CountingImage(await twoColourStrip());
      final List<ImageInfo> tiles = await Future.wait([
        for (int i = 0; i < 20; i++) resolveOnce(SpriteTileImage(sheet: strip, rect: Rect.fromLTWH(i * 20.0, 0, 20, 300))),
      ]);
      expect(strip.loads, 1);
      expect(tiles.map((t) => t.image.width).toSet(), {20});
      for (final ImageInfo t in tiles) {
        t.dispose();
      }
    });

    test('equal strip and rectangle mean the same cache entry; a different rectangle does not', () {
      final MemoryImage a = MemoryImage(Uint8List.fromList(const [1, 2, 3]));
      final MemoryImage b = MemoryImage(Uint8List.fromList(const [1, 2, 3]));
      const Rect r = Rect.fromLTWH(0, 0, 1, 1);
      expect(SpriteTileImage(sheet: a, rect: r), SpriteTileImage(sheet: a, rect: r));
      expect(SpriteTileImage(sheet: a, rect: r).hashCode, SpriteTileImage(sheet: a, rect: r).hashCode);
      expect(SpriteTileImage(sheet: a, rect: r), isNot(SpriteTileImage(sheet: a, rect: const Rect.fromLTWH(1, 0, 1, 1))));
      expect(SpriteTileImage(sheet: a, rect: r), isNot(SpriteTileImage(sheet: b, rect: r)), reason: 'MemoryImage compares its bytes by identity');
    });

    test('ResizeImage over a tile leaves the tile as it is: it never resizes the strip, and never resizes the tile either', () async {
      final _CountingImage strip = _CountingImage(await twoColourStrip());
      final ImageInfo info = await resolveOnce(
        ResizeImage(
          SpriteTileImage(sheet: strip, rect: const Rect.fromLTWH(200, 0, 200, 300)),
          width: 100,
          policy: ResizeImagePolicy.fit,
          allowUpscaling: false,
        ),
      );
      // ResizeImage works through the decode callback, which a crop does not
      // use — so the thumbnail widget's resize (and its 10 px pixelation of
      // hidden items) is a no-op for tiles. A 200 px tile is smaller than
      // any cell, so nothing is lost; this pins the fact.
      expect(info.image.width, 200);
      expect(await pixelAt(info.image, 0, 0), [0, 0, 255, 255]);
      info.dispose();
    });

    test('a tile whose strip failed is not sticky: the next request tries the strip again', () async {
      final _CountingImage strip = _CountingImage(await twoColourStrip(), failOnce: true);
      final SpriteTileImage tile = SpriteTileImage(sheet: strip, rect: const Rect.fromLTWH(0, 0, 20, 20));
      await expectLater(resolveOnce(tile), throwsA(isA<StateError>()));
      // The tile evicts its own cache entry on failure (a microtask away),
      // the way CustomNetworkImage does — otherwise a filmstrip cell that
      // resolves the same key would replay the error for the rest of the session.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final ImageInfo info = await resolveOnce(tile);
      expect(strip.loads, 2, reason: 'the second request went back to the strip');
      expect(info.image.width, 20);
      info.dispose();
    });

    test('a tile disposed before its strip arrives stays quiet when the strip does', () async {
      final Completer<void> gate = Completer<void>();
      final _CountingImage strip = _CountingImage(await twoColourStrip(), gate: gate);
      // The completer itself, outside the image cache (whose keep-alive
      // handle is only released after a frame): one listener comes and goes,
      // which is exactly what a tile scrolled off the grid does.
      final SpriteTileCompleter completer = SpriteTileCompleter(strip, const Rect.fromLTWH(0, 0, 10, 10));
      final ImageStreamListener listener = ImageStreamListener((_, _) {});
      completer.addListener(listener);
      expect(completer.disposed, isFalse);
      completer.removeListener(listener);
      expect(completer.disposed, isTrue, reason: 'nothing holds the tile any more');
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(strip.loads, 1, reason: 'the strip was asked for once; a disposed tile must not throw when it lands');
    });

    test('the cover-aspect table ignores tiles: two thousand of them would evict every card', () {
      final DoujinCoverAspects aspects = DoujinCoverAspects.instance;
      aspects.resetForTests();
      aspects.record('https://h/strip.webp#xywh=0,0,200,277', 200, 277);
      expect(aspects.aspectFor('https://h/strip.webp#xywh=0,0,200,277'), isNull);
      aspects.record('https://ehgt.org/cover.webp', 250, 342);
      expect(aspects.aspectFor('https://ehgt.org/cover.webp'), closeTo(250 / 342, 0.001));
      aspects.resetForTests();
    });

    test('the strip provider for a source is shared by every tile: one headers map, one cache key', () {
      final Booru eh = Booru('eh', BooruType.EHentai, '', 'https://e-hentai.org', '');
      final Map<String, String> headers = SpriteTileImage.sheetHeadersFor(eh);
      expect(identical(headers, SpriteTileImage.sheetHeadersFor(eh)), isTrue, reason: 'CustomNetworkImage compares headers by identity');
      expect(headers['Referer'], 'https://e-hentai.org/');
      expect(headers['User-Agent'], isNotEmpty);
      expect(headers.containsKey('Cookie'), isFalse, reason: 'a hath node must never see the session');
      final SpriteTile tile = SpriteTile.parse('https://h.hath.network/c2/k/1-0.webp#xywh=200,0,200,277')!;
      final SpriteTileImage a = SpriteTileImage.network(tile, booru: eh, withCache: true);
      final SpriteTileImage b = SpriteTileImage.network(tile, booru: eh, withCache: true);
      expect(a, b);
      expect(a.sheet, isA<CustomNetworkImage>());
      final CustomNetworkImage sheet = a.sheet as CustomNetworkImage;
      expect(sheet.url, 'https://h.hath.network/c2/k/1-0.webp');
      expect(sheet.fileNameExtras, '', reason: 'one cache file per strip, not one per page');
      expect(sheet.cacheFolder, 'thumbnails');
      expect(sheet.withCaptchaCheck, isFalse);
      final SpriteTileImage next = SpriteTileImage.network(SpriteTile.parse('https://h.hath.network/c2/k/1-0.webp#xywh=0,0,200,273')!, booru: eh, withCache: true);
      expect(next.sheet, sheet, reason: 'the next tile of the strip resolves the same cache entry');
    });
  });
}
