import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'package:lolisnatcher/src/handlers/service_handler.dart';

/// True for the URL forms a downloaded page is addressed by: a `file://` URL
/// or absolute path (plain storage), or a `content://` document (SAF).
bool isLocalMediaUrl(String url) =>
    url.startsWith('file://') || url.startsWith('content://') || url.startsWith('/');

/// The provider for a local page, or null when [url] is a network URL.
ImageProvider? localImageProviderFor(String url) {
  if (url.startsWith('file://')) return FileImage(File(Uri.parse(url).toFilePath()));
  if (url.startsWith('/')) return FileImage(File(url));
  if (url.startsWith('content://')) return SafDocumentImage(url);
  return null;
}

/// An image read through the storage access framework by document URI —
/// what a doujin page saved under a SAF download folder is addressed by.
@immutable
class SafDocumentImage extends ImageProvider<SafDocumentImage> {
  const SafDocumentImage(this.uri, {this.scale = 1.0});

  final String uri;
  final double scale;

  @override
  Future<SafDocumentImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(SafDocumentImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _load(key, decode),
      scale: key.scale,
      debugLabel: key.uri,
    );
  }

  Future<ui.Codec> _load(SafDocumentImage key, ImageDecoderCallback decode) async {
    final Uint8List? bytes = await ServiceHandler.getSAFFile(key.uri);
    if (bytes == null || bytes.isEmpty) {
      throw StateError('SAF document is empty or unreadable: ${key.uri}');
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) => other is SafDocumentImage && other.uri == uri && other.scale == scale;

  @override
  int get hashCode => Object.hash(uri, scale);
}
