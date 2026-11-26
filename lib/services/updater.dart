import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api.dart';
import '../i18n.dart';

class UpdateInfo {
  UpdateInfo({required this.version, required this.notes, this.publishedAt, this.size, this.sha256, this.downloadUrl});

  final String version;
  final String notes;
  final DateTime? publishedAt;
  final int? size;
  final String? sha256;
  final String? downloadUrl;
}

enum UpdatePhase { idle, downloading, installing, failed }

/// Оновлення застосунку з релізів відкритого репозиторію на GitHub.
///
/// Спершу питаємо GitHub напряму (`releases/latest` репозиторію [repo]): без ключа,
/// без посередників. Якщо GitHub не відповів (немає зв'язку з ним, вичерпано
/// безкоштовну межу запитів з цієї мережі) — запасна дорога: сайт церкви
/// (/api/app/v1/update), який бере ті самі релізи. Так воно працювало до 1.0.15, тож
/// сайт лишився запасним каналом для всіх старих копій. На Android файл
/// завантажується й відкривається встановлювач (Android завжди просить людину
/// підтвердити). На iPhone так не можна — там лише повідомляємо.
class UpdateService extends ChangeNotifier {
  static const _kPostponed = 'update.postponed';

  /// Репозиторій, з якого беруться оновлення. Свою збірку (форк) можна спрямувати
  /// на свій: `flutter build apk --dart-define=UPDATE_REPO=власник/репозиторій`.
  static const repo = String.fromEnvironment('UPDATE_REPO', defaultValue: 'roman885-85/church-app-flutter-bible-sermons-songbook');

  /// Адреса API GitHub (змінюється лише в перевірках на комп'ютері розробника).
  static const githubApi = String.fromEnvironment('UPDATE_API', defaultValue: 'https://api.github.com');

  String currentVersion = '';
  String buildNumber = '';
  UpdateInfo? available;

  UpdatePhase phase = UpdatePhase.idle;
  double progress = 0;
  String? error;
  StreamSubscription<OtaEvent>? _ota;

