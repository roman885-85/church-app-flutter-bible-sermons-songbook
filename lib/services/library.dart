import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/models.dart';

/// Усе, що людина зберегла в застосунку: обране, історію, де зупинилась,
/// завантажені для офлайну проповіді. Без реєстрації — лише на телефоні.
class LibraryService extends ChangeNotifier {
  static const _kFavorites = 'favorites.v1';
  static const _kHistory = 'history.v1';
  static const _kPositions = 'positions.v1';
  static const _kDownloads = 'downloads.v1';
  static const _kBible = 'bible.v1';
  static const _kTheme = 'theme.v1';

  late SharedPreferences _prefs;
  Directory? _downloadDir;

  final Map<int, Sermon> _favorites = {};
  final List<(Sermon, DateTime)> _history = [];
  final Map<int, int> _positions = {};
  final Map<int, Sermon> _downloads = {};

  /// Поточні завантаження: id → частка від 0 до 1.
  final Map<int, ValueNotifier<double>> downloading = {};

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    for (final raw in _prefs.getStringList(_kFavorites) ?? const <String>[]) {
      final s = _decodeSermon(raw);
      if (s != null) _favorites[s.id] = s;
    }
    for (final raw in _prefs.getStringList(_kHistory) ?? const <String>[]) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        _history.add((Sermon.fromJson(Map<String, dynamic>.from(m['sermon'] as Map)), DateTime.parse(m['at'] as String)));
      } catch (_) {}
    }
    final positions = _prefs.getString(_kPositions);
    if (positions != null) {
      try {
        (jsonDecode(positions) as Map).forEach((k, v) => _positions[int.parse('$k')] = (v as num).toInt());
      } catch (_) {}
    }
    final dir = await _dir();
    for (final raw in _prefs.getStringList(_kDownloads) ?? const <String>[]) {
      final s = _decodeSermon(raw);
      if (s != null && File('${dir.path}/${s.id}.mp3').existsSync()) _downloads[s.id] = s;
    }
  }

  Sermon? _decodeSermon(String raw) {
    try {
      return Sermon.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _dir() async {
    if (_downloadDir != null) return _downloadDir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/sermons');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _downloadDir = dir;
  }

  // ── Тема ──
  String get theme => _prefs.getString(_kTheme) ?? 'system';
  Future<void> setTheme(String value) async {
    await _prefs.setString(_kTheme, value);
    notifyListeners();
  }

  // ── Обране ──
  List<Sermon> get favorites => _favorites.values.toList().reversed.toList();
  bool isFavorite(int id) => _favorites.containsKey(id);
  Future<void> toggleFavorite(Sermon sermon) async {
    if (_favorites.remove(sermon.id) == null) _favorites[sermon.id] = sermon;
    await _prefs.setStringList(_kFavorites, _favorites.values.map((s) => jsonEncode(s.toJson())).toList());
    notifyListeners();
  }

  // ── Історія ──
  List<Sermon> get history => _history.map((e) => e.$1).toList();
  Future<void> recordPlayed(Sermon sermon) async {
    _history.removeWhere((e) => e.$1.id == sermon.id);
    _history.insert(0, (sermon, DateTime.now()));
    if (_history.length > 60) _history.removeRange(60, _history.length);
    await _prefs.setStringList(
      _kHistory,
      _history.map((e) => jsonEncode({'sermon': e.$1.toJson(), 'at': e.$2.toIso8601String()})).toList(),
    );
    notifyListeners();
  }

  // ── Де зупинились ──
  Duration positionOf(int id) => Duration(seconds: _positions[id] ?? 0);
  Future<void> savePosition(int id, Duration position, {Duration? total, bool notify = false}) async {
    var seconds = position.inSeconds;
    // Дослухали до кінця — наступного разу з початку.
    if (total != null && total.inSeconds > 0 && total.inSeconds - seconds < 30) seconds = 0;
    if (seconds <= 5) {
      _positions.remove(id);
    } else {
      _positions[id] = seconds;
    }
    await _prefs.setString(_kPositions, jsonEncode(_positions.map((k, v) => MapEntry('$k', v))));
    // Під час гри — тихо (кожні 10 с); на паузі — хай списки й кнопка «Продовжити» оновляться.
    if (notify) notifyListeners();
  }

  /// Скільки прослухано (0..1) — для смужки в списку.
  double progressOf(Sermon sermon) {
    final seconds = _positions[sermon.id] ?? 0;
    if (seconds <= 0 || sermon.duration <= 0) return 0;
    return (seconds / sermon.duration).clamp(0, 1).toDouble();
  }

  // ── Завантаження для офлайну ──
  List<Sermon> get downloads => _downloads.values.toList();
  bool isDownloaded(int id) => _downloads.containsKey(id);

  Future<String?> localPath(int id) async {
    if (!_downloads.containsKey(id)) return null;
    final file = File('${(await _dir()).path}/$id.mp3');
    return await file.exists() ? file.path : null;
  }

  Future<int> downloadsSize() async {
    final dir = await _dir();
    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.mp3')) total += await entity.length();
    }
    return total;
  }

  Future<void> download(Sermon sermon) async {
    if (_downloads.containsKey(sermon.id) || downloading.containsKey(sermon.id)) return;
    final progress = downloading[sermon.id] = ValueNotifier<double>(0);
    notifyListeners();
    final dir = await _dir();
    final part = File('${dir.path}/${sermon.id}.mp3.part');
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(sermon.audioUrl)));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final total = res.contentLength ?? 0;
      var received = 0;
      final sink = part.openWrite();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) progress.value = received / total;
      }
      await sink.close();
      await part.rename('${dir.path}/${sermon.id}.mp3');
      _downloads[sermon.id] = sermon;
      await _saveDownloads();
    } catch (_) {
      if (await part.exists()) await part.delete();
      rethrow;
    } finally {
      client.close();
      downloading.remove(sermon.id)?.dispose();
      notifyListeners();
    }
  }

  Future<void> deleteDownload(int id) async {
    final file = File('${(await _dir()).path}/$id.mp3');
    if (await file.exists()) await file.delete();
    _downloads.remove(id);
    await _saveDownloads();
    notifyListeners();
  }

  Future<void> _saveDownloads() =>
      _prefs.setStringList(_kDownloads, _downloads.values.map((s) => jsonEncode(s.toJson())).toList());

  // ── Біблія: де читали ──
  (String translation, int book, int chapter)? get lastReading {
    final raw = _prefs.getString(_kBible);
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return ('${m['t']}', (m['b'] as num).toInt(), (m['c'] as num).toInt());
    } catch (_) {
      return null;
    }
  }

  Future<void> saveReading(String translation, int book, int chapter) =>
      _prefs.setString(_kBible, jsonEncode({'t': translation, 'b': book, 'c': chapter}));

  double get bibleFont => _prefs.getDouble('bible.font') ?? 18;
  Future<void> setBibleFont(double value) => _prefs.setDouble('bible.font', value);

  /// Аудіо-Біблія: після глави — одразу наступна, аж поки не зупинять.
  bool get bibleContinuous => _prefs.getBool('bible.continuous') ?? true;
  Future<void> setBibleContinuous(bool value) async {
    await _prefs.setBool('bible.continuous', value);
    notifyListeners();
  }

  /// Пісенник: розмір тексту пісні, розгорнуті ноти, останній збірник.
  double get songFont => _prefs.getDouble('song.font') ?? 20;
  Future<void> setSongFont(double value) => _prefs.setDouble('song.font', value);
  bool? get songNotesOpen => _prefs.getBool('song.notes');
  Future<void> setSongNotesOpen(bool value) => _prefs.setBool('song.notes', value);
  String? get songBook => _prefs.getString('song.book');
  Future<void> setSongBook(String value) => _prefs.setString('song.book', value);

  String? get bibleParallel => _prefs.getString('bible.parallel');
  Future<void> setBibleParallel(String? code) =>
      code == null ? _prefs.remove('bible.parallel') : _prefs.setString('bible.parallel', code);
}
