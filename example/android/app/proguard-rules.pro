# ONNX
# https://onnxruntime.ai/docs/build/android.html#note-proguard-rules-for-r8-minimization-android-app-builds-to-work
# via https://github.com/microsoft/onnxruntime/issues/17847
-keep class ai.onnxruntime.** { *; }