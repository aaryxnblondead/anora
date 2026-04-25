# Keep rules for TensorFlow Lite GPU delegate classes referenced by tflite_flutter.
-dontwarn org.tensorflow.lite.gpu.GpuDelegateFactory$Options$GpuBackend
-dontwarn org.tensorflow.lite.gpu.GpuDelegateFactory$Options
1
# Protects the core TensorFlow Lite engine from being deleted during the Release build
-keep class org.tensorflow.lite.** { *; }