/// Token 153: which libmpv the media_kit engine loads. Both ship in the APK
/// (third_party/libmpv-android/README.md); one is used per process.
enum MpvBuild {
  /// libmpv-android-video-build v1.1.11: mpv git of 2023-10, FFmpeg 6.0.
  classic,

  /// Our own build: mpv 0.41, FFmpeg 7.1, libplacebo (gpu-next, Vulkan).
  mpv041,
  ;

  /// The value stored in settings.json (`mediaKitLibmpv`).
  String get setting => name;

  /// The file media_kit opens.
  String get libraryName => switch (this) {
    MpvBuild.classic => 'libmpv.so',
    MpvBuild.mpv041 => 'libmpvls.so',
  };

  String get label => switch (this) {
    MpvBuild.classic => 'Classic (mpv 2023, FFmpeg 6.0)',
    MpvBuild.mpv041 => 'mpv 0.41 (FFmpeg 7.1, libplacebo)',
  };

  static const List<String> settingOptions = ['classic', 'mpv041'];

  /// Unknown, empty or missing values read as [classic], the old behaviour.
  static MpvBuild fromSetting(String? raw) => raw == 'mpv041' ? MpvBuild.mpv041 : MpvBuild.classic;
}
