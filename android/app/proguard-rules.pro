# Chain Pop — release minification enabled in android/app/build.gradle.kts.

# Flutter embedding references Play Core deferred-delivery / split APIs even when the
# app does not ship those libraries. Without this, R8 aborts with “Missing class …
# com.google.android.play.core…” during minifyReleaseWithR8.
-dontwarn com.google.android.play.core.**

# Launcher activity (manifest entry point).
-keep class com.adbkv.chainpop.MainActivity { *; }

-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
