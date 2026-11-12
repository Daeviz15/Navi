import groovy.json.JsonSlurper

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Local developer configuration remains ignored by Git. CI can supply the key
// through an environment variable without creating env.json for this purpose.
val mapsConfigFile = rootProject.file("../env.json")
val mapsEnvironmentKey = providers.environmentVariable("GOOGLE_MAPS_API_KEY")
    .orElse(providers.environmentVariable("GOOGLE_MAPS_API"))
val mapsApiKey = mapsEnvironmentKey.orNull?.trim().takeUnless { it.isNullOrEmpty() }
    ?: run {
        val config = if (mapsConfigFile.exists()) {
            @Suppress("UNCHECKED_CAST")
            (JsonSlurper().parseText(mapsConfigFile.readText(Charsets.UTF_8).removePrefix("\uFEFF")) as? Map<String, Any?>)
                ?: error("env.json must contain a JSON object")
        } else emptyMap()
        (config["GOOGLE_MAPS_API_KEY"] ?: config["GOOGLE_MAPS_API"])
            ?.toString()?.trim().orEmpty()
    }

android {
    namespace = "com.example.navi"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.navi"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 26)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["NAVI_MAPS_API_KEY"] = mapsApiKey
    }

    buildTypes {
        release {
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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
