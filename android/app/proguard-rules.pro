# Proguard rules for FlashFlow Sentinel

# Keep all native methods and their parameter/return type descriptors.
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}

# Keep the JNI classes from dart-lang jni package
-keep class com.github.dart_lang.jni.** { *; }
-dontwarn com.github.dart_lang.jni.**

# Keep Flutter embedding and plugins
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Suppress warnings for missing Google Play Core classes (used by Flutter deferred components)
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.android.FlutterPlayStoreSplitApplication
-dontwarn io.flutter.embedding.engine.deferredcomponents.PlayStoreDeferredComponentManager

# Keep llama_flutter_android plugin (JNI-facing) and its lambda/callback classes.
# The native side does a JNI method-name lookup on a Kotlin Function1 lambda
# passed in as a progress callback; R8 renames/strips it without these rules.
-keep class com.write4me.llama_flutter_android.** { *; }
-dontwarn com.write4me.llama_flutter_android.**

-keep class kotlin.jvm.functions.** { *; }
-keepclassmembers class * implements kotlin.jvm.functions.Function1 {
    public *** invoke(...);
}
-keep class kotlin.jvm.internal.Lambda { *; }
