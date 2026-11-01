import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties (see key.properties.example). Never commit it.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
val buildingRelease = gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
if (hasReleaseKey) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
} else if (buildingRelease) {
    // CI sets REQUIRE_RELEASE_KEY=true so a store build can never ship debug-signed.
    if (System.getenv("REQUIRE_RELEASE_KEY") == "true") {
        throw GradleException("REQUIRE_RELEASE_KEY=true but android/key.properties is missing; refusing to sign a release with the debug key.")
    }
    logger.error(
        """
        |************************************************************************
        |* android/key.properties NOT FOUND - this RELEASE build is signed with *
        |* the DEBUG key. It installs for testing but Play will REJECT it.      *
        |* Set REQUIRE_RELEASE_KEY=true in CI to turn this into a build error.  *
        |************************************************************************
        """.trimMargin()
    )
}

android {
    namespace = "com.gstexpenses.gst_expense_scanner"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.gstexpenses.gst_expense_scanner"
        // Android 7.0+. 24 is the Flutter engine floor and matches the
        // network_security_config trust-anchor support.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // From pubspec `version: x.y.z+N` (or --build-name / --build-number).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKey) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (hasReleaseKey) "release" else "debug")
            // R8 is intentionally OFF: it strips classes that plugins create by reflection
            // (e.g. WorkManager's WorkDatabase_Impl), crashing the app on launch. The
            // proguard-rules.pro (incl. ML Kit keeps) is only used if this is re-enabled;
            // verify a release build cold-starts and runs background sync before doing so.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
