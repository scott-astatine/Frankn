import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android Gradle plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

configurations.all {
    resolutionStrategy {
        eachDependency {
            if (requested.group == "androidx.core" && (requested.name == "core" || requested.name == "core-ktx")) {
                useVersion("1.13.1")
            }
            if (requested.group == "androidx.activity" && (requested.name == "activity" || requested.name == "activity-ktx")) {
                useVersion("1.9.3")
            }
            if (requested.group == "androidx.navigationevent" && requested.name == "navigationevent-android") {
                useVersion("1.0.0")
            }
        }
    }
}

android {
    namespace = "com.astatine.frankn.frankn"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.astatine.frankn.frankn"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = signingConfigs.create("release")
            val keystoreProperties = Properties()
            val keystorePropertiesFile = rootProject.file("key.properties")
            if (keystorePropertiesFile.exists()) {
                keystoreProperties.load(keystorePropertiesFile.inputStream())
                signingConfig?.keyAlias = keystoreProperties.getProperty("keyAlias")
                signingConfig?.keyPassword = keystoreProperties.getProperty("keyPassword")
                signingConfig?.storeFile = file(keystoreProperties.getProperty("storeFile"))
                signingConfig?.storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }
}

flutter {
    source = "../.."
}
