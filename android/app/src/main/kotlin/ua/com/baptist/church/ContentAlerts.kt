package ua.com.baptist.church

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Сповіщення про нове на сайті: новини (зі статтями й фото), відео, проповіді.
 *
 * Раз на годину (JobScheduler сам підлаштовує під сон і мережу телефона)
 * питаємо /api/app/v1/latest — по 10 найсвіжіших записів кожного розділу — і
 * порівнюємо з тим, що вже бачили. Перша перевірка після ввімкнення лише
 * запамʼятовує наявне, щоб не засипати людину старими записами.
 */
object ContentAlerts {
    val KINDS = listOf("news", "videos", "sermons")

    private const val PREFS = "content_alerts"
    private const val JOB_ID = 7101
    private const val ENDPOINT = "https://baptist.com.ua/api/app/v1/latest"
    private const val MAX_SEEN = 60

    private const val PERIOD_MS = 15 * 60_000L

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun isEnabled(ctx: Context, kind: String) = prefs(ctx).getBoolean("enabled_$kind", false)

    private fun anyEnabled(ctx: Context) = KINDS.any { isEnabled(ctx, it) }

    fun setEnabled(ctx: Context, kind: String, enabled: Boolean) {
        if (kind !in KINDS) return
        prefs(ctx).edit().putBoolean("enabled_$kind", enabled).remove("seen_$kind").apply()
        if (enabled) {
            // Одразу запамʼятати, що вже є на сайті, — без сповіщень.
            Thread { runCatching { check(ctx) } }.start()
        } else {
            ctx.getSystemService(NotificationManager::class.java)?.cancel(notificationId(kind))
        }
        ensureScheduled(ctx)
        runCatching { PushSetup.syncTopics(ctx) }
    }

    fun ensureScheduled(ctx: Context) {
        val js = ctx.getSystemService(JobScheduler::class.java) ?: return
        if (!anyEnabled(ctx)) {
            js.cancel(JOB_ID)
            return
        }
        // Раз на 15 хвилин (частіше Android періодичних завдань не дає). Завдання зі
        // старих версій застосунку — щогодинне — замінюємо.
        val pending = js.getPendingJob(JOB_ID)
        if (pending != null && pending.intervalMillis == PERIOD_MS) return
        val job = JobInfo.Builder(JOB_ID, ComponentName(ctx, ContentCheckJob::class.java))
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
            .setPeriodic(PERIOD_MS, 5 * 60_000L)
            .setPersisted(true)
            .build()
        js.schedule(job)
    }

    /** Один запит до сайту; false — якщо сайт недоступний (JobScheduler спробує пізніше). */
    fun check(ctx: Context): Boolean {
        if (!anyEnabled(ctx)) return true
        val body = fetch(ENDPOINT) ?: return false
        handle(ctx, body)
        return true
    }

    private class Item(
        val key: String,
        val title: String,
        val subtitle: String,
        val headline: String,
        val open: String,
        val id: String,
    )

    fun handle(ctx: Context, body: String) {
        val json = try {
            JSONObject(body)
        } catch (e: Exception) {
            return
        }
        for (kind in KINDS) {
            if (!isEnabled(ctx, kind)) continue
            val array = json.optJSONArray(kind) ?: continue
            val items = mutableListOf<Item>()
            for (i in 0 until array.length()) {
                val o = array.optJSONObject(i) ?: continue
                when (kind) {
                    "news" -> {
                        val slug = o.optString("slug")
                        if (slug.isEmpty()) continue
                        val headline = when (o.optString("kind")) {
                            "article" -> Texts.t(ctx, "Нова стаття")
                            "photo" -> Texts.t(ctx, "Нові фото")
                            else -> Texts.t(ctx, "Новина")
                        }
                        items += Item(slug, o.optString("title"), "", headline, "news", slug)
                    }
                    "videos" -> {
                        val id = o.optString("id")
                        // Іде наживо — про це окреме сповіщення; «новим відео» стане після ефіру.
                        if (id.isEmpty() || o.optBoolean("live")) continue
                        items += Item(id, o.optString("title"), "", Texts.t(ctx, "Нове відео"), "video", id)
                    }
                    "sermons" -> {
                        val id = o.opt("id")?.toString().orEmpty()
                        if (id.isEmpty()) continue
                        items += Item(id, o.optString("title"), o.optString("preacher"), Texts.t(ctx, "Нова проповідь"), "sermon", id)
                    }
                }
            }
            val p = prefs(ctx)
            val seenRaw = p.getString("seen_$kind", null)
            val keys = items.map { it.key }
            if (seenRaw == null) {
                p.edit().putString("seen_$kind", keys.joinToString("\n")).apply()
                continue
            }
            val seen = seenRaw.split('\n').filter { it.isNotEmpty() }
            val fresh = items.filter { it.key !in seen }
            if (fresh.isNotEmpty()) notify(ctx, kind, fresh)
            val merged = (keys + seen).distinct().take(MAX_SEEN)
            p.edit().putString("seen_$kind", merged.joinToString("\n")).apply()
        }
    }

