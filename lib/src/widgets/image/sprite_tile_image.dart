import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/image/custom_network_image.dart';

/// One rectangle of a sprite strip, written as a URL with a W3C media
/// fragment: `https://host/strip.webp#xywh=x,y,w,h` (pixel units).
///
/// e-hentai serves a gallery's page thumbnails this way — one strip per block
/// of twenty pages, the tiles side by side — and a tile has no URL of its
/// own. The fragment never reaches the server (`HttpClient` strips it), so
/// the strip is fetched and cached once and every tile is cut from that one
/// decode by [SpriteTileImage].
@immutable
class SpriteTile {
  const SpriteTile(this.sheetUrl, this.rect);

  /// The strip, without the fragment.
  final String sheetUrl;

  /// The tile's rectangle inside the strip, in pixels.
  final Rect rect;

  static final RegExp _fragment = RegExp(r'^xywh=(?:pixel:)?(\d+),(\d+),(\d+),(\d+)$');

  /// The tile a URL names, or null for a URL that is just an image: a plain
  /// thumbnail, a placeholder with its own `#page-N` fragment, anything else.
  static SpriteTile? parse(String url) {
    final int hash = url.indexOf('#');
    if (hash < 0) return null;
    final RegExpMatch? m = _fragment.firstMatch(url.substring(hash + 1));
    if (m == null) return null;
    final int w = int.parse(m.group(3)!);
    final int h = int.parse(m.group(4)!);
    if (w <= 0 || h <= 0) return null;
    return SpriteTile(
      url.substring(0, hash),
      Rect.fromLTWH(int.parse(m.group(1)!).toDouble(), int.parse(m.group(2)!).toDouble(), w.toDouble(), h.toDouble()),
    );
  }

  String encode() => '$sheetUrl#xywh=${rect.left.round()},${rect.top.round()},${rect.width.round()},${rect.height.round()}';

  @override
  bool operator ==(Object other) => other is SpriteTile && other.sheetUrl == sheetUrl && other.rect == rect;

  @override
  int get hashCode => Object.hash(sheetUrl, rect);

  @override
  String toString() => encode();
}

/// An image that is one rectangle of another image.
///
/// The strip is resolved through the ordinary [ImageStream], so Flutter's
/// image cache holds one decode of it however many tiles are cut from it;
/// each tile is then a small image of its own that the rest of the app (the
/// thumbnail widget, `ResizeImage`, the cover-aspect table) treats like any
/// other.
@immutable
class SpriteTileImage extends ImageProvider<SpriteTileImage> {
  const SpriteTileImage({required this.sheet, required this.rect});

  /// The tile [tile] names, fetched with the source's media headers.
  ///
  /// [sheetHeadersFor] hands out one map instance per source and the
  /// timeouts are fixed, so the strip's cache key is the same for every
  /// tile — the pages grid and the reader's filmstrip alike — and the strip
  /// is decoded once. On disk it is cached once too (`fileNameExtras`
  /// empty), under `thumbnails`.
  factory SpriteTileImage.network(SpriteTile tile, {required Booru? booru, required bool withCache}) => SpriteTileImage(
    sheet: CustomNetworkImage(
      tile.sheetUrl,
      headers: sheetHeadersFor(booru),
      withCache: withCache,
      cacheFolder: 'thumbnails',
      sendTimeout: sheetTimeout,
      receiveTimeout: sheetTimeout,
    ),
    rect: tile.rect,
  );

  /// The strip provider. Every tile of one strip must hold an EQUAL provider
  /// (same URL, same headers instance, same cache settings) or the cache
  /// decodes the strip once per tile; [SpriteTileImage.network] guarantees
  /// it.
  final ImageProvider sheet;

  /// The rectangle of [sheet] this image is, in the strip's pixels.
  final Rect rect;

  static const Duration sheetTimeout = Duration(seconds: 20);

  static final Map<String, Map<String, String>> _headersBySource = {};

  /// The headers a strip request carries for [booru]: the browser agent and
  /// whatever the source's own handler says its media host needs (e-hentai:
  /// a Referer, never a cookie). One instance per source, because
  /// [CustomNetworkImage] compares headers by identity.
  static Map<String, String> sheetHeadersFor(Booru? booru) {
    final String key = '${booru?.type?.name ?? '?'}|${booru?.baseURL ?? ''}';
    return _headersBySource.putIfAbsent(
      key,
      () => <String, String>{
        'User-Agent': Tools.browserUserAgent,
        if (booru != null) ...BooruHandlerFactory.mediaHeadersFor(booru),
      },
    );
  }

