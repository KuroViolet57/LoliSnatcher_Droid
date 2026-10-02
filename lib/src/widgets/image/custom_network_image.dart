// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'package:dio/dio.dart';
import 'package:flutter_avif/flutter_avif.dart';

import 'package:lolisnatcher/src/services/image_writer.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/image/abstract_custom_network_image.dart' as custom_network_image;

/// How far back from the end of a JPEG to look for its EOI marker.
///
/// A truncated JPEG has no EOI anywhere, so any window comfortably larger than
/// a plausible trailer distinguishes the two cases. 8KB covers signatures,
/// appended thumbnails and stray metadata without reading a whole file back.
const int jpegTailWindow = 8 * 1024;

/// Whether a JPEG's tail contains the EOI marker `FF D9`.
///
/// It looks for the LAST EOI rather than requiring the file to end on one.
/// Trailing bytes after EOI are legal JPEG and hosts do use them: every image
/// on erocdn ends `FF D9 53 4E` — EOI followed by a two-byte "SN" signature.
/// The previous check read the final two bytes and demanded they be `FF D9`,
/// which is false for every one of those files, so it rejected 2,141 perfectly
/// decodable images as "truncated" and took the reader's first page with them.
///
/// This is deliberately not special-cased to one host; the bytes are valid
/// JPEG and any CDN is free to append to them.
/// Whether the bytes start with the JPEG SOI marker `FF D8`. The end-marker
/// check is only meaningful for a real JPEG: pawchive's thumbnail service
/// serves WebP under `.jpeg` URLs and `image/jpeg`, which has no EOI at all
/// and decodes fine.
bool looksLikeJpeg(List<int> head) => head.length >= 2 && head[0] == 0xFF && head[1] == 0xD8;

bool hasJpegEndMarker(List<int> tail) {
  for (int i = tail.length - 2; i >= 0; i--) {
    if (tail[i] == 0xFF && tail[i + 1] == 0xD9) return true;
  }
  return false;
}

