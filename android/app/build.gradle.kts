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

fun admobAndroidApplicationId(): String =
    System.getenv("ADMOB_ANDROID_APPLICATION_ID")
        ?: localProperties.getProperty("admob.android.application.id")
        ?: "ca-app-pub-4216543114907932~4253667866"

fun signingPropsFile(): java.io.File? {
    System.getenv("ANDROID_KEY_PROPERTIES")?.let { raw ->
        file(raw).takeIf { it.exists() }?.let { return it }
    }
    localProperties.getProperty("ANDROID_KEY_PROPERTIES")?.let { raw ->
        file(raw).takeIf { it.exists() }?.let { return it }
    }
    val repoJks = rootProject.file("../../../jks/key.properties")
    if (repoJks.exists()) return repoJks
    return rootProject.file("key.properties").takeIf { it.exists() }
}

android {
    namespace = "com.adbkv.chainpop"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.adbkv.chainpop"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        val admobAppId = admobAndroidApplicationId()
        manifestPlaceholders["admobApplicationId"] = admobAppId
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
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            signingConfig =
                signingConfigs
                    .findByName("release")
                    ?.takeIf { it.storeFile?.exists() == true }
                    ?: signingConfigs.getByName("debug")
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
