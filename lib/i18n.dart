import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'i18n_dicts.dart';

/// Мови застосунку. Українська — основна: усе, чого ще нема в словнику,
/// показується українською.
const appLangs = ['uk', 'ru', 'en'];

const appLangNames = {'uk': 'Українська', 'ru': 'Русский', 'en': 'English'};

/// Мова застосунку: вибір людини (Ще → Мова) або мова телефона.
///
/// Мова телефона — за правилом у _resolve (Україна, українська чи російська → українська,
/// решта → англійська; російська — лише вручну).
/// Вибір зберігається, а обрана мова (`app_lang_resolved`) лежить поруч для
/// Kotlin-частини: сповіщення про ефір і нові записи будуються там.
class LangService extends ChangeNotifier {
  LangService._();
  static final LangService instance = LangService._();

  static const _channel = MethodChannel('ua.com.baptist.church/lang');

  String? _choice;
  String _lang = 'uk';

  /// uk / ru / en — чим зараз говорить застосунок.
  String get lang => _lang;

  /// null — як у телефоні.
  String? get choice => _choice;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('app_lang');
      _choice = appLangs.contains(saved) ? saved : null;
    } catch (_) {
      _choice = null;
    }
    _lang = _resolve();
    await _publish();
  }

  Future<void> setChoice(String? choice) async {
    _choice = appLangs.contains(choice) ? choice : null;
    final next = _resolve();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_choice == null) {
        await prefs.remove('app_lang');
      } else {
        await prefs.setString('app_lang', _choice!);
      }
    } catch (_) {}
    if (next != _lang) {
      _lang = next;
      notifyListeners();
    }
    await _publish();
  }

  /// Мова телефона змінилась (налаштування Android) — підхопити, якщо людина не обирала сама.
  void systemLocaleChanged() {
    if (_choice != null) return;
    final next = _resolve();
    if (next == _lang) return;
    _lang = next;
    notifyListeners();
    _publish();
  }

  /// Правило власника (з 21.11.2026, як і на сайті): Україна (регіон UA), українська чи
  /// російська мова телефона — українська; будь-яка інша — англійська. Російська — лише
  /// вручну (Ще → Мова), цей вибір зберігається. До 1.0.14 російський телефон давав російську.
  String _resolve() {
    if (_choice != null) return _choice!;
    final locale = PlatformDispatcher.instance.locale;
    final code = locale.languageCode.toLowerCase();
    final region = (locale.countryCode ?? '').toUpperCase();
    if (region == 'UA' || code == 'uk' || code == 'ru') return 'uk';
    return 'en';
  }

  Future<void> _publish() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_lang_resolved', _lang);
    } catch (_) {}
    try {
      await _channel.invokeMethod('setLang', _lang);
    } catch (_) {
      // Старі збірки без каналу — не страшно: Kotlin прочитає мову з налаштувань.
    }
  }
}

/// tr('Нові проповіді') → переклад поточною мовою (або українське, коли перекладу нема).
/// Змінні: tr('Знайдено: {a}', {'a': 5}).
String tr(String text, [Map<String, Object?>? vars]) {
  final lang = LangService.instance.lang;
  var out = switch (lang) {
    'ru' => ruDict[text] ?? text,
    'en' => enDict[text] ?? text,
    _ => text,
  };
  if (vars != null) {
    vars.forEach((key, value) => out = out.replaceAll('{$key}', '$value'));
  }
  return out;
}

/// Мова для дат (intl): uk / ru / en.
String get dateLocale => LangService.instance.lang;
