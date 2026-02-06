plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("com.facebook.react")
}

android {
    namespace = "com.proxyman.atlantis.reactnative"
    compileSdk = 36

    defaultConfig {
        minSdk = 26
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }
}

dependencies {
    // React Native (provided by the host app)
    compileOnly("com.facebook.react:react-android:+")

    // Atlantis Android library
    implementation("com.proxyman:atlantis-android:1.33.0")

    // OkHttp (provided by React Native / host app)
    compileOnly("com.squareup.okhttp3:okhttp:4.12.0")
}
