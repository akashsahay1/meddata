plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
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
        // Old-phone support: Android 6.0 (Marshmallow) and up — ~98% device coverage.
        // 23 is Flutter 3.44's hard engine floor (below this the build is rejected);
        // still far below Flutter's default of 24, so we support older phones.
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

    buildTypes {
        release {
            // Signing with debug keys for now so `flutter run --release` works.
            // Replace with a real keystore before publishing (see docs/TASKS.md Phase 6).
            signingConfig = signingConfigs.getByName("debug")
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
