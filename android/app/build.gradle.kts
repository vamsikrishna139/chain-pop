import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

val localProperties = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) {
        f.reader(Charsets.UTF_8).use { load(it) }
    }
}

// Explicit AdMob app id supplied by the environment or local.properties.
// When set it wins for every build type, including debug.
fun admobApplicationIdOverride(): String? =
    System.getenv("ADMOB_ANDROID_APPLICATION_ID")
        ?: localProperties.getProperty("admob.android.application.id")

// Production AdMob app id. Release builds only.
fun admobAndroidApplicationId(): String =
    admobApplicationIdOverride()
        ?: "ca-app-pub-6510329237083952~7569862231"

// Google's public sample AdMob app id. Debug builds only, so that debug
// traffic never reaches the production app id. The Dart side defaults
// kAdmobUseSampleUnits to !kReleaseMode, so debug requests sample ad units;
// those must be paired with the sample app id or AdMob treats it as
// invalid traffic against the real account.
// https://developers.google.com/admob/android/quick-start
fun admobDebugApplicationId(): String =
    admobApplicationIdOverride()
        ?: "ca-app-pub-3940256099942544~3347511713"

fun signingPropsFile(): java.io.File? {
    System.getenv("ANDROID_KEY_PROPERTIES")?.let { raw ->
        file(raw).takeIf { it.exists() }?.let { return it }
    }
    localProperties.getProperty("ANDROID_KEY_PROPERTIES")?.let { raw ->
        file(raw).takeIf { it.exists() }?.let { return it }
    }
    // Machine-specific developer fallback: a keystore checked out beside the
    // repo. CI and any other machine must supply ANDROID_KEY_PROPERTIES via
    // env var or local.properties instead of relying on this path.
    val repoJks = rootProject.file("../../../jks/key.properties")
    if (repoJks.exists()) return repoJks
    return rootProject.file("key.properties").takeIf { it.exists() }
}

android {
    namespace = "com.adbkv.chainpop"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.adbkv.chainpop"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Safe default; each build type below sets its own value.
        manifestPlaceholders["admobApplicationId"] = admobDebugApplicationId()
    }

    signingConfigs {
        create("release") {
            val propsFile = signingPropsFile()
            if (propsFile != null) {
                val keystoreProps = Properties()
                propsFile.reader(Charsets.UTF_8).use { keystoreProps.load(it) }
                keyAlias = keystoreProps["keyAlias"] as String
                keyPassword = keystoreProps["keyPassword"] as String
                val rawStoreFile = keystoreProps["storeFile"] as String
                storeFile =
                    file(
                        if (rawStoreFile.startsWith("/")) rawStoreFile
                        else rootProject.file(rawStoreFile),
                    )
                storePassword = keystoreProps["storePassword"] as String
            }
        }
    }

    buildTypes {
        debug {
            manifestPlaceholders["admobApplicationId"] = admobDebugApplicationId()
        }
        release {
            manifestPlaceholders["admobApplicationId"] = admobAndroidApplicationId()
            isMinifyEnabled = true
            isShrinkResources = true
            signingConfig =
                signingConfigs
                    .findByName("release")
                    ?.takeIf { it.storeFile?.exists() == true }
                    ?: throw GradleException("Release signing config 'release' is missing or invalid.")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    // Same version games_services pulls in; used directly by MainActivity for
    // the queued (non-"Immediate") achievement writes.
    implementation("com.google.android.gms:play-services-games-v2:21.0.0")
}
