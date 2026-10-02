import 'package:flutter/foundation.dart';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'package:lolisnatcher/src/data/model_tasks.dart';

/// r88: what the installed ONNX Runtime can run on. The NPU build
/// (onnxruntime-android-qnn) has no XNNPACK - "XNNPACK execution provider is
/// not supported in this build" (log 2026-10-02) - so Run on offers only
/// what is there. Asked once (at start and when Settings → Models opens);
/// until then every choice is offered.
class OnnxAvailability {
  const OnnxAvailability._();

  static Set<String>? _providers;

  /// The provider names this build has, once known.
  static Set<String>? get providers => _providers;

  static String? _providerOf(ModelAccelerator a) => switch (a) {
    ModelAccelerator.cpu => null,
    ModelAccelerator.xnnpack => 'XNNPACK',
    ModelAccelerator.nnapi => 'NNAPI',
    ModelAccelerator.npu => 'QNN',
  };

  /// [a] can run in this build (the CPU always can).
  static bool has(ModelAccelerator a) {
    final String? p = _providerOf(a);
    final Set<String>? known = _providers;
    return p == null || known == null || known.contains(p);
  }

  /// What [model] may run on in this build.
  static List<ModelAccelerator> choicesFor(ModelKind model) => [
    for (final ModelAccelerator a in ModelAccelerator.choicesFor(model))
      if (has(a)) a,
  ];

  static Future<Set<String>?> Function() _ask = _defaultAsk;

  static Future<Set<String>?> _defaultAsk() async {
    try {
      return {for (final OrtProvider p in await OnnxRuntime().getAvailableProviders()) p.name};
    } catch (_) {
      return null;
    }
  }

  /// Asks the runtime once; later calls answer from memory.
  static Future<Set<String>?> load() async => _providers ??= await _ask();

  @visibleForTesting
  static void setForTests(Set<String>? providers) => _providers = providers;

  @visibleForTesting
  static void resetForTests() {
    _providers = null;
    _ask = _defaultAsk;
  }
}
