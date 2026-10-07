# r34: the ONNX Runtime plugin (flutter_onnxruntime) loads these by name.
-keep class ai.onnxruntime.** { *; }

# mpvlibAndroid JNI looks these classes and methods up by name.
-keep class is.xyz.mpv.** { *; }
