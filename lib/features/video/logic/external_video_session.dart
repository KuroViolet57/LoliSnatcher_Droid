import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:lolisnatcher/features/video/logic/bridged_video_controller.dart';
import 'package:lolisnatcher/models/settings/video_engine_choice.dart';

const MethodChannel videoEngineChannel = MethodChannel('com.noaisu.loliSnatcher/video_engine');
const EventChannel videoEngineEvents = EventChannel('com.noaisu.loliSnatcher/video_engine_events');

Stream<dynamic>? _videoEngineEventStream;
int _nextVideoEngineRequest = 1;

/// One native subscription, shared by every open video.
Stream<dynamic> videoEngineEventStream() {
  return _videoEngineEventStream ??= videoEngineEvents.receiveBroadcastStream().asBroadcastStream();
}

/// What the process actually loaded before plugins started.
///
/// `off` means media_kit's libmpv, if anything, is the one in memory.
/// A missing channel (tests, desktop) is `off`.
Future<String> loadedMpvlibVariant() async {
  try {
    final String? value = await videoEngineChannel.invokeMethod<String>('loadedVariant');
    return value == 'vulkan' || value == 'opengl' ? value! : 'off';
  } catch (error) {
    debugPrint('video-engine: loadedVariant unavailable ($error)');
    return 'off';
  }
}

class ExternalVideoHandle {
  ExternalVideoHandle(this.controller, this.textureId);

  final BridgedVideoController controller;
  final int textureId;
}

/// Opens Media3 or the already-loaded mpvlib build and returns the texture
/// LoliControls' viewer should show.
Future<ExternalVideoHandle> openExternalVideo({
  required VideoEngineChoice choice,
  required String url,
  required Map<String, String> headers,
}) async {
  int? textureId;
  StreamSubscription<dynamic>? events;
  final int requestId = _nextVideoEngineRequest++;
  late final BridgedVideoController controller;
  controller = BridgedVideoController(
    url: url,
    onCommand: (String name, Map<String, Object?> args) async {
      final Map<String, Object?> payload = <String, Object?>{
        ...args,
        'engine': choice.name,
        'requestId': requestId,
        'textureId': ?textureId,
        if (name == 'open') 'headers': headers,
      };
      final Object? raw = await videoEngineChannel.invokeMethod<Object?>(name, payload);
      if (name == 'open' && raw is Map) {
        textureId = (raw['textureId'] as num?)?.toInt();
      }
      if (name == 'dispose') {
        await events?.cancel();
        events = null;
      }
      return raw;
    },
  );

  events = videoEngineEventStream().listen(
    (Object? event) {
      if (event is! Map || textureId == null) return;
      if ((event['textureId'] as num?)?.toInt() != textureId) return;
      controller.applyNative(event);
    },
    onError: (Object error) {
      debugPrint('video-engine: event error $error');
    },
  );

  debugPrint('video-engine: open ${choice.name} $url');
  try {
    await controller.initialize().timeout(const Duration(seconds: 20));
  } catch (error) {
    await events?.cancel();
    events = null;
    debugPrint('video-engine: open failed $error');
    await controller.dispose();
    rethrow;
  }
  final int? id = textureId;
  if (id == null || !controller.value.isInitialized) {
    await events?.cancel();
    await controller.dispose();
    throw StateError('The video engine did not return a picture');
  }
  return ExternalVideoHandle(controller, id);
}
