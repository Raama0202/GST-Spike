# Flutter engine and plugin registrant
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**
# Deferred components / Play Core are referenced by the engine but not used.
-dontwarn com.google.android.play.core.**

# Secure storage (Android Keystore / Tink)
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**

# url_launcher
-keep class io.flutter.plugins.urllauncher.** { *; }

# Keep stack traces readable in crash reports
-keepattributes SourceFile, LineNumberTable
-renamesourcefileattribute SourceFile
