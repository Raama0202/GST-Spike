# Flutter engine and plugin registrant
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**
# Deferred components / Play Core are referenced by the engine but not used.
-dontwarn com.google.android.play.core.**

# ML Kit text recognition + document scanner (only the Latin model is bundled)
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_** { *; }
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# WorkManager (background sync) instantiates workers reflectively
-keep class * extends androidx.work.ListenableWorker { <init>(...); }
-keep class be.tramckrijte.workmanager.** { *; }
-keep class dev.fluttercommunity.workmanager.** { *; }

# flutter_local_notifications serialises scheduled notifications with Gson
-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }
-keepattributes Signature, *Annotation*, InnerClasses, EnclosingMethod
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# Secure storage (Android Keystore / Tink)
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**

# sqflite
-keep class com.tekartik.sqflite.** { *; }

# Keep stack traces readable in crash reports
-keepattributes SourceFile, LineNumberTable
-renamesourcefileattribute SourceFile
