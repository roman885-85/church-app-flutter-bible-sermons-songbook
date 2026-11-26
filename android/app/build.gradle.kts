import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

/*
 * Ключ підпису застосунку — поза репозиторієм.
 *
 * Оновлення з GitHub встановлюється поверх старої версії лише тоді, коли обидві
 * підписані одним ключем. Тому ключ один на весь час життя застосунку, лежить поза
 * git і ніколи не потрапляє в репозиторій. Тека з ключем — змінна CHURCH_APP_KEY_DIR
 * (типово ~/.church-app-key): у ній key.properties (storeFile, storePassword, keyAlias,
 * keyPassword) і, за потреби, google-services.json. Файл key.properties можна вказати й
 * окремо — змінною VIDRODZHENNIA_KEY_PROPERTIES.
 * Немає файла — збірка підписується debug-ключем (лише для перевірки на своєму
 * телефоні; така копія оновлень з GitHub не прийме).
 */
val keyDir = System.getenv("CHURCH_APP_KEY_DIR") ?: "${System.getProperty("user.home")}/.church-app-key"
val keyProperties = Properties().apply {
    val path = System.getenv("VIDRODZHENNIA_KEY_PROPERTIES") ?: "$keyDir/key.properties"
    val file = File(path)
    if (file.exists()) file.inputStream().use { load(it) }
}

/*
 * Firebase (миттєві сповіщення, див. PushSetup.kt) — лише якщо поклали
 * google-services.json у теку з ключем підпису. Беремо з нього чотири значення
 * для ресурсів; плагін google-services не потрібен (з AGP 9 він не дружить).
 * Без файла миттєві сповіщення просто не вмикаються; решта працює.
 */
val firebaseValues: Map<String, String>? = run {
    val file = File(keyDir, "google-services.json")
    if (!file.exists()) return@run null
    @Suppress("UNCHECKED_CAST")
    val root = groovy.json.JsonSlurper().parse(file) as Map<String, Any?>
    val project = root["project_info"] as Map<String, Any?>
    @Suppress("UNCHECKED_CAST")
    val client = (root["client"] as List<Map<String, Any?>>).firstOrNull {
        val info = it["client_info"] as Map<String, Any?>
        (info["android_client_info"] as Map<String, Any?>)["package_name"] == "ua.com.baptist.church"
    } ?: return@run null
    val info = client["client_info"] as Map<String, Any?>
    @Suppress("UNCHECKED_CAST")
    val apiKey = ((client["api_key"] as List<Map<String, Any?>>).first())["current_key"] as String
    mapOf(
        "fcm_app_id" to (info["mobilesdk_app_id"] as String),
        "fcm_api_key" to apiKey,
        "fcm_project_id" to (project["project_id"] as String),
        "fcm_sender_id" to (project["project_number"] as String),
    )
}

// Тестова збірка для емулятора: `flutter build apk -P liveTestHooks=true` дає змогу
// підсунути приймачу сповіщень відповідь сайту через adb. У релізах вимкнено.
val liveTestHooks = (project.findProperty("liveTestHooks") as String?) == "true"

android {
    namespace = "ua.com.baptist.church"
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        // ota_update (оновлення з GitHub) написаний на новіших Java API.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "ua.com.baptist.church"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        buildConfigField("boolean", "LIVE_TEST_HOOKS", liveTestHooks.toString())
        firebaseValues?.forEach { (name, value) -> resValue("string", name, value) }
        manifestPlaceholders["liveReceiverExported"] = liveTestHooks.toString()
    }

    buildFeatures {
        buildConfig = true
        resValues = true
    }

    signingConfigs {
        if (keyProperties.getProperty("storeFile") != null) {
            create("release") {
                storeFile = File(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }

    // Синтезатор мінусів (FluidSynth) лежить готовими .so у src/main/jniLibs для
    // arm, arm64 і x86_64 — див. third_party/fluidsynth/README.md. Flutter однаково
    // пакує всі три ABI; x86_64 потрібен лише емулятору, тож у збірку для телефонів
    // (--target-platform без android-x64) він не йде: мінус 4 МБ.
    packaging {
        jniLibs {
            val platforms = (project.findProperty("target-platform") as String?)?.split(",")
            if (platforms != null && "android-x64" !in platforms) {
                excludes += "**/x86_64/*.so"
            }
        }
    }

}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // FCM — див. PushSetup.kt. Без google-services.json просто не вмикається.
    implementation(platform("com.google.firebase:firebase-bom:33.7.0"))
    implementation("com.google.firebase:firebase-messaging")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
