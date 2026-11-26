package ua.com.baptist.church

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import org.json.JSONObject

/**
 * Повідомлення FCM (див. PushSetup). Сервер надсилає лише дані — застосунок сам
 * показує сповіщення тим самим кодом, що й за будильником, тож одне й те саме
 * двічі не прийде: LiveAlerts пам'ятає, про яку трансляцію вже сповістив, а
 * ContentAlerts — які записи вже бачив.
 */
class PushMessaging : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        when (data["kind"]) {
            "live" -> {
                if (!LiveAlerts.isEnabled(this)) return
                val live = data["live"]
                if (!live.isNullOrBlank()) {
                    val body = JSONObject().put("live", JSONObject(live)).toString()
                    LiveAlerts.handle(this, body)
                } else {
                    LiveAlerts.check(this)
                }
            }
            "sermons", "news", "videos" -> ContentAlerts.check(this)
        }
    }

    override fun onNewToken(token: String) {
        // Новий токен — підписки на теми треба відновити.
        PushSetup.syncTopics(this)
    }
}
