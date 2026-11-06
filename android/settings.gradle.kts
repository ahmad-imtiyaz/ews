pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("com.google.gms.google-services") version "4.4.4" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")

// repo.maven.apache.org menolak (403) jaringan pengembang, jadi Maven Central
// diambil dari mirror Google lebih dulu, termasuk buildscript milik plugin.
val mavenCentralMirror = "https://maven-central.storage-download.googleapis.com/maven2/"
gradle.beforeProject {
    buildscript.repositories.maven { url = uri(mavenCentralMirror) }
    repositories.maven { url = uri(mavenCentralMirror) }
}