/// Shared logic for downloading, caching, and atomic writing of images.
mixin _NetworkImageLoaderMixin {
  Future<void> _commitCacheFile(File tempFile, String destPath) async {
    final dest = File(destPath);
    try {
      await tempFile.rename(destPath);
      return;
    } catch (_) {}

    if (await dest.exists()) {
      try {
        final len = await dest.length();
        if (len > 0) {
          try {
            await tempFile.delete();
          } catch (_) {}
          return;
        }
        await dest.delete();
      } catch (e) {
        try {
          await tempFile.delete();
        } catch (_) {}
        return;
      }
    }
    for (int i = 0; i < 3; i++) {
      try {
        await tempFile.rename(destPath);
        return;
      } catch (_) {
        await Future.delayed(Duration(milliseconds: 50 * (i + 1)));
      }
    }

    if (await dest.exists()) {
      try {
        await tempFile.delete();
      } catch (_) {}
      return;
    }

    throw FileSystemException('Failed to commit cache file after retries', destPath);
  }

  Future<Uint8List> downloadAndCache({
    required String url,
    required String? cacheFolder,
    required String fileNameExtras,
    required bool withCache,
    required Map<String, String>? headers,
    required Duration? sendTimeout,
    required Duration? receiveTimeout,
    required CancelToken? cancelToken,
    required bool withCaptchaCheck,
    required StreamController<ImageChunkEvent> chunkEvents,
    required void Function(bool)? onCacheDetected,
    List<String> fallbackUrls = const [],
  }) async {
    final Uri resolved = Uri.base.resolve(url);
    final String cacheFilePath = await ImageWriter().getCachePathString(
      resolved.toString(),
      cacheFolder ?? 'media',
      clearName: cacheFolder != 'favicons',
      fileNameExtras: fileNameExtras,
    );

    final String tempFilePath = '$cacheFilePath.temp_${DateTime.now().microsecondsSinceEpoch}';

    File? cacheFile;

    // Check existing cache
    if (withCache) {
      cacheFile = File(cacheFilePath);
      if (await cacheFile.exists()) {
        final int fileSize = await cacheFile.length();
        if (fileSize < 10) {
          try {
            await cacheFile.delete();
          } catch (_) {}
          cacheFile = null;
        } else {
          chunkEvents.add(
            ImageChunkEvent(
              cumulativeBytesLoaded: fileSize,
              expectedTotalBytes: fileSize,
            ),
          );
        }
      } else {
        cacheFile = null;
      }
    }

    if (onCacheDetected != null) {
      onCacheDetected(cacheFile != null);
    }

    if (cacheFile != null) {
      try {
        return await cacheFile.readAsBytes();
      } catch (e) {
        cacheFile = null;
      }
    }

    // --- Download Logic ---
    final client = DioNetwork.getClient(skipLogging: true);
    if (withCaptchaCheck) {
      DioNetwork.captchaInterceptor(
        client,
        customUserAgent: Tools.appUserAgent,
      );
    }

    // Mirrors to try if the first URL fails.
    //
    // Some sources publish a spare CDN alongside the primary for exactly this
    // reason — niyaniya's API returns a `fallback` host with every thumbnail
    // because its main mirrors intermittently drop requests. The loader used to
    // give up on the first error, so that spare was carried all the way into
    // the item and then never used, and a flaky mirror read as a broken source.
    final List<Uri> candidates = [
      resolved,
      for (final fallback in fallbackUrls)
        if (fallback.isNotEmpty && fallback != url) Uri.base.resolve(fallback),
    ];

    Future<Response<dynamic>> attempt(Uri uri) {
      void onReceiveProgress(int count, int total) {
        chunkEvents.add(
          ImageChunkEvent(
            cumulativeBytesLoaded: count,
            expectedTotalBytes: total <= 0 ? null : total,
          ),
        );
      }

      final bool noRedirects = headers?.containsKey('LS-IGNORE-REDIRECT') == true;
      return withCache
          ? client.downloadUri(
              uri,
              tempFilePath,
              options: Options(
                headers: headers,
                sendTimeout: sendTimeout,
                receiveTimeout: receiveTimeout,
                followRedirects: !noRedirects,
              ),
              onReceiveProgress: onReceiveProgress,
              cancelToken: cancelToken,
            )
          : client.getUri(
              uri,
              options: Options(
                headers: headers,
                responseType: ResponseType.bytes,
                sendTimeout: sendTimeout,
                receiveTimeout: receiveTimeout,
                followRedirects: !noRedirects,
              ),
              onReceiveProgress: onReceiveProgress,
              cancelToken: cancelToken,
            );
    }

    Response? response;
    Exception? lastError;
    for (final Uri candidate in candidates) {
      try {
        final Response<dynamic> attempted = await attempt(candidate);
        if (Tools.isGoodResponse(attempted)) {
          response = attempted;
          break;
        }
        lastError = NetworkImageLoadException(
          statusCode: attempted.statusCode ?? 0,
          uri: candidate,
        );
      } catch (e) {
        // A cancelled request is the caller's decision, not a mirror failing;
        // trying the next one would defeat the cancellation.
        if (e is DioException && CancelToken.isCancel(e)) {
          try {
            await File(tempFilePath).delete();
          } catch (_) {}
          rethrow;
        }
        lastError = e is Exception ? e : Exception(e.toString());
      }
      // Each attempt writes to the same temp path, so clear it before the next.
      try {
        await File(tempFilePath).delete();
      } catch (_) {}
    }

    if (response == null) {
      try {
        await File(tempFilePath).delete();
      } catch (_) {}
      throw lastError ?? NetworkImageLoadException(statusCode: 0, uri: resolved);
    }
    // Every candidate above is checked with isGoodResponse before being
    // accepted, so reaching here means a good response.
    // NOTE: do NOT close `client` — it now shares the app-wide pooled
    // HttpClient (see DioNetwork.getClient); closing would drop every other
    // request's warm connections.

    if (withCache) {
      final tempFile = File(tempFilePath);
      if (await tempFile.exists()) {
        final actualLen = await tempFile.length();

        // Validate Content-Length
        final headerLen = int.tryParse(response.headers.value(HttpHeaders.contentLengthHeader) ?? '');
        if (headerLen != null && headerLen > 0 && actualLen != headerLen) {
          try {
            await tempFile.delete();
          } catch (_) {}
          throw Exception('Download incomplete: Expected $headerLen bytes, got $actualLen');
        }

        // Validate JPEG EOI (End of Image)
        if (actualLen > 2 && (url.toLowerCase().endsWith('.jpg') || url.toLowerCase().endsWith('.jpeg'))) {
          final handle = await tempFile.open();
          try {
            final headBytes = await handle.read(2);
            final int window = actualLen < jpegTailWindow ? actualLen : jpegTailWindow;
            await handle.setPosition(actualLen - window);
            final endBytes = await handle.read(window);
            if (looksLikeJpeg(headBytes) && !hasJpegEndMarker(endBytes)) {
              throw Exception('Image file is truncated (missing JPEG EOI marker)');
            }
          } catch (e) {
            try {
              await tempFile.delete();
            } catch (_) {}
            rethrow;
          } finally {
            await handle.close();
          }
        }

        try {
          await _commitCacheFile(tempFile, cacheFilePath);
          return File(cacheFilePath).readAsBytes();
        } catch (_) {
          try {
            await tempFile.delete();
          } catch (_) {}
          rethrow;
        }
      }
    }

    return response.data as Uint8List;
  }

  Future<Uint8List> tryFixGifSpeed(String url, Uint8List image) async {
    if (!url.toLowerCase().endsWith('.gif') && !url.toLowerCase().contains('.gif')) {
      return image;
    }

    try {
      final int len = image.length - 6;
      for (int i = 0; i < len; i++) {
        if (image[i] == 0x21 && image[i + 1] == 0xF9 && image[i + 2] == 0x04) {
          final int delay = image[i + 4] | (image[i + 5] << 8);
          if (delay < 10) {
            image[i + 4] = 0x0A;
          }
          i += 5;
        }
      }
    } catch (_) {}
    return image;
  }

  Future<void> deleteCache(String url, String? cacheFolder, String fileNameExtras) async {
    final Uri resolved = Uri.base.resolve(url);
    final String cacheFilePath = await ImageWriter().getCachePathString(
      resolved.toString(),
      cacheFolder ?? 'media',
      clearName: cacheFolder != 'favicons',
      fileNameExtras: fileNameExtras,
    );
    final File cacheFile = File(cacheFilePath);
    try {
      if (await cacheFile.exists()) {
        await cacheFile.delete();
      }
      // Note: We can't easily delete unique temp files here as their names are random.
      // But they are cleaned up in the try/catch blocks of downloadAndCache.
      // We can try deleting the legacy fixed temp file just in case.
      final legacyTemp = File('$cacheFilePath.temp');
      if (await legacyTemp.exists()) {
        await legacyTemp.delete();
      }
    } catch (e) {
      print('NetworkImage Exception :: delete cache file :: $e');
    }
  }
}

