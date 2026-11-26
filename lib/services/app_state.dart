import 'dart:async';

import 'package:flutter/widgets.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../i18n.dart';

/// Спільні дані застосунку: церква, фонотека, відео.
///
/// Спершу показуємо те, що лежить у кеші з минулого разу (миттєво й без
/// мережі), потім тихо підтягуємо свіже з сайту.
///
/// Списки оновлюються самі: коли застосунок знову відкривають (Flutter-двигун
/// живе довше за вікно — його тримає аудіо, тож main() удруге не виконується)
/// і кожні 10 хвилин, поки застосунок на екрані. Раніше свіже бралось лише при
/// запуску процесу, і нові проповіді не з'являлися годинами.
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  AppState(this.api);

  final Api api;

  AppConfig? config;
  SermonCatalogue? catalogue;
  VideosOverview? videos;

  String? configError;
  String? sermonsError;
  String? videosError;

  bool _refreshing = false;
  bool get refreshing => _refreshing;
  /// Коли востаннє взяли свіже з сайту — екрани з власними списками (новини)
  /// за цим знають, що й їм час оновитись.
  DateTime? get lastRefresh => _lastRefresh;
  Future<void>? _inFlight;
  DateTime? _lastRefresh;
  Timer? _timer;

  static const _foregroundEvery = Duration(minutes: 10);
  static const _staleAfter = Duration(minutes: 2);

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
    await Future.wait([
      _fromCache(api.configUrl, AppConfig.fromJson, (v) => config = v),
      _fromCache(api.sermonsUrl, SermonCatalogue.fromJson, (v) => catalogue = v),
      _fromCache(api.videosUrl, VideosOverview.fromJson, (v) => videos = v),
    ]);
    notifyListeners();
    await refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTimer();
      unawaited(refreshIfStale());
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_foregroundEvery, (_) => unawaited(refresh()));
  }

  /// Оновити, якщо востаннє брали з сайту давніше, ніж [maxAge] тому.
  Future<void> refreshIfStale({Duration maxAge = _staleAfter}) {
    final last = _lastRefresh;
    if (last != null && DateTime.now().difference(last) < maxAge) return Future.value();
    return refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fromCache<T>(String url, T Function(Map<String, dynamic>) parse, void Function(T) set) async {
    final cached = await api.cached(url);
    if (cached == null) return;
    try {
      set(parse(cached));
    } catch (_) {
      // Кеш від старішої версії — просто чекаємо свіжих даних.
    }
  }

  Future<String?> _fresh<T>(String url, T Function(Map<String, dynamic>) parse, void Function(T) set) async {
    try {
      set(parse(await api.getJson(url)));
      return null;
    } on ApiException catch (err) {
      return err.message;
    } catch (_) {
      return tr('Не вдалося прочитати відповідь сайту');
    }
  }

  /// Свіже з сайту. Якщо оновлення вже йде — чекаємо саме його (раніше потягнути
  /// список під час запуску означало миттєвий «успіх» без жодного запиту).
  Future<void> refresh() => _inFlight ??= _doRefresh().whenComplete(() => _inFlight = null);

  Future<void> _doRefresh() async {
    _refreshing = true;
    notifyListeners();
    final results = await Future.wait([
      _fresh(api.configUrl, AppConfig.fromJson, (v) => config = v),
      _fresh(api.sermonsUrl, SermonCatalogue.fromJson, (v) => catalogue = v),
      _fresh(api.videosUrl, VideosOverview.fromJson, (v) => videos = v),
    ]);
    configError = config == null ? results[0] : null;
    sermonsError = catalogue == null ? results[1] : null;
    videosError = videos == null ? results[2] : null;
    _lastRefresh = DateTime.now();
    _refreshing = false;
    notifyListeners();
  }

  /// Проповіді, нарізані з цього відео, або ж — з того самого богослужіння.
  ///
  /// Точний звʼязок знає лише імпорт з YouTube (videoId). Для решти беремо дату:
  /// з назви («Трансляція служіння 13.09.2026г.»), бо запис часто викладають
  /// уночі й дата публікації — вже наступний день; без дати в назві — день
  /// публікації або попередній.
  List<Sermon> sermonsForVideo(VideoItem video) {
    final all = catalogue?.sermons ?? const <Sermon>[];
    final exact = all.where((s) => s.videoId == video.id).toList();
    if (exact.isNotEmpty || !video.isService) return exact;
    final days = <String>{};
    final m = RegExp(r'(\d{1,2})\.(\d{1,2})\.(\d{4})').firstMatch(video.title);
    if (m != null) {
      days.add(_day(DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!))));
    } else {
      final at = video.publishedAt?.toLocal();
      if (at == null) return const [];
      days
        ..add(_day(at))
        ..add(_day(at.subtract(const Duration(days: 1))));
    }
    return all.where((s) => s.dateTime != null && days.contains(_day(s.dateTime!))).toList();
  }

  static String _day(DateTime d) => '${d.year}-${d.month}-${d.day}';

  Sermon? sermonById(int id) {
    for (final s in catalogue?.sermons ?? const <Sermon>[]) {
      if (s.id == id) return s;
    }
    return null;
  }
}
