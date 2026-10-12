import 'package:lolisnatcher/models/settings/mpv_build.dart';

/// Token 154: what the test handheld measured for the media_kit engine, for
/// the (i) windows in Settings -> Video. Sources: token 153's changes.txt
/// (traces of 2026-10-12) and the token 154 runs (session log).
///
/// Each run: the same 4 rule34 mp4 posts opened from the feed, 8 s each, pool
/// of 8, Settings -> Debug -> Record a trace. "First picture" = from asking
/// for a player to the first frame on screen; "dropped" = frames mpv dropped;
/// memory = the app's native memory after the 4 videos (dumpsys meminfo).
class EngineMeasurements {
  const EngineMeasurements._();

  static const String device = 'AYN Thor (Snapdragon 8 Gen 2, Adreno 740), 2026-10-12';

  static const String _how =
      'Same 4 mp4 posts each run, opened once each, so one video can be a few hundred ms off from network luck. '
      'Per video: time to the first picture, then dropped frames, then native memory after the 4 videos.';

  static String build(MpvBuild build) {
    switch (build) {
      case MpvBuild.classic:
        return 'Measured on the $device. $_how\n'
            '- output gpu, HWDEC vulkan (software there): 713 / 1288 / 1471 / 684 ms, dropped 0 / 5 / 12 / 0, 881 MB.\n'
            '- output gpu, HWDEC auto-safe (phone decoder, copying): 853 / 1425 / 608 / 655 ms, dropped 0 / 6 / 7 / 0, 713 MB.\n'
            '- output gpu, HWDEC mediacodec (phone decoder, no copy): 848 / 1648 / 708 / 612 ms, dropped 0 / 5 / 5 / 0, 614 MB.';
      case MpvBuild.mpv041:
        return 'Measured on the $device. $_how\n'
            '- output gpu, HWDEC vulkan (software there): 1156 / 1538 / 801 / 762 ms, dropped 0 / 4 / 7 / 0, 1028 MB.\n'
            '- output gpu, HWDEC auto-safe (phone decoder, copying): 858 / 1025 / 1043 / 738 ms, dropped 0 / 7 / 8 / 0, 740 MB.\n'
            '- output gpu, HWDEC mediacodec (phone decoder, no copy): 1064 / 1312 / 859 / 674 ms, dropped 0 / 4 / 9 / 0, 620 MB.\n'
            '- output gpu-next (Vulkan), auto-safe: 710 / 1035 / 723 / 731 ms, nothing dropped, 722 MB, '
            'but graphics memory 331 MB instead of about 178 MB.';
    }
  }

  /// Decoder chain (token 154). Filled from the token 154 device runs.
  static const String chain = 'Not measured yet on the $device.';

  /// SurfaceTexture (token 154). Filled from the token 154 device runs.
  static const String surfaceTexture = 'Not measured yet on the $device.';
}
