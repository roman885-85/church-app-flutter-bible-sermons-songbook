import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../i18n.dart';

enum AlertsResult { enabled, denied, blocked, failed }

/// Про що можна отримувати сповіщення.
enum AlertKind {
  live('live', 'Прямий ефір'),
  news('news', 'Новини, статті й фото'),
  videos('videos', 'Нові відео'),
  sermons('sermons', 'Нові проповіді');

  const AlertKind(this.code, this._label);
  final String code;
  final String _label;

  /// Назва мовою застосунку.
  String get label => tr(_label);
}

/// Що відкрити, коли людина торкнулась сповіщення.
class AlertOpen {
  const AlertOpen(this.target, {this.id, this.title});

  /// live | sermon | video | news | tab:sermons | tab:videos | tab:news
  /// | tab:bible | tab:songbook | search (останні три — ярлики на значку)
  final String target;
  final String? id;
  final String? title;

  static AlertOpen? from(Object? raw) {
    if (raw is String) return AlertOpen(raw);
    if (raw is Map) {
      final target = raw['open'];
      if (target is! String || target.isEmpty) return null;
      return AlertOpen(target, id: raw['id'] as String?, title: raw['title'] as String?);
    }
    return null;
  }
}

/// Сповіщення (лише Android): про початок ефіру й про нове на сайті.
///
/// Перевірки живуть у Kotlin (LiveAlerts.kt, ContentAlerts.kt) — будильник і
/// JobScheduler, без Flutter у фоні. Тут — увімкнути, вимкнути й відкрити
/// потрібний екран після натиску на сповіщення.
class LiveAlertsService extends ChangeNotifier {
  static const _channel = MethodChannel('ua.com.baptist.church/live_alerts');
  static const _kSuggestDismissed = 'alerts.suggestDismissed';

  bool get supported => !kIsWeb && Platform.isAndroid;
  final Map<AlertKind, bool> _enabled = {for (final k in AlertKind.values) k: false};
  bool suggestDismissed = true;
  String _endpoint = '';

  bool get enabled => _enabled[AlertKind.live] ?? false;
  bool isEnabled(AlertKind kind) => _enabled[kind] ?? false;

  final _open = StreamController<AlertOpen>.broadcast();
  Stream<AlertOpen> get openRequests => _open.stream;

  Future<void> init() async {
    if (!supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'open') {
        final request = AlertOpen.from(call.arguments);
        if (request != null) _open.add(request);
      }
    });
    try {
      final status = await _channel.invokeMapMethod<String, dynamic>('status');
      _enabled[AlertKind.live] = status?['enabled'] == true;
      for (final kind in [AlertKind.news, AlertKind.videos, AlertKind.sermons]) {
        _enabled[kind] = status?[kind.code] == true;
      }
      final prefs = await SharedPreferences.getInstance();
      suggestDismissed = prefs.getBool(_kSuggestDismissed) ?? false;
      if (_enabled.values.any((v) => v)) await _channel.invokeMethod('ensure', {'endpoint': _endpoint});
    } catch (_) {
      // Стара збірка без каналу — просто без сповіщень.
    }
    notifyListeners();
  }

  /// Адреса /api/live з налаштувань сайту.
  void setEndpoint(String endpoint) {
    if (!supported || endpoint.isEmpty || endpoint == _endpoint) return;
    _endpoint = endpoint;
    if (enabled) unawaited(_channel.invokeMethod('ensure', {'endpoint': endpoint}).catchError((_) => null));
  }

  Future<AlertOpen?> takeLaunchAction() async {
    if (!supported) return null;
    try {
      return AlertOpen.from(await _channel.invokeMethod<Object?>('takeLaunchAction'));
    } catch (_) {
      return null;
    }
  }

  Future<AlertsResult> enable([AlertKind kind = AlertKind.live]) async {
    if (!supported) return AlertsResult.failed;
    try {
      final result = await _channel.invokeMethod<String>('enableKind', {'kind': kind.code, 'endpoint': _endpoint});
      _enabled[kind] = result == 'enabled';
      notifyListeners();
      return switch (result) {
        'enabled' => AlertsResult.enabled,
        'blocked' => AlertsResult.blocked,
        'denied' => AlertsResult.denied,
        _ => AlertsResult.failed,
      };
    } catch (_) {
      return AlertsResult.failed;
    }
  }

  Future<void> disable([AlertKind kind = AlertKind.live]) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod('disableKind', {'kind': kind.code});
    } catch (_) {}
    _enabled[kind] = false;
    notifyListeners();
  }

  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod('openSettings');
    } catch (_) {}
  }

  Future<void> dismissSuggestion() async {
    suggestDismissed = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSuggestDismissed, true);
  }
}
