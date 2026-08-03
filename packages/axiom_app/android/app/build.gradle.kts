plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "de.axiom.axiom_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "de.axiom.axiom_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Health Connect verlangt mindestens 26. Kein Verlust: Zielgeraet ist
        // ein aktuelles Android, und die App hat nie eine Nutzerbasis mit
        // alten Geraeten gehabt.
        minSdk = maxOf(flutter.minSdkVersion, 26)
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

dependencies {
    // Flutters Einbettung zieht nur 1.13.1. NotificationCompat.ProgressStyle
    // und setRequestPromotedOngoing gibt es erst ab 1.16 — ohne sie kein
    // Live Update in der Statusleisten-Pille und keine Now Bar.
    implementation("androidx.core:core-ktx:1.17.0")

    // Health Connect: Schlaf und Schritte lesen. Speist capacity und
    // sleepDebt, die sonst nur aus Selbstauskunft stammen.
    implementation("androidx.health.connect:connect-client:1.1.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
