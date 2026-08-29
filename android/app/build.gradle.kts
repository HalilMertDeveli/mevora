plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

android {
    namespace = "com.mevora.app"
  // flutter_secure_storage 11.x requires API 37; SDK folder is android-37.0 (junction android-37).
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.mevora.app"
        minSdk = flutter.minSdkVersion
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Google sample AdMob app ID — safe for debug/QA.
        // Production flavor overrides via ADMOB_ANDROID_APP_ID env/property.
        manifestPlaceholders["admobAppId"] =
            "ca-app-pub-3940256099942544~3347511713"
    }

    flavorDimensions += "environment"
    productFlavors {
        create("development") {
            dimension = "environment"
            // Same applicationId as the Firebase Android app with OAuth SHA-1 registered.
            versionNameSuffix = "-dev"
            resValue("string", "app_name", "Mevora Dev")
            manifestPlaceholders["admobAppId"] =
                "ca-app-pub-3940256099942544~3347511713"
        }
        create("staging") {
            dimension = "environment"
            applicationIdSuffix = ".staging"
            versionNameSuffix = "-staging"
            resValue("string", "app_name", "Mevora Staging")
            manifestPlaceholders["admobAppId"] =
                "ca-app-pub-3940256099942544~3347511713"
        }
        create("production") {
            dimension = "environment"
            resValue("string", "app_name", "Mevora")
            // Prefer CI/local property or env; never hard-code production IDs.
            // Falls back to Google sample so accidental builds stay policy-safe.
            val fromProp = (project.findProperty("ADMOB_ANDROID_APP_ID") as String?)?.trim()
            val fromEnv = System.getenv("ADMOB_ANDROID_APP_ID")?.trim()
            val prodAdmob = when {
                !fromProp.isNullOrEmpty() -> fromProp
                !fromEnv.isNullOrEmpty() -> fromEnv
                else -> "ca-app-pub-3940256099942544~3347511713"
            }
            manifestPlaceholders["admobAppId"] = prodAdmob
        }
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

// Flutter CLI looks for app-debug.apk when --flavor is omitted; flavored builds
// emit app-<flavor>-debug.apk. Mirror the development artifact after that build.
val flutterProjectRoot = rootProject.projectDir.parentFile!!
val flutterApkDir = flutterProjectRoot.resolve("build/app/outputs/flutter-apk")

afterEvaluate {
    tasks.findByName("assembleDevelopmentDebug")?.doLast {
        val source = flutterApkDir.resolve("app-development-debug.apk")
        val target = flutterApkDir.resolve("app-debug.apk")
        if (source.exists()) {
            source.copyTo(target, overwrite = true)
        }
    }
}