  @visibleForTesting
  static void resetForTests() => _headersBySource.clear();

  /// Deletes the strip's cache file, so a corrupt one is fetched again.
  Future<void> deleteCacheFile() async {
    final ImageProvider strip = sheet;
    if (strip is CustomNetworkImage) await strip.deleteCacheFile();
  }

  @override
  Future<SpriteTileImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture<SpriteTileImage>(this);

  @override
  ImageStreamCompleter loadImage(SpriteTileImage key, ImageDecoderCallback decode) => SpriteTileCompleter(
    sheet,
    rect,
    // A failed tile must not stay in the cache with its error: the cache's own
    // pending listener has no error path, so a later request for the same key
    // (a filmstrip cell, a grid tile scrolled back) would replay the failure
    // for the rest of the session. Evict, as CustomNetworkImage does.
    onFailed: () => scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key)),
  );

  @override
  bool operator ==(Object other) => other is SpriteTileImage && other.sheet == sheet && other.rect == rect;

  @override
  int get hashCode => Object.hash(sheet, rect);

  @override
  String toString() => 'SpriteTileImage($sheet, $rect)';
}

/// Cuts [rect] out of the strip once the strip has decoded.
///
/// Not a [OneFrameImageStreamCompleter]: that one calls `setImage` whenever
/// its future completes, and a completer disposed in the meantime — a tile
/// scrolled away before its strip landed — throws a StateError. This one
/// stops listening to the strip when disposed and drops a late crop.
class SpriteTileCompleter extends ImageStreamCompleter {
  SpriteTileCompleter(ImageProvider sheet, this.rect, {this.onFailed}) {
    _listener = ImageStreamListener(_onSheet, onError: _onSheetError);
    _stream = sheet.resolve(ImageConfiguration.empty);
    _stream.addListener(_listener);
  }

  final Rect rect;

  /// Called once when the tile cannot be produced (the strip failed to load,
  /// or does not contain the rectangle), before the error is reported.
  final VoidCallback? onFailed;

  late final ImageStream _stream;
  late final ImageStreamListener _listener;
  bool _disposed = false;
  bool _listening = true;

  @visibleForTesting
  bool get disposed => _disposed;

  void _stopListening() {
    if (!_listening) return;
    _listening = false;
    _stream.removeListener(_listener);
  }

  void _onSheet(ImageInfo info, bool synchronousCall) {
    _stopListening();
    unawaited(_crop(info));
  }

  Future<void> _crop(ImageInfo info) async {
    try {
      final ui.Image cropped = await cropImage(info.image, rect);
      if (_disposed) {
        cropped.dispose();
        return;
      }
      setImage(ImageInfo(image: cropped, scale: info.scale, debugLabel: info.debugLabel));
    } catch (e, s) {
      if (!_disposed) {
        onFailed?.call();
        reportError(context: ErrorDescription('while cutting a tile from its strip'), exception: e, stack: s, silent: true);
      }
    } finally {
      // The strip stream handed this listener its own clone.
      info.dispose();
    }
  }

  void _onSheetError(Object e, StackTrace? s) {
    _stopListening();
    if (!_disposed) {
      onFailed?.call();
      reportError(context: ErrorDescription('while loading a strip of thumbnails'), exception: e, stack: s, silent: true);
    }
  }

  @override
  void onDisposed() {
    _disposed = true;
    _stopListening();
    super.onDisposed();
  }

  /// [rect] out of [image], clamped to its bounds; no overlap is an error.
  static Future<ui.Image> cropImage(ui.Image image, Rect rect) async {
    final Rect bounds = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final Rect src = rect.intersect(bounds);
    if (src.isEmpty || src.width < 1 || src.height < 1) {
      throw StateError('tile $rect lies outside the ${image.width}x${image.height} strip');
    }
    final int w = src.width.round();
    final int h = src.height.round();
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    // A 1:1 copy: exact texels, or the sampler blends half a pixel of the
    // neighbouring tile into this one's edge. Scaling happens in the widget.
    canvas.drawImageRect(
      image,
      src,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..filterQuality = FilterQuality.none,
    );
    final ui.Picture picture = recorder.endRecording();
    try {
      return await picture.toImage(w, h);
    } finally {
      picture.dispose();
    }
  }
}
