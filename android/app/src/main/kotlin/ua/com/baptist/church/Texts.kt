package ua.com.baptist.church

import android.content.Context
import java.util.Locale

/**
 * Тексти сповіщень мовою застосунку.
 *
 * Мову обирає Flutter-частина (Ще → Мова) і кладе обрану в налаштування
 * (`app_lang_resolved`, файл FlutterSharedPreferences). Поки застосунок ще не
 * відкривали після оновлення — мова телефона за тим самим правилом: Україна, українська
 * чи російська — українська, решта — англійська. Ключ — українська фраза, як і в
 * словниках сайту й застосунку.
 */
object Texts {
    private val ru = mapOf(
        "Нова стаття" to "Новая статья",
        "Нові фото" to "Новые фото",
        "Новина" to "Новость",
        "Нове відео" to "Новое видео",
        "Нова проповідь" to "Новая проповедь",
        "Новини, статті й фото" to "Новости, статьи и фото",
        "Нові відео" to "Новые видео",
        "Нові проповіді" to "Новые проповеди",
        "Нові публікації ({a})" to "Новые публикации ({a})",
        "Нові відео ({a})" to "Новые видео ({a})",
        "Нові проповіді ({a})" to "Новые проповеди ({a})",
        "і ще {a}" to "и ещё {a}",
        "Пряма трансляція богослужіння" to "Прямая трансляция богослужения",
        "Прямі трансляції" to "Прямые трансляции",
        "Повідомлення, щойно почнеться трансляція богослужіння" to "Сообщение, как только начнётся трансляция богослужения",
        "Почалася пряма трансляція" to "Началась прямая трансляция",
    )

    private val en = mapOf(
        "Нова стаття" to "New article",
        "Нові фото" to "New photos",
        "Новина" to "News",
        "Нове відео" to "New video",
        "Нова проповідь" to "New sermon",
        "Новини, статті й фото" to "News, articles and photos",
        "Нові відео" to "New videos",
        "Нові проповіді" to "New sermons",
        "Нові публікації ({a})" to "New posts ({a})",
        "Нові відео ({a})" to "New videos ({a})",
        "Нові проповіді ({a})" to "New sermons ({a})",
        "і ще {a}" to "and {a} more",
        "Пряма трансляція богослужіння" to "Live broadcast of the service",
        "Прямі трансляції" to "Live broadcasts",
        "Повідомлення, щойно почнеться трансляція богослужіння" to "A notification as soon as a service broadcast begins",
        "Почалася пряма трансляція" to "The live broadcast has started",
    )

    fun lang(context: Context): String {
        val saved = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString("flutter.app_lang_resolved", null)
        if (saved == "uk" || saved == "ru" || saved == "en") return saved
        // Як у застосунку (з 1.0.14): Україна, українська чи російська — uk, решта — en;
        // російська — лише вручну у Flutter-частині (тоді вона вже в app_lang_resolved).
        val locale = Locale.getDefault()
        return when {
            locale.country.equals("UA", ignoreCase = true) || locale.language == "uk" || locale.language == "ru" -> "uk"
            else -> "en"
        }
    }

    /** t(ctx, "Нові відео ({a})", "a" to 3) → «New videos (3)». */
    fun t(context: Context, uk: String, vararg vars: Pair<String, Any>): String {
        var out = when (lang(context)) {
            "ru" -> ru[uk] ?: uk
            "en" -> en[uk] ?: uk
            else -> uk
        }
        for ((key, value) in vars) out = out.replace("{$key}", value.toString())
        return out
    }
}
