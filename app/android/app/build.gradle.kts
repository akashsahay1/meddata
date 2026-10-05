import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties (gitignored) points at the upload
// keystore. Without it, release builds fall back to the debug key so
// `flutter run --release` still works — never publish such a build.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.medstock.med_stock"
    // Some plugins (file_picker → flutter_plugin_android_lifecycle) require 36+.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required for flutter_local_notifications on older Android (API 21+).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.medstock.med_stock"
        // Flutter 3.44's default, 24 (Android 7.0). Plugins such as
        // flutter_secure_storage need 24, so it is also the effective floor.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
        // 32-bit (armeabi-v7a) + 64-bit (arm64-v8a) are included by Flutter by
        // default, so old 32-bit-only phones can install. We do NOT set an
        // explicit ndk abiFilters here because it conflicts with the
        // `--split-per-abi` release build (which manages ABI splitting itself).
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Real upload key when android/key.properties exists (see
            // docs/MEDDATA.md §10), else the debug key for local release runs.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Keep the release small for low-end devices.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
    // Enables Java 8+ APIs (used by flutter_local_notifications) down to API 21.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
