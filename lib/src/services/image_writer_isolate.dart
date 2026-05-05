import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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
      print('found image at: ${cachePath + fileName} for $fileURL :: ImageWriterIsolate /:: readFileFromCache');
      if (!await image.exists()) {
        return null;
      }
    } catch (e) {
      print('Image Writer Isolate Exception :: read cache file :: $e');
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
    final int queryIndex = thumbURL.indexOf('?'); // Sankaku fix
    final String urlWithoutQuery = queryIndex != -1 ? thumbURL.substring(0, queryIndex) : thumbURL;
    String result = urlWithoutQuery.substring(urlWithoutQuery.lastIndexOf('/') + 1);

    if (result.startsWith('thumb.')) {
      //Paheal/shimmie(?) fix
      final String unthumbedURL = thumbURL.replaceAll('/thumb', '');

      final int unthumbedQueryIndex = unthumbedURL.indexOf('?');
      final String unthumbedUrlWithoutQuery = unthumbedQueryIndex != -1 ? unthumbedURL.substring(0, unthumbedQueryIndex) : unthumbedURL;

      result = unthumbedUrlWithoutQuery.substring(unthumbedUrlWithoutQuery.lastIndexOf('/') + 1);
    }
    return result;
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