@immutable
class CustomNetworkImage extends ImageProvider<custom_network_image.CustomNetworkImage>
    with _NetworkImageLoaderMixin
    implements custom_network_image.CustomNetworkImage {
  const CustomNetworkImage(
    this.url, {
    this.scale = 1.0,
    this.headers,
    this.cancelToken,
    this.withCache = false,
    this.cacheFolder,
    this.fileNameExtras = '',
    this.onCacheDetected,
    this.onError,
    this.sendTimeout,
    this.receiveTimeout,
    this.withCaptchaCheck = false,
    this.fallbackUrls = const [],
  }) : assert(!withCache || cacheFolder != null, 'cacheFolder must be set when withCache is true');

  @override
  final String url;
  @override
  final double scale;
  @override
  final Map<String, String>? headers;
  final CancelToken? cancelToken;
  final bool withCache;
  final String? cacheFolder;
  final String fileNameExtras;
  final void Function(bool)? onCacheDetected;
  final void Function(Object)? onError;
  final Duration? sendTimeout;
  final Duration? receiveTimeout;

  /// Spare mirrors for [url], tried in order if it fails. Sources that publish
  /// a backup CDN (niyaniya returns one with every thumbnail) put it here.
  final List<String> fallbackUrls;
  final bool withCaptchaCheck;

  @override
  Future<CustomNetworkImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<CustomNetworkImage>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    custom_network_image.CustomNetworkImage key,
    ImageDecoderCallback decode,
  ) {
    final StreamController<ImageChunkEvent> chunkEvents = StreamController<ImageChunkEvent>();

    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key as CustomNetworkImage, chunkEvents, decode),
      chunkEvents: chunkEvents.stream,
      scale: key.scale,
      debugLabel: key.url,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<custom_network_image.CustomNetworkImage>('Image key', key),
      ],
    );
  }

  Future<bool> deleteCacheFile() async {
    await deleteCache(url, cacheFolder, fileNameExtras);
    return true;
  }

  Future<ui.Codec> _loadAsync(
    CustomNetworkImage key,
    StreamController<ImageChunkEvent> chunkEvents,
    ImageDecoderCallback decode,
  ) async {
    try {
      assert(key == this, 'The $runtimeType cannot be reused after disposing.');

      final Uint8List bytes = await downloadAndCache(
        url: key.url,
        cacheFolder: cacheFolder,
        fileNameExtras: fileNameExtras,
        withCache: withCache,
        headers: headers,
        sendTimeout: sendTimeout,
        receiveTimeout: receiveTimeout,
        cancelToken: cancelToken,
        withCaptchaCheck: withCaptchaCheck,
        chunkEvents: chunkEvents,
        onCacheDetected: onCacheDetected,
        fallbackUrls: fallbackUrls,
      );

      if (bytes.isEmpty) {
        await deleteCacheFile();
        throw Exception('CustomNetworkImage is an empty file: ${key.url}');
      }

      final fixedBytes = await tryFixGifSpeed(key.url, bytes);

      final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(fixedBytes);
      return decode(buffer);
    } catch (e) {
      if (onError != null) {
        onError?.call(e);
      }
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(key);
      });
      rethrow;
    } finally {
      await chunkEvents.close();
    }
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is CustomNetworkImage &&
        other.url == url &&
        other.scale == scale &&
        other.headers == headers &&
        other.withCache == withCache &&
        other.cacheFolder == cacheFolder &&
        other.fileNameExtras == fileNameExtras &&
        other.sendTimeout == sendTimeout &&
        other.receiveTimeout == receiveTimeout &&
        other.withCaptchaCheck == withCaptchaCheck;
  }

  @override
  int get hashCode => Object.hash(
    url,
    scale,
    headers,
    withCache,
    cacheFolder,
    fileNameExtras,
    sendTimeout,
    receiveTimeout,
    withCaptchaCheck,
  );

  @override
  String toString() => '${objectRuntimeType(this, 'CustomNetworkImage')}("$url", scale: $scale)';
}

