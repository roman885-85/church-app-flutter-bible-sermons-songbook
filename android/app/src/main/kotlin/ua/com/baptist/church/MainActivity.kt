package ua.com.baptist.church

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// AudioServiceActivity, а не FlutterActivity: так звук проповідей живе у фоні
// й на заблокованому екрані, коли вікно застосунку закрите (just_audio_background).
class MainActivity : AudioServiceActivity() {
    private var channel: MethodChannel? = null
    private var pendingEnable: Triple<MethodChannel.Result, String, String?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Підписки FCM на теми — за перемикачами сповіщень (після перевстановлення,
        // зміни токена чи першого запуску збірки з FCM).
        runCatching { PushSetup.syncTopics(this) }
        // Мова застосунку: Dart уже зберіг її в налаштуваннях (Texts читає звідти),
        // тут — лише підтвердження, щоб виклик не падав.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ua.com.baptist.church/lang").setMethodCallHandler { call, result ->
            if (call.method == "setLang") result.success(Texts.lang(this)) else result.notImplemented()
        }
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ua.com.baptist.church/live_alerts").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(
                        mapOf(
                            "enabled" to LiveAlerts.isEnabled(this),
                            "news" to ContentAlerts.isEnabled(this, "news"),
                            "videos" to ContentAlerts.isEnabled(this, "videos"),
                            "sermons" to ContentAlerts.isEnabled(this, "sermons"),
                            "allowed" to LiveAlerts.notificationsAllowed(this),
                        ),
                    )
                    "enable" -> enable(result, "live", call.argument<String>("endpoint"))
                    "enableKind" -> enable(result, call.argument<String>("kind") ?: "", call.argument<String>("endpoint"))
                    "disable" -> {
                        LiveAlerts.setEnabled(this, false, null)
                        result.success(true)
                    }
                    "disableKind" -> {
                        val kind = call.argument<String>("kind") ?: ""
                        if (kind == "live") LiveAlerts.setEnabled(this, false, null) else ContentAlerts.setEnabled(applicationContext, kind, false)
                        result.success(true)
                    }
                    "ensure" -> {
                        LiveAlerts.setEndpoint(this, call.argument<String>("endpoint"))
                        LiveAlerts.ensureScheduled(applicationContext)
                        ContentAlerts.ensureScheduled(applicationContext)
                        result.success(null)
                    }
                    "openSettings" -> {
                        openNotificationSettings()
                        result.success(null)
                    }
                    "takeLaunchAction" -> {
                        dartReady = true
                        result.success(takeOpen(intent))
                    }
                    else -> result.notImplemented()
                }
            }
        }
        // Ярлик на значку, коли застосунок уже працює: Android відкриває ярлики
        // з CLEAR_TASK, тож вікно створюється наново, а Dart живе далі (рушій
        // спільний зі звуком) і сам про запуск не спитає — кажемо йому.
        if (dartReady) takeOpen(intent)?.let { channel?.invokeMethod("open", it) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // Рушій переживає вікно (грає звук) — не тримаємо в ньому посилання на старе вікно.
        channel?.setMethodCallHandler(null)
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun enable(result: MethodChannel.Result, kind: String, endpoint: String?) {
        if (kind != "live" && kind !in ContentAlerts.KINDS) {
            result.success("failed")
            return
        }
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingEnable?.first?.success("denied")
            pendingEnable = Triple(result, kind, endpoint)
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
            return
        }
        finishEnable(result, kind, endpoint)
    }

    private fun finishEnable(result: MethodChannel.Result, kind: String, endpoint: String?) {
        if (!LiveAlerts.notificationsAllowed(this)) {
            result.success("blocked")
            return
        }
        if (kind == "live") LiveAlerts.setEnabled(this, true, endpoint) else ContentAlerts.setEnabled(applicationContext, kind, true)
        result.success("enabled")
    }

    /** Що відкрити після натиску на сповіщення: {open, id, title} або null. */
    private fun takeOpen(intent: Intent?): Map<String, String?>? {
        val open = intent?.getStringExtra(LiveAlerts.EXTRA_OPEN) ?: return null
        val payload = mapOf("open" to open, "id" to intent.getStringExtra("id"), "title" to intent.getStringExtra("title"))
        intent.removeExtra(LiveAlerts.EXTRA_OPEN)
        intent.removeExtra("id")
        intent.removeExtra("title")
        return payload
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_NOTIFICATIONS) return
        val (result, kind, endpoint) = pendingEnable ?: return
        pendingEnable = null
        when {
            grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED -> finishEnable(result, kind, endpoint)
            // Відмовили вдруге («більше не питати») — тепер лише через налаштування.
            !shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS) -> result.success("blocked")
            else -> result.success("denied")
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val payload = takeOpen(intent) ?: return
        channel?.invokeMethod("open", payload)
    }

    private fun openNotificationSettings() {
        val settings = if (Build.VERSION.SDK_INT >= 26) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
        }
        startActivity(settings.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private companion object {
        const val REQUEST_NOTIFICATIONS = 7003

        /** Dart уже забрав дію запуску — нові дії йому передаються самі. */
        @Volatile
        var dartReady = false
    }
}
