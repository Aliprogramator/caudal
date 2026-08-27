import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

// Firma propia: sin esto el APK saldria firmado con la clave de depuracion
// y no se podria actualizar sobre una instalacion anterior.
val clavesArchivo = rootProject.file("key.properties")
val claves = Properties()
if (clavesArchivo.exists()) {
    claves.load(FileInputStream(clavesArchivo))
}

android {
    namespace = "com.kevinrr.caudal"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.kevinrr.caudal"
        // flutter.minSdkVersion es 24: suficiente para el navegador integrado,
        // el reproductor de fondo y el lector de QR.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (clavesArchivo.exists()) {
            create("release") {
                keyAlias = claves["keyAlias"] as String
                keyPassword = claves["keyPassword"] as String
                storeFile = rootProject.file(claves["storeFile"] as String)
                storePassword = claves["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (clavesArchivo.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
