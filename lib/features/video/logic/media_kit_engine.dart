import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:media_kit/media_kit.dart';

import 'package:lolisnatcher/core/logging/logger.dart';
import 'package:lolisnatcher/models/settings/mpv_build.dart';

/// Token 153: the one place that starts media_kit, with the libmpv build the
/// user picked (Settings -> Video -> media_kit libmpv build).
///
/// media_kit re-resolves its library on every `MediaKit.ensureInitialized`
/// call, and players made after a re-resolve would talk to the other
/// library. So the first call here locks the build for the whole process;
/// a different choice takes effect after a restart ([restartNeeded]).
class MediaKitEngine {
  const MediaKitEngine._();

  static MpvBuild? _loaded;

  /// The build this process runs, or null before the first video.
  static MpvBuild? get loaded => _loaded;

  static MpvBuild? _fellBackFrom;

  /// The build that was asked for but would not open in this process (Classic
  /// plays instead), or null. A restart would fail the same way, so Settings
  /// says so instead of promising one (review 2026-10-14, finding 1).
  static MpvBuild? get fellBackFrom => _fellBackFrom;

  /// Starts media_kit once. [open] and [log] are seams for tests.
  static MpvBuild ensureInitialized(
    String? setting, {
    void Function(String library)? open,
    void Function(String message)? log,
  }) {
    final MpvBuild? already = _loaded;
    if (already != null) return already;
    // Desktop keeps media_kit's own lookup (libmpv-2.dll, libmpv.so.2, ...):
    // the two builds are Android libraries. Tests pass [open] and count as Android.
    if (open == null && !Platform.isAndroid) {
      MediaKit.ensureInitialized();
      return _loaded = MpvBuild.classic;
    }
    final void Function(String) openLibrary = open ?? ((String lib) => MediaKit.ensureInitialized(libmpv: lib));
    final void Function(String) write = log ?? _log;
    MpvBuild build = MpvBuild.fromSetting(setting);
    try {
      openLibrary(build.libraryName);
    } catch (e) {
      if (build == MpvBuild.classic) rethrow;
      write('media_kit engine: ${build.libraryName} would not open ($e); using classic (${MpvBuild.classic.libraryName})');
      _fellBackFrom = build;
      build = MpvBuild.classic;
      openLibrary(build.libraryName);
    }
    _loaded = build;
    write('media_kit engine: ${build.setting} (${build.libraryName}) loaded');
    return build;
  }

  /// True when the stored choice is not the build this process loaded and a
  /// restart can change that (not when that choice just failed to open).
  static bool restartNeeded(String? setting) {
    final MpvBuild? now = _loaded;
    final MpvBuild wanted = MpvBuild.fromSetting(setting);
    return now != null && now != wanted && wanted != _fellBackFrom;
  }

  /// The Settings -> Video line under "media_kit libmpv build": what runs now
  /// and whether a restart is pending, or that the chosen build would not open.
  static String statusText(String? setting) {
    final MpvBuild? now = _loaded;
    if (now == null) return 'Nothing loaded yet in this run.';
    final MpvBuild? failed = _fellBackFrom;
    if (failed != null && failed == MpvBuild.fromSetting(setting)) {
      return '${failed.label} would not open on this device; ${now.label} plays the videos (see the log, "media_kit engine").';
    }
    return 'Loaded now: ${now.label}.${restartNeeded(setting) ? ' Restart the app to switch.' : ''}';
  }

  /// "media_kit engine: mpv041 (libmpvls.so) · mpv v0.41.0-110 · FFmpeg n7.1.3".
  static String engineLine(MpvBuild build, {required String mpvVersion, required String ffmpegVersion}) {
    String or(String v) => v.trim().isEmpty ? '?' : v.trim();
    return 'media_kit engine: ${build.setting} (${build.libraryName}) · ${or(mpvVersion)} · FFmpeg ${or(ffmpegVersion)}';
  }

  static void _log(String message) =>
      Logger.Inst().log(message, 'MediaKitEngine', 'ensureInitialized', LogTypes.booruItemLoad);

  @visibleForTesting
  static void resetForTest() {
    _loaded = null;
    _fellBackFrom = null;
  }
}
