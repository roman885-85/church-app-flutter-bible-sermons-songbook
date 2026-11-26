import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../api/api.dart';
import '../api/songbook_models.dart';
import '../i18n.dart';

/// Пісенник у телефоні.
///
/// Збірник завантажується цілком один раз і лежить на телефоні: у церкві
/// зв'язок буває поганий саме тоді, коли треба швидко знайти пісню. Коли на
/// сайті щось змінилось (інша дата оновлення збірника), свіжа копія тихо
/// підтягується фоном, а до того працює та, що є.
class SongbookService extends ChangeNotifier {
  SongbookService(this._api);

  final Api _api;

  SongbookInfo? info;
  String? infoError;

  final Map<String, List<Song>> _books = {};
  final Map<String, String> _bookStamp = {};
  String? loadingBook;
  /// Частка завантаженого, якщо сайт назвав розмір; інакше null (смуга «біжить»).
  double? progress;
  /// Скільки вже завантажено — показується, коли розміру не знаємо (стиснена відповідь).
  int downloadedBytes = 0;
  String? bookError;

  List<Song>? songsOf(String code) => _books[code];

  Future<File> _file(String code, {String ext = 'json'}) async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/songbook');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/$code.$ext');
  }

  Future<void> loadInfo() async {
    final url = '${Api.base}/songbook';
    final cached = await _api.cached(url);
    if (cached != null && info == null) {
      info = SongbookInfo.fromJson(cached);
      notifyListeners();
    }
    try {
      info = SongbookInfo.fromJson(await _api.getJson(url));
      infoError = null;
    } catch (err) {
      if (info == null) infoError = err.toString();
    }
    notifyListeners();
  }

  String? get defaultBookCode => info?.defaultBook ?? info?.books.firstOrNull?.code;

  /// Збірник на екран: з телефона, якщо є; інакше — з сайту з показом поступу.
  Future<void> openBook(String code) async {
    if (_books.containsKey(code)) {
      unawaited(_refreshIfStale(code));
      return;
    }
    final local = await _file(code);
    if (await local.exists()) {
      try {
        final parsed = await compute(_parseBook, await local.readAsString());
        _books[code] = parsed.songs;
        _bookStamp[code] = parsed.updatedAt;
        notifyListeners();
        unawaited(_refreshIfStale(code));
        return;
      } catch (_) {
        // Зіпсований файл — завантажимо заново.
      }
    }
    await _download(code);
  }

  Future<void> _refreshIfStale(String code) async {
    if (info == null) await loadInfo();
    final remote = info?.books.where((b) => b.code == code).firstOrNull?.updatedAt;
    if (remote == null || remote.isEmpty || remote == _bookStamp[code]) return;
    await _download(code, quiet: true);
  }

  Future<void> _download(String code, {bool quiet = false}) async {
    if (loadingBook == code) return;
    loadingBook = code;
    progress = null;
    downloadedBytes = 0;
    bookError = null;
    if (!quiet) notifyListeners();
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse('${Api.base}/songbook/${Uri.encodeComponent(code)}?full=1'))
        ..headers['Accept'] = 'application/json';
      final response = await client.send(request).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw Exception(tr('сайт відповів {a}', {'a': response.statusCode}));
      final total = response.contentLength ?? 0;
      final bytes = <int>[];
      var lastNotified = 0;
      await for (final chunk in response.stream.timeout(const Duration(seconds: 60))) {
        bytes.addAll(chunk);
        if (quiet) continue;
        downloadedBytes = bytes.length;
        if (total > 0) progress = bytes.length / total;
        // Не частіше, ніж на кожні ~100 КБ: тисяча перебудов екрана на 3 МБ ні до чого.
        if (bytes.length - lastNotified > 100000) {
          lastNotified = bytes.length;
          notifyListeners();
        }
      }
      final body = utf8.decode(bytes);
      final parsed = await compute(_parseBook, body);
      if (parsed.songs.isEmpty) throw Exception(tr('у збірнику немає пісень'));
      final file = await _file(code);
      final tmp = await _file(code, ext: 'tmp');
      await tmp.writeAsString(body, flush: true);
      await tmp.rename(file.path);
      _books[code] = parsed.songs;
      _bookStamp[code] = parsed.updatedAt;
    } catch (err) {
      if (!quiet) bookError = tr('Не вдалося завантажити пісенник. Перевірте інтернет і спробуйте ще раз.');
    } finally {
      client.close();
      loadingBook = null;
      progress = null;
      notifyListeners();
    }
  }

  Future<void> retry(String code) => _download(code);

  /// Пошук: число — номер; слова — кожне в назві чи тексті; спершу збіги в назві.
  List<Song> search(String code, String query) {
    final songs = _books[code] ?? const <Song>[];
    final q = query.trim();
    if (q.isEmpty) return songs;
    final number = int.tryParse(q);
    if (number != null) {
      final exact = songs.where((s) => s.number == number).toList();
      final prefix = songs.where((s) => s.number != number && s.number.toString().startsWith(q)).take(30);
      return [...exact, ...prefix];
    }
    final words = foldSongText(q).split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return songs;
    final inTitle = <Song>[];
    final inText = <Song>[];
    for (final song in songs) {
      if (words.every(song.titleFold.contains)) {
        inTitle.add(song);
      } else if (words.every(song.textFold.contains)) {
        inText.add(song);
      }
    }
    final joined = words.join(' ');
    inTitle.sort((a, b) {
      final sa = a.titleFold.startsWith(joined) ? 0 : 1;
      final sb = b.titleFold.startsWith(joined) ? 0 : 1;
      return sa != sb ? sa - sb : a.number - b.number;
    });
    return [...inTitle, ...inText];
  }
}

class _ParsedBook {
  _ParsedBook(this.songs, this.updatedAt);
  final List<Song> songs;
  final String updatedAt;
}

_ParsedBook _parseBook(String body) {
  final data = Map<String, dynamic>.from(jsonDecode(body) as Map);
  final songs = (data['songs'] is List ? data['songs'] as List : const [])
      .whereType<Map>()
      .map((m) => Song.fromJson(Map<String, dynamic>.from(m)))
      .where((s) => s.number > 0 && s.title.isNotEmpty)
      .toList()
    ..sort((a, b) => a.number - b.number);
  // Згорнутий для пошуку текст рахуємо тут, у фоновому потоці: інакше перший
  // пошук на телефоні помітно «задумається» над трьома тисячами пісень.
  for (final song in songs) {
    song.titleFold;
    song.textFold;
  }
  return _ParsedBook(songs, data['updatedAt']?.toString() ?? '');
}
