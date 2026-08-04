import java.util.Properties

// Signaturangaben aus einer Datei, die nicht im Repository liegt.
// Ohne sie baut `flutter build apk --release` weiter — aber mit dem
// Debug-Schluessel, und das steht dann auch in der Ausgabe. Ein Release,
// das sich nicht von einem Debug-Build unterscheidet, ist keins.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasSigningKey = keyProperties.getProperty("storeFile") != null

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

    signingConfigs {
        if (hasSigningKey) {
            create("release") {
                storeFile = rootProject.file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    defaultConfig {
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
            signingConfig = if (hasSigningKey) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "AXIOM: android/key.properties fehlt — die Release-APK " +
                        "wird mit dem Debug-Schluessel signiert. Den kennt " +
                        "jeder Flutter-Rechner der Welt."
                )
                signingConfigs.getByName("debug")
            }

            // R8 raeumt auf und verkleinert. Ohne `isShrinkResources` bleiben
            // die Ressourcen der ungenutzten Health-Connect-Oberflaechen drin.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
