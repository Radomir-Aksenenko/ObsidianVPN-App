plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.obsidian.vpn"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.obsidian.vpn"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

// gomobile AAR (package com.obsidian.core.mobile: Mobile, SocketProtector, StatusListener, StatsListener).
// CI writes it to app/android/app/libs/obsidian.aar before `flutter build` ("Bind Go core to AAR"
// in .github/workflows/app.yml). It is not committed, so a local Android build needs it first.
// files("libs/obsidian.aar") is not used on purpose: AGP does not unpack a bare AAR file
// dependency, so its classes and native libs would be missing. flatDir + name/ext resolves it
// as a real Android library.
repositories {
    flatDir {
        dirs(file("libs"))
    }
}

dependencies {
    implementation(mapOf("name" to "obsidian", "ext" to "aar"))
    implementation("androidx.core:core-ktx:1.15.0")
}
