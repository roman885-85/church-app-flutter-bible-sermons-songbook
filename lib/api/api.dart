import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import '../i18n.dart';

/// Звертання до сайту церкви.
///
/// Кожна вдала відповідь лягає на диск: без мережі застосунок показує те, що
/// бачив востаннє, замість порожнього екрана. Прямий ефір не кешується — там
/// важлива саме мить.
class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class Api {
  Api({http.Client? client}) : _client = client ?? http.Client();

  static const siteUrl = 'https://baptist.com.ua';
  static const base = '$siteUrl/api/app/v1';
  static const _headers = {'Accept': 'application/json', 'User-Agent': 'VidrodzhenniaApp/1.0 (Flutter)'};

  final http.Client _client;
  Directory? _cacheDir;

  Future<Directory> _dir() async {
    if (_cacheDir != null) return _cacheDir!;
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/api-cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _cacheDir = dir;
  }

  /// Коротке стійке ім'я файла для адреси (FNV-1a, 64 біти).
  static String _key(String url) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(url)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toUnsigned(64).toRadixString(16);
  }

  Future<Map<String, dynamic>?> _readCache(String url) async {
    try {
      final file = File('${(await _dir()).path}/${_key(url)}.json');
      if (!await file.exists()) return null;
      return Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(String url, String body) async {
    try {
      final dir = await _dir();
      final tmp = File('${dir.path}/${_key(url)}.tmp');
      await tmp.writeAsString(body, flush: true);
      await tmp.rename('${dir.path}/${_key(url)}.json');
    } catch (_) {
      // Кеш — зручність, не обов'язок.
    }
  }

  Future<Map<String, dynamic>> getJson(String url, {bool cache = true, Duration timeout = const Duration(seconds: 20)}) async {
    try {
      final res = await _client.get(Uri.parse(url), headers: _headers).timeout(timeout);
      if (res.statusCode == 200) {
        final body = utf8.decode(res.bodyBytes);
        final data = Map<String, dynamic>.from(jsonDecode(body) as Map);
        if (cache) unawaited(_writeCache(url, body));
        return data;
      }
      if (res.statusCode == 503) throw ApiException(tr('Сайт зараз оновлюється — спробуйте за хвилину'));
      if (res.statusCode == 404) throw ApiException(tr('Не знайдено'));
      throw ApiException(tr('Сайт відповів помилкою {a}', {'a': res.statusCode}));
    } catch (err) {
      if (cache) {
        final cached = await _readCache(url);
        if (cached != null) return cached;
      }
      if (err is ApiException) rethrow;
      throw ApiException(tr('Немає з\'єднання з сайтом. Перевірте інтернет і спробуйте ще раз.'));
    }
  }

  /// Те, що лежить у кеші, — щоб показати одразу, поки йде свіжий запит.
  Future<Map<String, dynamic>?> cached(String url) => _readCache(url);

  static String _q(String v) => Uri.encodeQueryComponent(v);

  /// Налаштування — мовою застосунку: назви, розклад, вірш дня перекладає сайт.
  String get configUrl => LangService.instance.lang == 'uk' ? '$base/config' : '$base/config?lang=${LangService.instance.lang}';
  String get sermonsUrl => '$base/sermons';
  String get videosUrl => '$base/videos';
  String get bibleUrl => '$base/bible';
  String sheetMusicUrl({String q = '', String collection = '', int page = 1}) =>
      '$base/sheet-music?page=$page&limit=48'
      '${q.isEmpty ? '' : '&q=${_q(q)}'}'
      '${collection.isEmpty ? '' : '&collection=${_q(collection)}'}';
  String newsUrl(String section) => '$base/news?section=$section';

  Future<AppConfig> config() async => AppConfig.fromJson(await getJson(configUrl));
  Future<SermonCatalogue> sermons() async => SermonCatalogue.fromJson(await getJson(sermonsUrl));
  Future<SermonDetail> sermon(int id) async => SermonDetail.fromJson(await getJson('$base/sermons/$id'));
  Future<VideosOverview> videos() async => VideosOverview.fromJson(await getJson(videosUrl));

  /// Ноти з розділу сайту: сторінками, з пошуком і збірками.
  Future<SheetMusicPage> sheetMusic({String q = '', String collection = '', int page = 1}) async =>
      SheetMusicPage.fromJson(await getJson(sheetMusicUrl(q: q, collection: collection, page: page), cache: q.isEmpty));
  Future<CollectionVideos> collection(String kind, String slug) async =>
      CollectionVideos.fromJson(await getJson('$base/videos/$kind/${Uri.encodeComponent(slug)}'));

  Future<LiveStatus> live(String endpoint) async {
    final url = endpoint.isNotEmpty ? endpoint : '$siteUrl/api/live';
    return LiveStatus.fromJson(await getJson(url, cache: false, timeout: const Duration(seconds: 15)));
  }

  Future<List<NewsItem>> news(String section) async {
    final data = await getJson(newsUrl(section));
    return (data['items'] is List ? data['items'] as List : const [])
        .whereType<Map>()
        .map((m) => NewsItem.fromJson(Map<String, dynamic>.from(m)))
        .where((n) => n.slug.isNotEmpty)
        .toList();
  }

  Future<NewsArticle> article(String slug) async => NewsArticle.fromJson(await getJson('$base/news/${Uri.encodeComponent(slug)}'));

  /// Новини, статті й фото для загального пошуку. Пісні, проповіді й відео
  /// застосунок шукає у своїх даних — тут лише те, чого на телефоні немає.
  Future<List<NewsItem>> searchNews(String query) async {
    final data = await getJson('$base/search?q=${_q(query)}&limit=15', cache: false, timeout: const Duration(seconds: 12));
    return (data['news'] is List ? data['news'] as List : const [])
        .whereType<Map>()
        .map((m) => NewsItem.fromJson(Map<String, dynamic>.from(m)))
        .where((n) => n.slug.isNotEmpty)
        .toList();
  }

  Future<BibleInfo> bible() async => BibleInfo.fromJson(await getJson(bibleUrl));

  Future<List<BibleBook>> books(String translation) async {
    final data = await getJson('$base/bible/${Uri.encodeComponent(translation)}');
    return (data['books'] is List ? data['books'] as List : const [])
        .whereType<Map>()
        .map((m) => BibleBook.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<BibleChapter> chapter(String translation, int bookNr, int chapter, {String? parallel, bool commentaries = false}) async {
    final params = [
      if (parallel != null && parallel.isNotEmpty && parallel != translation) 'parallel=${_q(parallel)}',
      if (commentaries) 'commentaries=1',
    ];
    final query = params.isEmpty ? '' : '?${params.join('&')}';
    return BibleChapter.fromJson(await getJson('$base/bible/${Uri.encodeComponent(translation)}/$bookNr/$chapter$query'));
  }

  Future<List<BibleHit>> searchBible(String query, String translation) async {
    final data = await getJson('$base/bible/search?q=${_q(query)}&t=${_q(translation)}', cache: false);
    return (data['hits'] is List ? data['hits'] as List : const [])
        .whereType<Map>()
        .map((m) => BibleHit(
              bookNr: (m['bookNr'] as num?)?.toInt() ?? 0,
              bookName: '${m['bookName'] ?? ''}',
              chapter: (m['chapter'] as num?)?.toInt() ?? 0,
              verse: (m['verse'] as num?)?.toInt() ?? 0,
              text: '${m['text'] ?? ''}',
            ))
        .toList();
  }

  Future<List<DictionaryHit>> dictionary(String endpoint, String word) async {
    final url = '${endpoint.isNotEmpty ? endpoint : '$siteUrl/api/bible/dictionary'}?q=${_q(word)}';
    final data = await getJson(url);
    return (data['hits'] is List ? data['hits'] as List : const [])
        .whereType<Map>()
        .map((m) => DictionaryHit(
              dictionary: '${m['dictTitle'] ?? ''}',
              topic: '${m['topic'] ?? ''}',
              definition: '${m['definition'] ?? ''}',
            ))
        .toList();
  }
}
