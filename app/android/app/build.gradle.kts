import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Релизный ключ: android/key.properties + android/fern-release.jks (оба вне git).
// Без них релиз собирается debug-ключом — установить поверх боевого APK не выйдет.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "com.fern.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Требуется flutter_local_notifications (java.time на старых Android).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.fern.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { rootProject.file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
            // v3 нужен, чтобы ключ можно было ротировать без переустановки у пользователей.
            enableV1Signing = true
            enableV2Signing = true
            enableV3Signing = true
        }
    }

    // Три канала распространения. Отличаются способом обновляться.
    //  * github  — свой апдейтер качает APK с GitHub (нужно REQUEST_INSTALL_PACKAGES);
    //  * play    — обновляет сам магазин (Play запрещает самообновление, и
    //              разрешение на установку пакетов из этой сборки вырезано,
    //              см. src/play/AndroidManifest.xml);
    //  * rustore — обновляет магазин, разрешение вырезано так же. Подпись при
    //              этом наша, а не магазина, поэтому версии из RuStore и с
    //              GitHub встают друг поверх друга.
    flavorDimensions += "store"
    productFlavors {
        create("github") {
            dimension = "store"
            isDefault = true
        }
        create("play") {
            dimension = "store"
        }
        create("rustore") {
            dimension = "store"
            // ABI режутся ниже, в androidComponents: ndk.abiFilters здесь
            // бесполезен — плагин Flutter выставляет свои фильтры из
            // --target-platform и перетирает флейворные.
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystoreProperties.isEmpty) {
                signingConfigs.getByName("debug")
            } else {
                signingConfigs.getByName("release")
            }
            // Правила R8 (глушим отсутствующие ML Kit CJK-распознаватели).
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

// Из RuStore-сборки выбрасываем x86_64: телефонов на Intel не бывает, а
// libtranslate_jni и распознаватель ML Kit под эту архитектуру весят 29 МБ,
// которые каждый человек скачал бы впустую (магазин отдаёт APK целиком, без
// раздачи по устройствам, как в Play).
//
// Именно так, а не `ndk.abiFilters` во флейворе: плагин Flutter выставляет
// abiFilters сам, из `--target-platform`, и флейворные значения перетирает.
// Флаг `--target-platform` в одиночку тоже не спасает: он управляет только
// библиотеками Flutter, а нативные части плагинов пакует Gradle.
androidComponents {
    onVariants(selector().withFlavor("store" to "rustore")) { variant ->
        variant.packaging.jniLibs.excludes.add("lib/x86*/**")
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
