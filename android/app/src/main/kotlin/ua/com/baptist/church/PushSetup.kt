package ua.com.baptist.church

import android.app.Application
import android.content.Context
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging

/**
 * Миттєві сповіщення через Firebase Cloud Messaging — коли вони налаштовані.
 *
 * Без FCM Android сам вирішує, коли будити застосунок: перевірка «чи почалась
 * трансляція» за будильником у сплячому телефоні може запізнитися на хвилини, а
 * виробники на кшталт Xiaomi й зовсім її присипляють. FCM будить одразу.
 *
 * Налаштування — з google-services.json, який власник кладе в теку з ключем
 * підпису (CHURCH_APP_KEY_DIR, див. README); збірка (app/build.gradle.kts)
 * переносить з нього чотири значення в ресурси fcm_*. Немає файла — немає й FCM:
 * застосунок працює як раніше, на будильниках. Плагін google-services не
 * використовується навмисно — з AGP 9 він не дружить, а тут потрібні лише ці
 * чотири рядки.
 *
 * Сервер шле на теми live / sermons / news / videos (lib/fcm.ts на сайті), а
 * телефон підписаний на ті самі теми, що й перемикачі «Сповіщення» в застосунку.
 * Саме повідомлення — лише сигнал «перевір зараз»: показує й не повторює вже
 * наявний код LiveAlerts / ContentAlerts.
 */
object PushSetup {
    private fun res(ctx: Context, name: String): String? {
        val id = ctx.resources.getIdentifier(name, "string", ctx.packageName)
        return if (id == 0) null else ctx.getString(id).ifBlank { null }
    }

    /** true — FCM готовий; false — у цій збірці його немає. */
    fun init(ctx: Context): Boolean {
        if (FirebaseApp.getApps(ctx).isNotEmpty()) return true
        val appId = res(ctx, "fcm_app_id") ?: return false
        val apiKey = res(ctx, "fcm_api_key") ?: return false
        val projectId = res(ctx, "fcm_project_id") ?: return false
        val senderId = res(ctx, "fcm_sender_id") ?: return false
        return try {
            FirebaseApp.initializeApp(
                ctx,
                FirebaseOptions.Builder()
                    .setApplicationId(appId)
                    .setApiKey(apiKey)
                    .setProjectId(projectId)
                    .setGcmSenderId(senderId)
                    .build(),
            )
            true
        } catch (e: Exception) {
            false
        }
    }

    /** Підписки на теми — такі самі, як перемикачі сповіщень у застосунку. */
    fun syncTopics(ctx: Context) {
        if (!init(ctx)) return
        val fm = try {
            FirebaseMessaging.getInstance()
        } catch (e: Exception) {
            return
        }
        fun set(topic: String, on: Boolean) {
            runCatching { if (on) fm.subscribeToTopic(topic) else fm.unsubscribeFromTopic(topic) }
        }
        set("live", LiveAlerts.isEnabled(ctx))
        for (kind in ContentAlerts.KINDS) set(kind, ContentAlerts.isEnabled(ctx, kind))
    }
}

/** Застосунок: FCM — до будь-якого екрана, бо повідомлення може розбудити процес і без них. */
class VidrodzhenniaApp : Application() {
    override fun onCreate() {
        super.onCreate()
        runCatching { PushSetup.init(this) }
    }
}
