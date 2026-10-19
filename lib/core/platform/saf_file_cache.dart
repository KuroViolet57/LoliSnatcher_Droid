import 'dart:async';

import 'package:lolisnatcher/core/platform/service_handler.dart';

class SAFFileCache {
  SAFFileCache._();
  static final SAFFileCache instance = SAFFileCache._();

  String _cachedUri = '';
  final Set<String> _fileNames = {};
  Set<String> get fileNames => _fileNames;
  bool _isPopulated = false;
  bool get isPopulated => _isPopulated;
  bool _isPopulating = false;
  Completer<void>? _populateCompleter;

  /// 1.0: moved on by [invalidate]. A listing started before it (the
  /// download folder changed while the start of the app listed the old one)
  /// must not fill the cache with the old folder's names.
  int _generation = 0;

  Future<bool> existsFile(String safUri, String fileName) async {
    bool result;

    if (safUri == _cachedUri && _isPopulated) {
      result = _fileNames.contains(fileName);
    } else {
      result = await ServiceHandler.existsFileFromSAFDirectoryFast(safUri, fileName);
    }

    return result;
  }

  Future<void> populate(String safUri) async {
    // skip if can't get access to saf folder for some reason
    // 1.0: asks Android whether the grant exists (hasSafAccess). The old check
    // (testSAF) opened the folder picker when there was no grant - at app start,
    // unasked - and otherwise wrote and deleted a test file in the download
    // folder on the main thread at every start. Downloads still go through
    // setPermissions, which offers the picker when the folder is gone.
    if (_isPopulating || !await ServiceHandler.hasSafAccess(safUri)) {
      await _populateCompleter?.future;
      return;
    }
    _isPopulating = true;
    _populateCompleter = Completer<void>();

    final int generation = _generation;
    try {
      _cachedUri = safUri;
      final names = await ServiceHandler.listFileNamesFromSAFDirectory(safUri);
      if (generation != _generation) return;
      _fileNames.clear();
      _fileNames.addAll(names);
      _isPopulated = true;
    } catch (e) {
      _isPopulated = false;
    } finally {
      _isPopulating = false;
      _populateCompleter?.complete();
    }
  }

  void onFileCreated(String fileName) {
    if (_isPopulated) {
      _fileNames.add(fileName);
    }
  }

  void onFileDeleted(String fileName) {
    if (_isPopulated) {
      _fileNames.remove(fileName);
    }
  }

  void invalidate() {
    _generation++;
    _fileNames.clear();
    _isPopulated = false;
    _cachedUri = '';
  }
}
