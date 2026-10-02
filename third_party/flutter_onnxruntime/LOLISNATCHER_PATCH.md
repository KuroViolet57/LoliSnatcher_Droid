# LoliSnatcher patch (r87, branch claude/r87-npu)

A copy of flutter_onnxruntime 1.8.5 (pub.dev), used through
`dependency_overrides` in the app's pubspec.yaml, so the models can run on the
phone's NPU (Snapdragon Hexagon, ONNX Runtime's QNN execution provider).

Changes, all marked "LoliSnatcher r87" in the sources:

- `android/build.gradle`: `com.microsoft.onnxruntime:onnxruntime-android-qnn:1.23.0`
  instead of `onnxruntime-android:1.23.0` - the same ONNX Runtime and Java API,
  with the QNN provider; it pulls `com.qualcomm.qti:qnn-runtime:2.37.1`.
- `lib/src/ort_session.dart`: `OrtSessionOptions` gains `providerOptions`
  (per provider name), `sessionConfig` (addConfigEntry) and `symbolicDims`
  (setSymbolicDimensionValue; `'*'` fixes every free input dimension, read from
  the model with a plain session first).
- `FlutterOnnxruntimePlugin.kt`: reads those three; `addQnn` and `addXnnpack`
  get their provider options instead of empty maps.

The example app, the doc folder and the logo were left out of the copy.

To undo: remove the `flutter_onnxruntime:` entry under `dependency_overrides`
in pubspec.yaml (the app then uses pub.dev's 1.8.5 again, CPU/NNAPI/XNNPACK
only) and delete this folder.
