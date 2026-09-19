import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.mindsprint.trivia"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // Required by flutter_local_notifications (added 2026-09-10 for
        // local reminder notifications) -- its Android implementation
        // uses java.time APIs that need desugaring support on API levels
        // below 26. Without this, any build that touches notification
        // scheduling fails at compile time with an explicit error naming
        // this exact flag.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.mindsprint.trivia"
        // Hardcoded rather than flutter.minSdkVersion: the in_app_purchase
        // plugin (added 2026-08-22 for real Play Billing) requires Android
        // SDK 24+ (Android 7.0, released 2016). This trades away support
        // for a small number of very old devices in exchange for real
        // payments -- a normal trade-off, not expected to meaningfully
        // affect the current tester/player base.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { rootProject.file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Fails the build loudly instead of silently falling back to
            // debug signing (as this used to). Play itself already rejects
            // a debug-signed upload, so that fallback could never actually
            // ship a bad release -- but it used to let `flutter build
            // appbundle --release` "succeed" and produce a useless
            // artifact on a fresh clone or CI runner that never copied
            // key.properties, with the real failure only surfacing much
            // later as a confusing Play Console error.
            if (!keystorePropertiesFile.exists()) {
                throw GradleException(
                    "android/key.properties is missing -- cannot build a " +
                    "signed release. See the project handover doc for what " +
                    "it needs to contain (keyAlias, keyPassword, storeFile, " +
                    "storePassword)."
                )
            }
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Pairs with isCoreLibraryDesugaringEnabled above -- required by
    // flutter_local_notifications.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