@immutable
class CustomNetworkAvifImage extends ImageProvider<custom_network_image.CustomNetworkImage>
    with _NetworkImageLoaderMixin
    implements custom_network_image.CustomNetworkImage {
  const CustomNetworkAvifImage(
    this.url, {
    this.scale = 1.0,
    this.headers,
    this.cancelToken,
    this.withCache = false,
    this.cacheFolder,
    this.fileNameExtras = '',
    this.onCacheDetected,
    this.onError,
    this.sendTimeout,
    this.receiveTimeout,
    this.withCaptchaCheck = false,
    this.fallbackUrls = const [],
  }) : assert(!withCache || cacheFolder != null, 'cacheFolder must be set when withCache is true');

  @override
  final String url;
  @override
  final double scale;
  @override
  final Map<String, String>? headers;
  final CancelToken? cancelToken;
  final bool withCache;
  final String? cacheFolder;
  final String fileNameExtras;
  final void Function(bool)? onCacheDetected;
  final void Function(Object)? onError;
  final Duration? sendTimeout;
  final Duration? receiveTimeout;

  /// Spare mirrors for [url], tried in order if it fails. Sources that publish
  /// a backup CDN (niyaniya returns one with every thumbnail) put it here.
  final List<String> fallbackUrls;
  final bool withCaptchaCheck;

  @override
  Future<CustomNetworkAvifImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<CustomNetworkAvifImage>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    custom_network_image.CustomNetworkImage key,
    ImageDecoderCallback decode,
  ) {
    final StreamController<ImageChunkEvent> chunkEvents = StreamController<ImageChunkEvent>();

    return AvifImageStreamCompleter(
      key: key,
      codec: _loadAsync(key as CustomNetworkAvifImage, chunkEvents, decode),
      scale: key.scale,
      debugLabel: key.url,
      informationCollector: () => <DiagnosticsNode>[
        ErrorDescription('Url: $url'),
      ],
      chunkEvents: chunkEvents.stream,
    );
  }

  Future<bool> deleteCacheFile() async {
    await deleteCache(url, cacheFolder, fileNameExtras);
    return true;
  }

  Future<AvifCodec> _loadAsync(
    CustomNetworkAvifImage key,
    StreamController<ImageChunkEvent> chunkEvents,
    ImageDecoderCallback decode,
  ) async {
    try {
      assert(key == this, 'The $runtimeType cannot be reused after disposing.');

      final Uint8List bytes = await downloadAndCache(
        url: key.url,
        cacheFolder: cacheFolder,
        fileNameExtras: fileNameExtras,
        withCache: withCache,
        headers: headers,
        sendTimeout: sendTimeout,
        receiveTimeout: receiveTimeout,
        cancelToken: cancelToken,
        withCaptchaCheck: withCaptchaCheck,
        chunkEvents: chunkEvents,
        onCacheDetected: onCacheDetected,
        fallbackUrls: fallbackUrls,
      );

      if (bytes.isEmpty) {
        await deleteCacheFile();
        throw Exception('CustomNetworkAvifImage is an empty file: ${key.url}');
      }

      final fType = isAvifFile(bytes.sublist(0, 16));
      if (fType == AvifFileType.unknown) {
        throw Exception('CustomNetworkAvifImage is not an avif file: ${key.url}');
      }

      final codec = fType == AvifFileType.avif
          ? SingleFrameAvifCodec(bytes: bytes)
          : MultiFrameAvifCodec(
              key: hashCode,
              avifBytes: bytes,
              overrideDurationMs: -1,
            );
      await codec.ready();
      return codec;
    } catch (e) {
      if (onError != null) {
        onError?.call(e);
      }
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(key);
      });
      rethrow;
    } finally {
      await chunkEvents.close();
    }
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is CustomNetworkAvifImage &&
        other.url == url &&
        other.scale == scale &&
        other.headers == headers &&
        other.withCache == withCache &&
        other.cacheFolder == cacheFolder &&
        other.fileNameExtras == fileNameExtras &&
        other.sendTimeout == sendTimeout &&
        other.receiveTimeout == receiveTimeout &&
        other.withCaptchaCheck == withCaptchaCheck;
  }

  @override
  int get hashCode => Object.hash(
    url,
    scale,
    headers,
    withCache,
    cacheFolder,
    fileNameExtras,
    sendTimeout,
    receiveTimeout,
    withCaptchaCheck,
  );

  @override
  String toString() => '${objectRuntimeType(this, 'CustomNetworkAvifImage')}("$url", scale: $scale)';
}
