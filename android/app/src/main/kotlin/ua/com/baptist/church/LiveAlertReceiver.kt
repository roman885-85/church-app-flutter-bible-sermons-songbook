package ua.com.baptist.church

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Будильник сповіщень про ефір, а також перезапуск телефона й оновлення
 * застосунку — після них Android забуває будильники, тож ставимо знову.
 */
class LiveAlertReceiver : BroadcastReceiver() {
    private companion object {
        const val CONTENT_CHECK = "ua.com.baptist.church.CONTENT_CHECK"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val ctx = context.applicationContext
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> {
                if (LiveAlerts.isEnabled(ctx)) LiveAlerts.schedule(ctx, 60_000)
                ContentAlerts.ensureScheduled(ctx)
            }
            CONTENT_CHECK -> {
                // Лише в тестовій збірці: перевірка нового з adb (з test_json або справжня).
                if (!BuildConfig.LIVE_TEST_HOOKS) return
                val pending = goAsync()
                Thread {
                    try {
                        val test = intent.getStringExtra("test_json")
                        if (test != null) ContentAlerts.handle(ctx, test) else ContentAlerts.check(ctx)
                    } finally {
                        pending.finish()
                    }
                }.start()
            }
            LiveAlerts.ACTION_CHECK -> {
                if (!LiveAlerts.isEnabled(ctx)) return
                val pending = goAsync()
                Thread {
                    try {
                        // Лише в тестовій збірці (-PliveTestHooks=true): відповідь сайту з adb.
                        val test = if (BuildConfig.LIVE_TEST_HOOKS) intent.getStringExtra("test_json") else null
                        val next = if (test != null) LiveAlerts.handle(ctx, test) else LiveAlerts.check(ctx)
                        if (LiveAlerts.isEnabled(ctx)) LiveAlerts.schedule(ctx, next)
                    } catch (e: Exception) {
                        if (LiveAlerts.isEnabled(ctx)) LiveAlerts.schedule(ctx, 5 * 60_000L)
                    } finally {
                        pending.finish()
                    }
                }.start()
            }
        }
    }
}
