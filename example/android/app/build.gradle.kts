plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.telosnex.fonnx.fonnx_example"
    compileSdk = flutter.compileSdkVersion
    // 25-05-28:
    // Your project is configured with Android NDK 26.3.11579264, but the following plugin(s) depend on a different Android NDK version:
    // - audioplayers_android requires Android NDK 27.0.12077973
    // - file_picker requires Android NDK 27.0.12077973
    // - flutter_plugin_android_lifecycle requires Android NDK 27.0.12077973
    // - fonnx requires Android NDK 27.0.12077973
    // - path_provider_android requires Android NDK 27.0.12077973
    // - record_android requires Android NDK 27.0.12077973
    // Fix this issue by using the highest Android NDK version (they are backward compatible).
    // Add the following to /Users/jpo/dev/fonnx/example/android/app/build.gradle.kts:
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.telosnex.fonnx.fonnx_example"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // needed 21 for ONNX ORT 1.16; in June 2024 need 23 for record_android
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

flutter {
    source = "../.."
}