    private fun notificationId(kind: String) = 7200 + KINDS.indexOf(kind) + 1

    private fun channel(ctx: Context, kind: String): Pair<String, String> = when (kind) {
        "news" -> "news" to Texts.t(ctx, "Новини, статті й фото")
        "videos" -> "videos" to Texts.t(ctx, "Нові відео")
        else -> "sermons" to Texts.t(ctx, "Нові проповіді")
    }

    private fun notify(ctx: Context, kind: String, fresh: List<Item>) {
        if (!LiveAlerts.notificationsAllowed(ctx)) return
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        val (channelId, channelName) = channel(ctx, kind)
        if (Build.VERSION.SDK_INT >= 26) {
            // Щоразу — щоб назва каналу йшла за мовою застосунку.
            nm.createNotificationChannel(NotificationChannel(channelId, channelName, NotificationManager.IMPORTANCE_DEFAULT))
        }
        val single = fresh.size == 1
        val first = fresh.first()
        val open = Intent(ctx, MainActivity::class.java)
            .setAction("ua.com.baptist.church.OPEN_$kind")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        if (single) {
            open.putExtra(LiveAlerts.EXTRA_OPEN, first.open).putExtra("id", first.id).putExtra("title", first.title)
        } else {
            open.putExtra(LiveAlerts.EXTRA_OPEN, "tab:$kind")
        }
        val content = PendingIntent.getActivity(
            ctx, notificationId(kind), open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(ctx, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(ctx).setPriority(Notification.PRIORITY_DEFAULT)
        }
        builder.setSmallIcon(R.drawable.ic_stat_audio)
            .setContentIntent(content)
            .setAutoCancel(true)
            .setColor(0xFF6D402C.toInt())
        if (single) {
            val text = if (first.subtitle.isNotEmpty()) "${first.title} — ${first.subtitle}" else first.title
            builder.setContentTitle(first.headline).setContentText(text).setStyle(Notification.BigTextStyle().bigText(text))
        } else {
            val headline = when (kind) {
                "news" -> Texts.t(ctx, "Нові публікації ({a})", "a" to fresh.size)
                "videos" -> Texts.t(ctx, "Нові відео ({a})", "a" to fresh.size)
                else -> Texts.t(ctx, "Нові проповіді ({a})", "a" to fresh.size)
            }
            val style = Notification.InboxStyle()
            fresh.take(5).forEach { style.addLine(it.title) }
            if (fresh.size > 5) style.setSummaryText(Texts.t(ctx, "і ще {a}", "a" to fresh.size - 5))
            builder.setContentTitle(headline).setContentText(first.title).setStyle(style)
        }
        nm.notify(notificationId(kind), builder.build())
    }

    private fun fetch(endpoint: String): String? = try {
        val conn = URL(endpoint).openConnection() as HttpURLConnection
        conn.connectTimeout = 8_000
        conn.readTimeout = 10_000
        conn.setRequestProperty("Accept", "application/json")
        conn.setRequestProperty("User-Agent", "VidrodzhenniaApp/1.0 (Android; content alerts)")
        try {
            if (conn.responseCode == 200) conn.inputStream.bufferedReader().use { it.readText() } else null
        } finally {
            conn.disconnect()
        }
    } catch (e: Exception) {
        null
    }
}
