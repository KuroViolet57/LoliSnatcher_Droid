# LoliSnatcher patch (r87, branch claude/r87-npu)

A copy of flutter_onnxruntime 1.8.5 (pub.dev), used through
`dependency_overrides` in the app's pubspec.yaml, so the models can run on the
phone's NPU (Snapdragon Hexagon, ONNX Runtime's QNN execution provider).

Changes, all marked "LoliSnatcher r87" in the sources:

- `android/build.gradle`: base `com.microsoft.onnxruntime:onnxruntime-android:1.27.0`,
  Qualcomm's plugin `com.qualcomm.qti:onnxruntime-android-qnn:2.6.0`, and
  `com.qualcomm.qti:qnn-runtime:2.50.0`. That is the set the plugin 2.6.0
  page says it was validated against. The bundled `onnxruntime-android-qnn`
  AAR is not a dependency. Both manifests override the plugin AAR's minSdk 27.
- `lib/src/ort_session.dart`: `OrtSessionOptions` gains `providerOptions`
  (per provider name), `sessionConfig` (addConfigEntry) and `symbolicDims`
  (setSymbolicDimensionValue; `'*'` fixes every free input dimension, read from
  the model with a plain session first).
- `FlutterOnnxruntimePlugin.kt`: reads those three. XNNPACK still gets its
  options. QNN registers `libonnxruntime_providers_qnn.so` once and calls
  `addExecutionProvider` with the QNN option map. ARM_NN is reported as
  unsupported.

The example app, the doc folder and the logo were left out of the copy.

To undo: remove the `flutter_onnxruntime:` entry under `dependency_overrides`
in pubspec.yaml (the app then uses pub.dev's 1.8.5 again, CPU/NNAPI/XNNPACK
only) and delete this folder.
