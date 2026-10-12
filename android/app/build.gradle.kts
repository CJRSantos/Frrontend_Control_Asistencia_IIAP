plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.control_asistencia"
    compileSdk = flutter.compileSdkVersion
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
        // ID de la aplicación que coincide con Google Cloud Console
        applicationId = "pe.gob.iiap.attendance"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
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

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

tasks.register("renameReleaseApk") {
    doLast {
        val apkDir = file("${layout.buildDirectory.get()}/outputs/flutter-apk")
        val defaultApk = file("$apkDir/app-release.apk")
        val namedApk = file("$apkDir/Control Asistencia.apk")
        if (defaultApk.exists()) {
            defaultApk.copyTo(namedApk, overwrite = true)
            val rootApk = file("${rootDir}/../Control Asistencia.apk")
            defaultApk.copyTo(rootApk, overwrite = true)
            println("=== APK renombrado exitosamente como 'Control Asistencia.apk' ===")
            println("Ubicación 1: ${namedApk.absolutePath}")
            println("Ubicación 2: ${rootApk.absolutePath}")
        }
    }
}

tasks.matching { it.name == "assembleRelease" }.configureEach {
    finalizedBy("renameReleaseApk")
}
