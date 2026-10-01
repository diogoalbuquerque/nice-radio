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
    // START: FlutterFire Configuration
    // 4.4.1, not flutterfire configure's own default of 4.3.15: the
    // Crashlytics Gradle plugin below (v3) refuses to configure against
    // anything older, and fails the whole build with a fairly opaque
    // "Failed to query the value of task ... appIdFile" error if it's not
    // bumped — see https://firebase.google.com/docs/crashlytics/upgrade-to-crashlytics-gradle-plugin-v3
    id("com.google.gms.google-services") version("4.4.1") apply false
    // Uploads native/NDK symbol-mapping info at build time so a real crash
    // stack trace is readable in the Firebase console instead of raw
    // addresses — see android/app/build.gradle.kts for where it's applied.
    id("com.google.firebase.crashlytics") version("3.0.8") apply false
    // END: FlutterFire Configuration
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
