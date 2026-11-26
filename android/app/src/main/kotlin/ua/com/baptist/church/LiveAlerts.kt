package ua.com.baptist.church

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Сповіщення «почалася пряма трансляція».
 *
 * Телефон сам питає сайт (/api/live), але не весь час: сайт у відповіді каже,
 * коли питати знову (`alert.nextCheckInMs`) — раз на 2 хвилини у вікні
 * трансляції й раз на 15 поза ним. Якщо збірка має FCM (PushSetup), сайт ще й
 * будить телефон сам, щойно ефір почався, — будильник тоді лише страховка.
 * Будильник «allow while idle» будить і сплячий телефон та дає ~10 секунд
 * мережі — вистачає на один маленький запит. Flutter у фоні не запускається.
 */
object LiveAlerts {
    const val ACTION_CHECK = "ua.com.baptist.church.LIVE_CHECK"
    const val ACTION_OPEN_LIVE = "ua.com.baptist.church.OPEN_LIVE"
    const val EXTRA_OPEN = "open"

    private const val PREFS = "live_alerts"
    private const val CHANNEL = "live"
    private const val NOTIFICATION_ID = 7001
    private const val REQUEST_ALARM = 7002
    private const val DEFAULT_ENDPOINT = "https://baptist.com.ua/api/live"
    private const val RETRY_MS = 5 * 60_000L

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun isEnabled(ctx: Context) = prefs(ctx).getBoolean("enabled", false)

    fun notificationsAllowed(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT >= 33 &&
            ctx.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return false
        return ctx.getSystemService(NotificationManager::class.java)?.areNotificationsEnabled() ?: false
    }

    fun setEndpoint(ctx: Context, endpoint: String?) {
        if (!endpoint.isNullOrBlank() && endpoint.startsWith("https://")) {
            prefs(ctx).edit().putString("endpoint", endpoint).apply()
        }
    }

    fun setEnabled(ctx: Context, enabled: Boolean, endpoint: String?) {
        setEndpoint(ctx, endpoint)
        prefs(ctx).edit().putBoolean("enabled", enabled).apply()
        if (enabled) {
            schedule(ctx, 5_000)
        } else {
            cancelAlarm(ctx)
            cancelNotification(ctx)
        }
        // Миттєві сповіщення (FCM), якщо збірка їх має: підписка на тему «live».
        runCatching { PushSetup.syncTopics(ctx) }
    }

    /** Будильник уже стоїть? Якщо ні (застосунок зупиняли примусово) — ставимо знову. */
    fun ensureScheduled(ctx: Context) {
        if (isEnabled(ctx) && alarmIntent(ctx, PendingIntent.FLAG_NO_CREATE) == null) schedule(ctx, 10_000)
    }

    private fun alarmIntent(ctx: Context, flags: Int): PendingIntent? {
        val intent = Intent(ctx, LiveAlertReceiver::class.java).setAction(ACTION_CHECK)
        return PendingIntent.getBroadcast(ctx, REQUEST_ALARM, intent, flags or PendingIntent.FLAG_IMMUTABLE)
    }

    fun schedule(ctx: Context, delayMs: Long) {
        val am = ctx.getSystemService(AlarmManager::class.java) ?: return
        val pi = alarmIntent(ctx, PendingIntent.FLAG_UPDATE_CURRENT) ?: return
        val at = System.currentTimeMillis() + delayMs.coerceAtLeast(5_000)
        prefs(ctx).edit().putLong("nextAt", at).apply()
        val exact = Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms()
        try {
            if (exact) am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            else am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        } catch (e: SecurityException) {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        }
    }

    private fun cancelAlarm(ctx: Context) {
        val pi = alarmIntent(ctx, PendingIntent.FLAG_NO_CREATE) ?: return
        ctx.getSystemService(AlarmManager::class.java)?.cancel(pi)
        pi.cancel()
    }

    /** Один запит до сайту; повертає, через скільки мілісекунд питати знову. */
    fun check(ctx: Context): Long {
        val endpoint = prefs(ctx).getString("endpoint", null) ?: DEFAULT_ENDPOINT
        val body = fetch(endpoint) ?: return RETRY_MS
        return handle(ctx, body)
    }

    fun handle(ctx: Context, body: String): Long {
        val json = try {
            JSONObject(body)
        } catch (e: Exception) {
            return RETRY_MS
        }
        val p = prefs(ctx)
        val live = json.optJSONObject("live")
        if (live != null) {
            val id = live.optString("id")
            if (id.isNotEmpty() && id != p.getString("notifiedId", null)) {
                val title = live.optString("title").ifBlank { Texts.t(ctx, "Пряма трансляція богослужіння") }
                if (show(ctx, title)) p.edit().putString("notifiedId", id).putBoolean("showing", true).apply()
            }
        } else if (p.getBoolean("showing", false)) {
            // Трансляція скінчилась — «наживо» не має висіти в шторці до вечора.
            cancelNotification(ctx)
        }
        val advised = json.optJSONObject("alert")?.optLong("nextCheckInMs", -1L) ?: -1L
        val next = when {
            advised > 0 -> advised
            json.optLong("nextInMs", 0L) in 1..60_000 -> 3 * 60_000L // старіший сайт: «у вікні»
            else -> 30 * 60_000L
        }
        return next.coerceIn(60_000L, 6 * 60 * 60_000L)
    }

    private fun fetch(endpoint: String): String? = try {
        val conn = URL(endpoint).openConnection() as HttpURLConnection
        conn.connectTimeout = 4_000
        conn.readTimeout = 5_000
        conn.setRequestProperty("Accept", "application/json")
        conn.setRequestProperty("User-Agent", "VidrodzhenniaApp/1.0 (Android; live alerts)")
        try {
            if (conn.responseCode == 200) conn.inputStream.bufferedReader().use { it.readText() } else null
        } finally {
            conn.disconnect()
        }
    } catch (e: Exception) {
        null
    }

    private fun show(ctx: Context, title: String): Boolean {
        if (!notificationsAllowed(ctx)) return false
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return false
        if (Build.VERSION.SDK_INT >= 26) {
            // Щоразу: так назва каналу в налаштуваннях телефона йде за мовою застосунку
            // (важливість Android не змінює, лише назву й опис).
            val channel = NotificationChannel(CHANNEL, Texts.t(ctx, "Прямі трансляції"), NotificationManager.IMPORTANCE_HIGH)
            channel.description = Texts.t(ctx, "Повідомлення, щойно почнеться трансляція богослужіння")
            nm.createNotificationChannel(channel)
        }
        val open = Intent(ctx, MainActivity::class.java)
            .setAction(ACTION_OPEN_LIVE)
            .putExtra(EXTRA_OPEN, "live")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val content = PendingIntent.getActivity(
            ctx, NOTIFICATION_ID, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(ctx, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(ctx).setPriority(Notification.PRIORITY_HIGH).setDefaults(Notification.DEFAULT_ALL)
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_live)
            .setContentTitle(Texts.t(ctx, "Почалася пряма трансляція"))
            .setContentText(title)
            .setStyle(Notification.BigTextStyle().bigText(title))
            .setContentIntent(content)
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_EVENT)
            .setColor(0xFF6D402C.toInt())
            .build()
        nm.notify(NOTIFICATION_ID, notification)
        return true
    }

    fun cancelNotification(ctx: Context) {
        ctx.getSystemService(NotificationManager::class.java)?.cancel(NOTIFICATION_ID)
        prefs(ctx).edit().putBoolean("showing", false).apply()
    }
}
