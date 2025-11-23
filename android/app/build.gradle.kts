plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.lagona.buyerapp.lagona_buyer_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    // Try to read from root .env first, then from assets/env/.env
    val rootEnvFile = File(rootProject.projectDir.parentFile, ".env")
    val assetsEnvFile = File(rootProject.projectDir.parentFile, "assets/env/.env")
    val envVars = mutableMapOf<String, String>().apply {
        // Try root .env first
        val envFile = if (rootEnvFile.exists()) rootEnvFile else assetsEnvFile
        if (envFile.exists()) {
            envFile.forEachLine { line ->
                val trimmed = line.trim()
                if (trimmed.isNotEmpty() && !trimmed.startsWith("#") && trimmed.contains("=")) {
                    val idx = trimmed.indexOf("=")
                    val key = trimmed.substring(0, idx).trim()
                    val value = trimmed.substring(idx + 1).trim().trim('"', '\'')
                    put(key, value)
                }
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.lagona.buyerapp.lagona_buyer_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["MAPS_API_KEY"] =
            (System.getenv("MAPS_API_KEY") ?: envVars["MAPS_API_KEY"] ?: "")
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
