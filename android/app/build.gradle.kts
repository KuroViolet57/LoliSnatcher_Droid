import com.android.build.gradle.internal.api.ApkVariantOutputImpl
import java.io.FileInputStream
import java.io.FileNotFoundException
import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.reader(Charsets.UTF_8).use { reader ->
        localProperties.load(reader)
    }
}

val flutterRoot = localProperties.getProperty("flutter.sdk")
    ?: throw FileNotFoundException("Flutter SDK not found. Define location with flutter.sdk in the local.properties file.")

val flutterVersionCode = localProperties.getProperty("flutter.versionCode") ?: "1"
val flutterVersionName = localProperties.getProperty("flutter.versionName") ?: "1.0"

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

var dartEnvVars = mapOf(
    "LS_IS_STORE" to "false",
    "LS_IS_TESTING" to "false"
)
if (project.hasProperty("dart-defines")) {
    dartEnvVars = dartEnvVars + (project.property("dart-defines") as String)
        .split(",")
        .associate { entry ->
            val pair = String(Base64.getDecoder().decode(entry), Charsets.UTF_8).split("=")
            pair.first() to pair.last()
        }
}
println("LS_IS_STORE=${dartEnvVars["LS_IS_STORE"]}")
// 1.0: --dart-define=LS_SIDE_BY_SIDE=true builds an app that installs NEXT TO
// the regular one (its own package id, data and launcher label "... 1.0"),
// so both can run on one phone for comparison. Without it nothing changes.
val sideBySide = dartEnvVars["LS_SIDE_BY_SIDE"] == "true"
println("LS_SIDE_BY_SIDE=$sideBySide")
val packageName = (if (dartEnvVars["LS_IS_STORE"] == "true") {
    "com.noaisu.play.loliSnatcher"
} else {
    "com.noaisu.loliSnatcher"
}) + (if (sideBySide) ".v1" else "")
println("packageName=$packageName")
println("compileSdk=${flutter.compileSdkVersion}")
println("ndkVersion=${flutter.ndkVersion}")
println("minSdkVersion=${flutter.minSdkVersion}")
println("targetSdkVersion=${flutter.targetSdkVersion}")

android {
    namespace = "com.noaisu.loliSnatcher"

    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications 10+ needs desugaring even for a notice
        // that is shown immediately.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    defaultConfig {
        applicationId = packageName
        multiDexEnabled = true
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutterVersionCode.toInt()
        versionName = flutterVersionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // Appended to every launcher label in the manifests (empty normally).
        manifestPlaceholders["appLabelSuffix"] = if (sideBySide) " 1.0" else ""
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as? String
            keyPassword = keystoreProperties["keyPassword"] as? String
            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
            storePassword = keystoreProperties["storePassword"] as? String
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            // r34: ONNX Runtime binds its Java classes by name; R8 must keep them.
            proguardFiles("proguard-rules.pro")
        }

        debug {
            signingConfig = if (keystoreProperties["storeFile"] != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    packagingOptions {
        jniLibs {
            // decreases APK size by ~40-50%, but maybe conflicts with 16KB page size devices?
            // possibly increases install and startup time
            // not used on play store builds
            useLegacyPackaging = dartEnvVars["LS_IS_STORE"] != "true"
            // r87: Qualcomm's QNN runtime (the NPU) also carries its GPU backend
            // and the old DSP one, which the app never asks for. The HTP (NPU)
            // libraries of every generation stay, and its compiler (QnnHtpPrepare),
            // which compiles a model for the NPU on the phone.
            excludes += setOf(
                "**/libQnnGpu.so",
                "**/libQnnDsp.so",
                "**/libQnnDspV66Skel.so",
                "**/libQnnDspV66Stub.so",
            )
        }
    }

    applicationVariants.all {
        outputs.all {
            val output = this as? ApkVariantOutputImpl
            // Override the version code to be the 'flutterVersionCode'
            // ignoring the ABI-specific logic added by Flutter
            output?.versionCodeOverride = flutterVersionCode.toInt()
        }
    }

    buildFeatures {
        buildConfig = true
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk8:2.1.0")
    implementation("androidx.documentfile:documentfile:1.0.1")
}
