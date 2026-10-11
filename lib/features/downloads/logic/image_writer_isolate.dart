import 'dart:async';
import 'dart:io';


class ImageWriterIsolate {
  ImageWriterIsolate(this.cacheRootPath);
  final String cacheRootPath;

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
}
