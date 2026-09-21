import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

/**
 * Release signing material, resolved from (in order):
 *   1. android/key.properties  — git-ignored, for local release builds
 *   2. environment variables   — for CI, where secrets are injected
 *
 * Nothing here is ever committed: no keystore, no passwords, no defaults.
 * When the material is absent `releaseSigning` stays null, development and
 * staging keep building debug-signed, and productionRelease fails loudly
 * (see the productionRelease guard at the bottom of this file).
 */
data class ReleaseSigning(
    val storeFile: File,
    val storePassword: String,
    val keyAlias: String,
    val keyPassword: String,
)

var releaseSigningProblem: String? = null

val releaseSigning: ReleaseSigning? = run {
    val properties = Properties()
    val propertiesFile = rootProject.file("key.properties")
    if (propertiesFile.exists()) {
        propertiesFile.inputStream().use(properties::load)
    }

    fun value(propertyKey: String, envKey: String): String? {
        val raw = properties.getProperty(propertyKey)
            ?: System.getenv(envKey)
            ?: providers.gradleProperty(propertyKey).orNull
        return raw?.trim()?.takeIf(String::isNotEmpty)
    }

    val storePath = value("storeFile", "MEVORA_ANDROID_KEYSTORE_PATH")
    val storePassword = value("storePassword", "MEVORA_ANDROID_KEYSTORE_PASSWORD")
    val keyAlias = value("keyAlias", "MEVORA_ANDROID_KEY_ALIAS")
    val keyPassword = value("keyPassword", "MEVORA_ANDROID_KEY_PASSWORD")

    val provided = listOf(storePath, storePassword, keyAlias, keyPassword)
    if (provided.all { it == null }) {
        // Nothing configured at all — the normal state of a fresh checkout.
        return@run null
    }
    val missing = listOf(
        "storeFile/MEVORA_ANDROID_KEYSTORE_PATH" to storePath,
        "storePassword/MEVORA_ANDROID_KEYSTORE_PASSWORD" to storePassword,
        "keyAlias/MEVORA_ANDROID_KEY_ALIAS" to keyAlias,
        "keyPassword/MEVORA_ANDROID_KEY_PASSWORD" to keyPassword,
    ).filter { it.second == null }.map { it.first }
    if (missing.isNotEmpty()) {
        releaseSigningProblem = "incomplete configuration, missing: " + missing.joinToString(", ")
        return@run null
    }

    val resolvedStore = file(storePath!!).let { candidate ->
        if (candidate.isAbsolute) candidate else rootProject.file(storePath)
    }
    if (!resolvedStore.exists()) {
        releaseSigningProblem = "keystore not found at " + resolvedStore.absolutePath
        return@run null
    }
    ReleaseSigning(
        storeFile = resolvedStore,
        storePassword = storePassword!!,
        keyAlias = keyAlias!!,
        keyPassword = keyPassword!!,
    )
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
    }

    flavorDimensions += "environment"
    productFlavors {
        create("development") {
            dimension = "environment"
            // Same applicationId as the Firebase Android app with OAuth SHA-1 registered.
            versionNameSuffix = "-dev"
            resValue("string", "app_name", "Mevora Dev")
        }
        create("staging") {
            dimension = "environment"
            applicationIdSuffix = ".staging"
            versionNameSuffix = "-staging"
            resValue("string", "app_name", "Mevora Staging")
        }
        create("production") {
            dimension = "environment"
            resValue("string", "app_name", "Mevora")
        }
    }

    signingConfigs {
        val signing = releaseSigning
        if (signing != null) {
            create("release") {
                storeFile = signing.storeFile
                storePassword = signing.storePassword
                keyAlias = signing.keyAlias
                keyPassword = signing.keyPassword
            }
        }
    }

    buildTypes {
        release {
            // Development and staging release builds stay debug-signed so
            // `flutter run --release` keeps working without signing material.
            // productionRelease is guarded below and fails instead.
            signingConfig = if (releaseSigning != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

// A production release must never be silently debug-signed.
//
// The check runs once the task graph is known, so it fails in seconds and
// only when a production release was actually requested — every other
// variant still configures and builds on a machine with no signing material.
// The doFirst backstop covers the case where the graph hook is skipped.
if (releaseSigning == null) {
    val problem = releaseSigningProblem
    val message = buildString {
        append("Production release signing is not configured")
        if (problem != null) {
            append(" (")
            append(problem)
            append(")")
        }
        appendLine(".")
        appendLine("Refusing to sign a production release with the debug keystore.")
        append("See docs/ANDROID_RELEASE_SIGNING.md for setup.")
    }
    val guardedTasks = setOf(
        "assembleProductionRelease",
        "bundleProductionRelease",
        "packageProductionRelease",
    )

    gradle.taskGraph.whenReady {
        val requested = allTasks.any { task ->
            task.project == project && task.name in guardedTasks
        }
        if (requested) {
            throw GradleException(message)
        }
    }

    afterEvaluate {
        guardedTasks.forEach { taskName ->
            tasks.findByName(taskName)?.doFirst {
                throw GradleException(message)
            }
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