  bool get canInstall => Platform.isAndroid && available?.downloadUrl != null;

  Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      currentVersion = info.version;
      buildNumber = info.buildNumber;
    } catch (_) {}
  }

  /// Перевірити оновлення. Запит крихітний, тож — щоразу при запуску: обмеження
  /// «раз на кілька годин» ховало вже знайдене оновлення після перезапуску.
  /// Набридливість стримує «Пізніше» (див. [shouldOffer]).
  Future<UpdateInfo?> check() async {
    if (currentVersion.isEmpty) await init();
    UpdateInfo? latest;
    try {
      latest = await _checkGithub();
    } catch (_) {
      // GitHub недоступний — запасна дорога через сайт (кине, якщо й сайт мовчить).
      latest = await _checkSite();
    }
    available = latest;
    // Попередня спроба (скасоване встановлення, збій) не має блокувати нову.
    if (phase != UpdatePhase.downloading) {
      phase = UpdatePhase.idle;
      error = null;
    }
    notifyListeners();
    return available;
  }

  /// GitHub: останній (не чернетка й не «pre-release») випуск репозиторію [repo].
  Future<UpdateInfo?> _checkGithub() async {
    final uri = Uri.parse('$githubApi/repos/$repo/releases/latest');
    final res = await http.get(uri, headers: const {
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'VidrodzhenniaApp-updater',
    }).timeout(const Duration(seconds: 15));
    if (res.statusCode == 404) return null; // випусків ще немає
    if (res.statusCode != 200) throw HttpException('GitHub ${res.statusCode}');
    return parseGithubRelease(jsonDecode(utf8.decode(res.bodyBytes)), currentVersion);
  }

  /// Розбір відповіді GitHub `releases/latest`; [current] — версія, що стоїть на телефоні.
  /// Повертає null, коли новішого немає (або в релізі немає .apk). Окремо від мережі — щоб перевіряти тестом.
  @visibleForTesting
  static UpdateInfo? parseGithubRelease(dynamic data, String current) {
    if (data is! Map) throw const FormatException('release');
    final version = parseVersion('${data['tag_name'] ?? ''}');
    if (version == null) throw const FormatException('tag');
    final installed = parseVersion(current);
    if (installed != null && compareVersions(version, installed) <= 0) return null;
    Map? apk;
    final assets = data['assets'];
    if (assets is List) {
      for (final a in assets) {
        if (a is Map && '${a['name'] ?? ''}'.toLowerCase().endsWith('.apk') && (a['state'] ?? 'uploaded') == 'uploaded') {
          apk = a;
          break;
        }
      }
    }
    final url = apk == null ? null : '${apk['browser_download_url'] ?? ''}';
    if (apk == null || url == null || !url.startsWith('https://')) return null;
    final digest = '${apk['digest'] ?? ''}';
    return UpdateInfo(
      version: version.join('.'),
      notes: '${data['body'] ?? ''}'.trim(),
      publishedAt: DateTime.tryParse('${data['published_at'] ?? ''}'),
      size: apk['size'] is num ? (apk['size'] as num).toInt() : null,
      sha256: RegExp(r'^sha256:[0-9a-fA-F]{64}$').hasMatch(digest) ? digest.substring(7).toLowerCase() : null,
      downloadUrl: url,
    );
  }

  /// «1.0.15», «v1.0.15», «app-v1.0.15» → [1, 0, 15]; сміття → null.
  @visibleForTesting
  static List<int>? parseVersion(String value) {
    final m = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(value);
    return m == null ? null : [int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)];
  }

  @visibleForTesting
  static int compareVersions(List<int> a, List<int> b) {
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] - b[i];
    }
    return 0;
  }

  /// Запасна дорога: сайт церкви бере ті самі релізи й сам порівнює з нашою версією.
  Future<UpdateInfo?> _checkSite() async {
    final platform = Platform.isIOS ? 'ios' : 'android';
    final uri = Uri.parse('${Api.base}/update?platform=$platform&version=${Uri.encodeQueryComponent(currentVersion)}');
    final res = await http.get(uri, headers: const {'Accept': 'application/json'}).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final latest = data['latest'];
    if (data['updateAvailable'] == true && latest is Map) {
      return UpdateInfo(
        version: '${latest['version'] ?? ''}',
        notes: '${latest['notes'] ?? ''}'.trim(),
        publishedAt: DateTime.tryParse('${latest['publishedAt'] ?? ''}'),
        size: latest['size'] is num ? (latest['size'] as num).toInt() : null,
        sha256: latest['sha256'] is String && (latest['sha256'] as String).length == 64 ? latest['sha256'] as String : null,
        downloadUrl: latest['downloadUrl'] is String ? latest['downloadUrl'] as String : null,
      );
    }
    return null;
  }

  /// Чи варто показати пропозицію зараз: «Пізніше» відкладає її на 12 годин.
  Future<bool> shouldOffer(UpdateInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPostponed);
    if (raw == null) return true;
    final parts = raw.split('|');
    if (parts.length != 2 || parts[0] != info.version) return true;
    final at = int.tryParse(parts[1]) ?? 0;
    return DateTime.now().millisecondsSinceEpoch - at > const Duration(hours: 12).inMilliseconds;
  }

  Future<void> postpone(UpdateInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPostponed, '${info.version}|${DateTime.now().millisecondsSinceEpoch}');
  }

  void install() {
    final info = available;
    if (info?.downloadUrl == null || !Platform.isAndroid) return;
    if (phase == UpdatePhase.downloading) return;
    phase = UpdatePhase.downloading;
    progress = 0;
    error = null;
    notifyListeners();
    _ota?.cancel();
    try {
      _ota = OtaUpdate()
          .execute(
            info!.downloadUrl!,
            destinationFilename: 'vidrodzhennia-${info.version}.apk',
            sha256checksum: info.sha256,
          )
          .listen(_onEvent, onError: (Object err) => _fail(tr('Не вдалося завантажити оновлення')));
    } catch (err) {
      _fail(tr('Не вдалося почати оновлення'));
    }
  }

  void _onEvent(OtaEvent event) {
    switch (event.status) {
      case OtaStatus.DOWNLOADING:
        progress = (double.tryParse(event.value ?? '') ?? 0) / 100;
        phase = UpdatePhase.downloading;
      case OtaStatus.INSTALLING:
      case OtaStatus.INSTALLATION_DONE:
        phase = UpdatePhase.installing;
        progress = 1;
      case OtaStatus.ALREADY_RUNNING_ERROR:
        phase = UpdatePhase.downloading;
      case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
        _fail(tr('Дозвольте застосунку встановлювати оновлення (Налаштування → «Встановлення невідомих застосунків») і спробуйте ще раз.'));
        return;
      case OtaStatus.CHECKSUM_ERROR:
        _fail(tr('Файл оновлення пошкодився під час завантаження. Спробуйте ще раз.'));
        return;
      case OtaStatus.CANCELED:
        phase = UpdatePhase.idle;
      case OtaStatus.DOWNLOAD_ERROR:
      case OtaStatus.INSTALLATION_ERROR:
      case OtaStatus.INTERNAL_ERROR:
        _fail(tr('Оновлення не вдалося. Перевірте інтернет і спробуйте ще раз.'));
        return;
    }
    notifyListeners();
  }

  void _fail(String message) {
    phase = UpdatePhase.failed;
    error = message;
    notifyListeners();
  }

  Future<void> cancel() async {
    await _ota?.cancel();
    try {
      await OtaUpdate().cancel();
    } catch (_) {}
    phase = UpdatePhase.idle;
    notifyListeners();
  }
}
