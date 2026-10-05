import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get_it/get_it.dart';

import 'package:lolisnatcher/core/logging/logger.dart';
import 'package:lolisnatcher/core/platform/download_notice.dart';
import 'package:lolisnatcher/core/utils/tools.dart';

/// Posts the snatch notices. The in-app banner stays in SnatchHandler.
class NotifyHandler {
  NotifyHandler({FlutterLocalNotificationsPlugin? plugin}) : _injected = plugin;

  final FlutterLocalNotificationsPlugin? _injected;
  FlutterLocalNotificationsPlugin? _owned;
  final List<DownloadNotice> posted = [];
  bool _ready = false;
  bool _permissionAsked = false;

  FlutterLocalNotificationsPlugin get _plugin => _injected ?? (_owned ??= FlutterLocalNotificationsPlugin());

  static NotifyHandler get instance => GetIt.instance<NotifyHandler>();

  static NotifyHandler register() {
    if (!GetIt.instance.isRegistered<NotifyHandler>()) {
      GetIt.instance.registerSingleton(NotifyHandler());
    }
    return instance;
  }

  static void unregister() => GetIt.instance.unregister<NotifyHandler>();

  /// Records [notice] under `flutter test`. On a device, initializes the
  /// plugin once, asks Android 13+ for permission once per process, and
  /// replaces the previous notice with the same id.
  Future<void> show(DownloadNotice notice) async {
    if (Tools.isTestMode) {
      posted.add(notice);
      return;
    }
    try {
      final bool? ready = await _ensureReady();
      if (ready == false) return;
      if (!await _allowed()) {
        Logger.Inst().log(
          'download notice not posted (notifications off or permission denied): ${notice.title}',
          'NotifyHandler',
          'show',
          LogTypes.settingsLoad,
        );
        return;
      }
      await _plugin.show(
        id: notice.id,
        title: notice.title,
        body: notice.body.isEmpty ? null : notice.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'downloads',
            'Downloads',
            channelDescription: 'Snatch queue and finished downloads. Silent; sound can be turned on in system settings.',
            icon: 'ic_stat_download',
            playSound: false,
            enableVibration: false,
          ),
        ),
      );
      Logger.Inst().log(
        'download notice posted: ${notice.title}',
        'NotifyHandler',
        'show',
        LogTypes.settingsLoad,
      );
    } catch (e, s) {
      Logger.Inst().log(
        'download notice failed: $e',
        'NotifyHandler',
        'show',
        LogTypes.exception,
        s: s,
      );
    }
  }

  Future<bool?> _ensureReady() async {
    if (_ready) return true;
    final bool? ok = await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_download'),
      ),
    );
    _ready = ok != false;
    return ok;
  }

  Future<bool> _allowed() async {
    final AndroidFlutterLocalNotificationsPlugin? android =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    final bool? enabled = await android.areNotificationsEnabled();
    if (enabled == true) return true;
    if (_permissionAsked) return false;
    _permissionAsked = true;
    final bool? granted = await android.requestNotificationsPermission();
    return granted == true;
  }
}
