# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# WebRTC
-keep class org.webrtc.** { *; }
-keep class com.cloudwebrtc.webrtc.** { *; }
-keep class org.jni_zero.** { *; }

# Flutter Foreground Task
-keep class com.pravera.flutter_foreground_task.** { *; }
-keep class com.pravera.flutter_foreground_task.models.** { *; }
-keep class com.pravera.flutter_foreground_task.services.** { *; }

# Awesome Notifications
-keep class me.carda.awesome_notifications.** { *; }
-keep class me.carda.awesome_notifications.core.** { *; }

# JNI & Callbacks
-keepclasseswithmembernames class * {
    native <methods>;
}
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}
-keepnames class * implements java.io.Serializable

# Ignore missing Google Play core libraries
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**