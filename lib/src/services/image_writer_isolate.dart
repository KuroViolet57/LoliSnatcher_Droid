import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

class ImageWriterIsolate {
  ImageWriterIsolate(this.cacheRootPath);
  final String cacheRootPath;

  Future<File?> writeCacheFromBytes(
    String fileURL,
    List<int> bytes,
    String typeFolder, {
    required String fileNameExtras,
    bool clearName = true,
  }) async {
    File? image;
    try {
      final String cachePath = '$cacheRootPath$typeFolder/';
      await Directory(cachePath).create(recursive: true);

      final String fileName = sanitizeName(
        clearName ? parseThumbUrlToName(fileURL) : fileURL,
        fileNameExtras: fileNameExtras,
      );
      image = File(cachePath + fileName);
      print('found image at: ${cachePath + fileName} for $fileURL :: ImageWriterIsolate :: readFileFromCache');
      await image.writeAsBytes(bytes, flush: true);
    } catch (e) {
      print('Image Writer Isolate Exception :: cache write bytes :: $e');
      return null;
    }
    return image;
  }

  Future<File?> readFileFromCache(
    String fileURL,
    String typeFolder, {
    required String fileNameExtras,
    bool clearName = true,
  }) async {
    File? image;
    try {
      final String cachePath = '$cacheRootPath$typeFolder/';
      final String fileName = sanitizeName(
        clearName ? parseThumbUrlToName(fileURL) : fileURL,
        fileNameExtras: fileNameExtras,
      );
      image = File(cachePath + fileName);
      // TODO is readBytes required here?
      print('found image at: ${cachePath + fileName} for $fileURL :: ImageWriterIsolate /:: readFileFromCache');
      if (await image.exists()) {
        await image.readAsBytes();
      }
    } catch (e) {
      print('Image Writer Isolate Exception :: cache write :: $e');
      return null;
    }
    return image;
  }

  Future<Uint8List?> readBytesFromCache(
    String fileURL,
    String typeFolder, {
    required String fileNameExtras,
    bool clearName = true,
  }) async {
    Uint8List? imageBytes;
    try {
      final String cachePath = '$cacheRootPath$typeFolder/';
      final String fileName = sanitizeName(
        clearName ? parseThumbUrlToName(fileURL) : fileURL,
        fileNameExtras: fileNameExtras,
      );
      final File image = File(cachePath + fileName);

      if (await image.exists()) {
        imageBytes = await image.readAsBytes();
        print('found image at: ${cachePath + fileName} for $fileURL :: ImageWriterIsolate :: readBytesFromCache');
      } else {
        print(
          'could not find image at: ${cachePath + fileName} for $fileURL :: ImageWriterIsolate :: readBytesFromCache',
        );
      }
    } catch (e) {
      print('Image Writer Isolate Exception :: read bytes cache :: $e');
      return null;
    }
    return imageBytes;
  }

  String parseThumbUrlToName(String thumbURL) {
    String result = '';
    if (thumbURL.contains('Hydrus-Client')) {
      final match = RegExp(r'[?&](id|file_id|hash)=([^&]+)').firstMatch(thumbURL);
      if (match != null && match.group(2) != null) {
        result = "hydrusThumb_${match.group(2)}";
      } else {
        final bytes = utf8.encode(thumbURL);
        final hash = md5.convert(bytes);
        result = "hydrusThumb_$hash";
      }
    } else {
      final int queryIndex = thumbURL.indexOf('?'); // Sankaku fix
      final String urlWithoutQuery = queryIndex != -1 ? thumbURL.substring(0, queryIndex) : thumbURL;
      result = urlWithoutQuery.substring(urlWithoutQuery.lastIndexOf('/') + 1);

      if (result.startsWith('thumb.')) {
        //Paheal/shimmie(?) fix
        final String unthumbedURL = thumbURL.replaceAll('/thumb', '');

        final int unthumbedQueryIndex = unthumbedURL.indexOf('?');
        final String unthumbedUrlWithoutQuery = unthumbedQueryIndex != -1 ? unthumbedURL.substring(0, unthumbedQueryIndex) : unthumbedURL;

        result = unthumbedUrlWithoutQuery.substring(unthumbedUrlWithoutQuery.lastIndexOf('/') + 1);
      }

      result = _disambiguate(urlWithoutQuery, result);
    }

    return result;
  }

  /// Generic basenames need the directory mixed in, or they all collide.
  ///
  /// The cache used to name files by the URL's last path segment alone. That
  /// works for the many boorus that put a hash or a post id in the filename
  /// (`1d01c636af3b9656….jpg`), but some sites carry the identity in the
  /// DIRECTORY and give every file the same generic name:
  ///
  ///   tik.porn  …/video/1753/1753144/list-sm.jpg   -> "list-sm.jpg"
  ///   xxxtik    …/{uid}/thumbnail.webp             -> "thumbnail.webp"
  ///
  /// Every post on those sites then shared one cache entry, so an entire grid
  /// rendered as whichever thumbnail was fetched first. (The narrow
  /// `thumb.`/Paheal case below is the same bug, patched one site at a time.)
  ///
  /// Only names that carry no identity of their own are prefixed, so cache
  /// entries for every normal booru keep their existing filenames instead of
  /// being invalidated wholesale.
  static bool _nameIsIdentifying(String fileName) {
    final int dot = fileName.lastIndexOf('.');
    final String stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    // A hash or an id: a run of 8+ alphanumerics containing at least a digit.
    for (final match in RegExp(r'[A-Za-z0-9]{8,}').allMatches(stem)) {
      if (RegExp(r'[0-9]').hasMatch(match.group(0)!)) return true;
    }
    return false;
  }

  static String _disambiguate(String urlWithoutQuery, String fileName) {
    if (fileName.isEmpty || _nameIsIdentifying(fileName)) return fileName;
    final int slash = urlWithoutQuery.lastIndexOf('/');
    if (slash <= 0) return fileName;
    final String dir = urlWithoutQuery.substring(0, slash);
    final String hash = md5.convert(utf8.encode(dir)).toString().substring(0, 10);
    return '${hash}_$fileName';
  }


  // calculates cache (total or by type) size and file count
  Future<Map<String, dynamic>> getCacheStat(String? typeFolder) async {
    String cacheDirPath;
    int fileNum = 0;
    int totalSize = 0;
    try {
      cacheDirPath = '$cacheRootPath${typeFolder ?? ''}/';

      final Directory cacheDir = Directory(cacheDirPath);
      final bool dirExists = await cacheDir.exists();
      if (dirExists) {
        final List<FileSystemEntity> files = await cacheDir.list(recursive: true, followLinks: false).toList();
        for (final FileSystemEntity file in files) {
          if (file is File) {
            fileNum++;
            totalSize += await file.length();
          }
        }
      }
    } catch (e) {
      print('Image Writer Isolate Exception :: cache stat :: $e');
    }

    return {
      'type': typeFolder,
      'fileNum': fileNum,
      'totalSize': totalSize,
    };
  }

  String sanitizeName(String fileName, {required String fileNameExtras}) {
    return '${Tools.sanitize(fileNameExtras)}${Tools.sanitize(fileName)}';
  }
}
