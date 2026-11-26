import 'dart:async';

import 'package:flutter/widgets.dart';

import '../api/api.dart';
import '../api/models.dart';

/// Прямий ефір — так само, як на сайті: питаємо /api/live, а він сам каже, коли
/// спитати знову (часто під час богослужіння, рідко решту тижня). Коли
/// застосунок згорнутий, не питаємо зовсім, а повернувшись — одразу.
class LiveService extends ChangeNotifier with WidgetsBindingObserver {
  LiveService(this._api);

  final Api _api;
  LiveSettings? _settings;
  LiveStatus? status;
  Timer? _timer;
  bool _busy = false;
  bool _foreground = true;

  bool get isLive => status?.isLive ?? false;
  LiveSettings? get settings => _settings;

  void start() => WidgetsBinding.instance.addObserver(this);

  void attach(LiveSettings settings) {
    final first = _settings == null;
    _settings = settings;
    if (!settings.enabled) {
      _timer?.cancel();
      status = null;
      return;
    }
    if (first) unawaited(poll());
  }

  Future<void> poll() async {
    if (_busy || !_foreground || !(_settings?.enabled ?? false)) return;
    _busy = true;
    _timer?.cancel();
    var next = const Duration(minutes: 1);
    try {
      final fresh = await _api.live(_settings?.endpoint ?? '');
      final changed = fresh.videoId != status?.videoId || status == null;
      status = fresh;
      next = fresh.nextIn;
      if (changed) notifyListeners();
    } catch (_) {
      next = const Duration(seconds: 45);
    } finally {
      _busy = false;
    }
    if (next < const Duration(seconds: 15)) next = const Duration(seconds: 15);
    if (next > const Duration(minutes: 10)) next = const Duration(minutes: 10);
    if (_foreground) _timer = Timer(next, poll);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      unawaited(poll());
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _foreground = false;
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }
}
