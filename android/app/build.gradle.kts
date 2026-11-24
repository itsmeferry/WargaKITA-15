plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

android {
    namespace = "id.kebonagung.rt15.wargakita"
    compileSdk = 35

    defaultConfig {
        applicationId = "id.kebonagung.rt15.wargakita"
        minSdk = 23
        targetSdk = 35
        versionCode = 26
        versionName = "1.16.0"

        buildConfigField("String", "SUPABASE_URL", "\"https://bwufyctxcttqhrepsevw.supabase.co\"")
        buildConfigField("String", "SUPABASE_ANON_KEY", "\"sb_publishable_Sto3oP18p0Jqin_QGSr5Hg_qRUoNMlG\"")
    }

    signingConfigs {
        create("release") {
            val ksPath = System.getenv("WK_KEYSTORE_PATH")
            if (!ksPath.isNullOrBlank()) {
                storeFile = file(ksPath)
                storePassword = System.getenv("WK_KEYSTORE_PASS") ?: ""
                keyAlias = System.getenv("WK_KEY_ALIAS") ?: ""
                keyPassword = System.getenv("WK_KEY_PASS") ?: ""
            }
        }
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = false
            val ksPath = System.getenv("WK_KEYSTORE_PATH")
            if (!ksPath.isNullOrBlank()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.09.03"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.6")
    implementation("androidx.navigation:navigation-compose:2.8.2")
    implementation(platform("io.github.jan-tennert.supabase:bom:3.0.1"))
    implementation("io.github.jan-tennert.supabase:auth-kt")
    implementation("io.github.jan-tennert.supabase:postgrest-kt")
    implementation("io.ktor:ktor-client-android:3.0.0")
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
}
