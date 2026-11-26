import '../i18n.dart';
// Дані з сайту церкви (/api/app/v1/*) — ті самі поля, що віддає сайт.
// Розбір терплячий: відсутнє поле — порожнє значення, а не падіння застосунку.

String _s(Object? v) => v == null ? '' : v.toString();
int _i(Object? v) => v is num ? v.toInt() : int.tryParse(_s(v)) ?? 0;
bool _b(Object? v) => v == true || v == 1 || v == '1' || v == 'true';
String? _n(Object? v) {
  final s = _s(v).trim();
  return s.isEmpty ? null : s;
}

List<T> _list<T>(Object? v, T Function(Map<String, dynamic>) parse) {
  if (v is! List) return const [];
  return v.whereType<Map>().map((m) => parse(Map<String, dynamic>.from(m))).toList();
}

List<String> _strings(Object? v) => v is List ? v.map(_s).where((s) => s.isNotEmpty).toList() : const [];

// ── Церква ─────────────────────────────────────────────────────────────────

class LiveSettings {
  LiveSettings({
    required this.enabled,
    required this.endpoint,
    required this.channelUrl,
    required this.badgeText,
    required this.heading,
    required this.description,
    this.logo,
  });

  final bool enabled;
  final String endpoint;
  final String? channelUrl;
  final String badgeText;
  final String heading;
  final String description;
  final String? logo;

  factory LiveSettings.fromJson(Map<String, dynamic> j) => LiveSettings(
        enabled: j['enabled'] != false,
        endpoint: _s(j['endpoint']),
        channelUrl: _n(j['channelUrl']),
        badgeText: _s(j['badgeText']),
        heading: _s(j['heading']),
        description: _s(j['description']),
        logo: _n(j['logo']),
      );
}

class Verse {
  Verse(this.text, this.reference);
  final String text;
  final String reference;
}

class Donation {
  Donation({
    required this.pageUrl,
    required this.recipient,
    required this.edrpou,
    required this.iban,
    required this.bank,
    required this.purpose,
    this.cardNumber,
    this.cardHolder,
    this.qrUrl,
    this.qrLabel,
    required this.onlinePayment,
  });

  final String pageUrl;
  final String recipient;
  final String edrpou;
  final String iban;
  final String bank;
  final String purpose;
  final String? cardNumber;
  final String? cardHolder;
  final String? qrUrl;
  final String? qrLabel;
  final bool onlinePayment;

  factory Donation.fromJson(Map<String, dynamic> j) {
    final card = j['card'] is Map ? Map<String, dynamic>.from(j['card'] as Map) : null;
    final qr = j['qrLink'] is Map ? Map<String, dynamic>.from(j['qrLink'] as Map) : null;
    return Donation(
      pageUrl: _s(j['pageUrl']),
      recipient: _s(j['recipient']),
      edrpou: _s(j['edrpou']),
      iban: _s(j['iban']),
      bank: _s(j['bank']),
      purpose: _s(j['purpose']),
      cardNumber: _n(card?['number']),
      cardHolder: _n(card?['holder']),
      qrUrl: _n(qr?['url']),
      qrLabel: _n(qr?['label']),
      onlinePayment: _b(j['onlinePayment']),
    );
  }
}

class AppConfig {
  AppConfig({
    required this.siteUrl,
    required this.name,
    required this.shortName,
    required this.logo,
    required this.phone,
    required this.email,
    required this.address,
    required this.mapsUrl,
    required this.serviceDay,
    required this.serviceTime,
    required this.serviceNote,
    required this.verses,
    required this.live,
    required this.donation,
  });

  final String siteUrl;
  final String name;
  final String shortName;
  final String? logo;
  final String phone;
  final String email;
  final String address;
  final String mapsUrl;
  final String serviceDay;
  final String serviceTime;
  final String serviceNote;
  final List<Verse> verses;
  final LiveSettings live;
  final Donation donation;

  factory AppConfig.fromJson(Map<String, dynamic> j) {
    final church = Map<String, dynamic>.from((j['church'] as Map?) ?? const {});
    final contacts = Map<String, dynamic>.from((j['contacts'] as Map?) ?? const {});
    final service = Map<String, dynamic>.from((j['service'] as Map?) ?? const {});
    return AppConfig(
      siteUrl: _s(j['siteUrl']),
      name: _s(church['name']),
      shortName: _s(church['shortName']),
      logo: _n(church['logo']),
      phone: _s(contacts['phone']),
      email: _s(contacts['email']),
      address: _s(contacts['address']),
      mapsUrl: _s(contacts['mapsUrl']),
      serviceDay: _s(service['day']),
      serviceTime: _s(service['time']),
      serviceNote: _s(service['note']),
      verses: (j['verses'] is List ? j['verses'] as List : const [])
          .whereType<Map>()
          .map((v) => Verse(_s(v['text']), _s(v['reference'])))
          .where((v) => v.text.isNotEmpty)
          .toList(),
      live: LiveSettings.fromJson(Map<String, dynamic>.from((j['live'] as Map?) ?? const {})),
      donation: Donation.fromJson(Map<String, dynamic>.from((j['donation'] as Map?) ?? const {})),
    );
  }
}

// ── Проповіді ───────────────────────────────────────────────────────────────

class Sermon {
  Sermon({
    required this.id,
    required this.title,
    required this.preacher,
    required this.date,
    required this.duration,
    required this.audioUrl,
    this.coverUrl,
    this.books = const [],
    this.topics = const [],
    this.isReading = false,
    this.url,
    this.videoId,
  });

  final int id;
  final String title;
  final String preacher;
  final String date;
  final int duration;
  final String audioUrl;
  final String? coverUrl;
  final List<String> books;
  final List<String> topics;
  final bool isReading;
  final String? url;
  final String? videoId;

  DateTime? get dateTime => DateTime.tryParse(date);

  factory Sermon.fromJson(Map<String, dynamic> j) => Sermon(
        id: _i(j['id']),
        title: _s(j['title']),
        preacher: _s(j['preacher']),
        date: _s(j['date']),
        duration: _i(j['duration']),
        audioUrl: _s(j['audioUrl']),
        coverUrl: _n(j['coverUrl']),
        books: _strings(j['books']),
        topics: _strings(j['topics']),
        isReading: _b(j['isReading']),
        url: _n(j['url']),
        videoId: _n(j['videoId']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'preacher': preacher,
        'date': date,
        'duration': duration,
        'audioUrl': audioUrl,
        'coverUrl': coverUrl,
        'books': books,
        'topics': topics,
        'isReading': isReading,
        'url': url,
        'videoId': videoId,
      };
}

class Tally {
  Tally(this.name, this.count, {this.photo, this.bio = ''});
  final String name;
  final int count;
  final String? photo;
  final String bio;
}

class SermonCatalogue {
  SermonCatalogue({required this.sermons, required this.preachers, required this.books, required this.topics});

  final List<Sermon> sermons;
  final List<Tally> preachers;
  final List<Tally> books;
  final List<Tally> topics;

  factory SermonCatalogue.fromJson(Map<String, dynamic> j) => SermonCatalogue(
        sermons: _list(j['sermons'], Sermon.fromJson).where((s) => s.audioUrl.isNotEmpty).toList(),
        preachers: _list(
          j['preachers'],
          (m) => Tally(_s(m['name']), _i(m['count']), photo: _n(m['photo']), bio: _s(m['bio'])),
        ),
        books: _list(j['books'], (m) => Tally(_s(m['name']), _i(m['count']))),
        topics: _list(j['topics'], (m) => Tally(_s(m['name']), _i(m['count']))),
      );
}

class SermonDetail {
  SermonDetail({
    required this.sermon,
    required this.description,
    required this.preacherPhoto,
    required this.preacherBio,
    required this.byPreacher,
    required this.byBook,
  });

  final Sermon sermon;
  final String description;
  final String? preacherPhoto;
  final String preacherBio;
  final List<Sermon> byPreacher;
  final List<Sermon> byBook;

  factory SermonDetail.fromJson(Map<String, dynamic> j) {
    final info = j['preacherInfo'] is Map ? Map<String, dynamic>.from(j['preacherInfo'] as Map) : null;
    return SermonDetail(
      sermon: Sermon.fromJson(j),
      description: _s(j['description']),
      preacherPhoto: _n(info?['photo']),
      preacherBio: _s(info?['bio']),
      byPreacher: _list(j['byPreacher'], Sermon.fromJson),
      byBook: _list(j['byBook'], Sermon.fromJson),
    );
  }
}

// ── Відео ──────────────────────────────────────────────────────────────────

class VideoItem {
  VideoItem({required this.id, required this.title, required this.published, required this.thumbnail, required this.isService});

  final String id;
  final String title;
  final String published;
  final String thumbnail;
  final bool isService;

  DateTime? get publishedAt => DateTime.tryParse(published);

  factory VideoItem.fromJson(Map<String, dynamic> j) => VideoItem(
        id: _s(j['id']),
        title: _s(j['title']),
        published: _s(j['published']),
        thumbnail: _s(j['thumbnail']).isNotEmpty ? _s(j['thumbnail']) : 'https://i.ytimg.com/vi/${_s(j['id'])}/hqdefault.jpg',
        isService: _b(j['isService']),
      );
}

class VideoCollection {
  VideoCollection({required this.kind, required this.slug, required this.title, required this.description, this.image});

  final String kind;
  final String slug;
  final String title;
  final String description;
  final String? image;
}

class VideoSection {
  VideoSection({required this.kind, required this.title, required this.items});
  final String kind;
  final String title;
  final List<VideoCollection> items;
}

class VideosOverview {
  VideosOverview({required this.channelUrl, required this.latest, required this.sections});

  final String? channelUrl;
  final List<VideoItem> latest;
  final List<VideoSection> sections;

  factory VideosOverview.fromJson(Map<String, dynamic> j) => VideosOverview(
        channelUrl: _n(j['channelUrl']),
        latest: _list(j['latest'], VideoItem.fromJson).where((v) => v.id.isNotEmpty).toList(),
        sections: _list(j['sections'], (m) {
          final kind = _s(m['kind']);
          return VideoSection(
            kind: kind,
            title: _s(m['title']),
            items: _list(
              m['items'],
              (c) => VideoCollection(
                kind: kind,
                slug: _s(c['slug']),
                title: _s(c['title']),
                description: _s(c['description']),
                image: _n(c['image']),
              ),
            ),
          );
        }),
      );
}

class CollectionVideos {
  CollectionVideos({required this.title, required this.description, this.image, required this.videos});

  final String title;
  final String description;
  final String? image;
  final List<VideoItem> videos;

  factory CollectionVideos.fromJson(Map<String, dynamic> j) => CollectionVideos(
        title: _s(j['title']),
        description: _s(j['description']),
        image: _n(j['image']),
        videos: _list(j['videos'], VideoItem.fromJson).where((v) => v.id.isNotEmpty).toList(),
      );
}

class LiveStatus {
  LiveStatus({this.videoId, this.title, required this.nextIn});

  final String? videoId;
  final String? title;
  final Duration nextIn;

  bool get isLive => videoId != null;

  factory LiveStatus.fromJson(Map<String, dynamic> j) {
    final live = j['live'] is Map ? Map<String, dynamic>.from(j['live'] as Map) : null;
    final next = _i(j['nextInMs']);
    return LiveStatus(
      videoId: _n(live?['id']),
      title: _n(live?['title']),
      nextIn: Duration(milliseconds: next <= 0 ? 60000 : next),
    );
  }
}

// ── Новини ─────────────────────────────────────────────────────────────────

class NewsItem {
  NewsItem({required this.slug, required this.title, required this.excerpt, required this.date, required this.category, this.image, this.url});

  final String slug;
  final String title;
  final String excerpt;
  final String date;
  final String category;
  final String? image;
  final String? url;

  factory NewsItem.fromJson(Map<String, dynamic> j) => NewsItem(
        slug: _s(j['slug']),
        title: _s(j['title']),
        excerpt: _s(j['excerpt']),
        date: _s(j['date']),
        category: _s(j['category']),
        image: _n(j['image']),
        url: _n(j['url']),
      );
}

class Photo {
  Photo(this.url, this.caption);
  final String url;
  final String caption;
}

class NewsArticle {
  NewsArticle({
    required this.item,
    required this.html,
    required this.gallery,
    this.videoId,
    this.documentUrl,
  });

  final NewsItem item;
  final String html;
  final List<Photo> gallery;
  final String? videoId;
  final String? documentUrl;

  factory NewsArticle.fromJson(Map<String, dynamic> j) => NewsArticle(
        item: NewsItem.fromJson(j),
        html: _s(j['html']),
        gallery: _list(j['gallery'], (m) => Photo(_s(m['url']), _s(m['caption']))).where((p) => p.url.isNotEmpty).toList(),
        videoId: _n(j['videoId']),
        documentUrl: _n(j['documentUrl']),
      );
}

// ── Біблія ─────────────────────────────────────────────────────────────────

class Translation {
  Translation({required this.code, required this.lang, required this.title, required this.abbrev});
  final String code;
  final String lang;
  final String title;
  final String abbrev;
}

class BibleInfo {
  BibleInfo({required this.translations, required this.defaults, required this.dictionaryEndpoint, required this.startBook, required this.startChapter});

  final List<Translation> translations;
  final List<String> defaults;
  final String dictionaryEndpoint;
  final String startBook;
  final int startChapter;

  factory BibleInfo.fromJson(Map<String, dynamic> j) {
    final start = Map<String, dynamic>.from((j['start'] as Map?) ?? const {});
    return BibleInfo(
      translations: _list(
        j['translations'],
        (m) => Translation(code: _s(m['code']), lang: _s(m['lang']), title: _s(m['title']), abbrev: _s(m['abbrev'])),
      ),
      defaults: _strings(j['defaults']),
      dictionaryEndpoint: _s(j['dictionaryEndpoint']),
      startBook: _s(start['book']),
      startChapter: _i(start['chapter']) == 0 ? 1 : _i(start['chapter']),
    );
  }
}

class BibleBook {
  BibleBook({required this.bookNr, required this.slug, required this.testament, required this.name, required this.shortName, required this.chapters});

  final int bookNr;
  final String slug;
  final String testament;
  final String name;
  final String shortName;
  final List<int> chapters;

  bool get isNewTestament => testament == 'nt';

  factory BibleBook.fromJson(Map<String, dynamic> j) => BibleBook(
        bookNr: _i(j['bookNr']),
        slug: _s(j['slug']),
        testament: _s(j['testament']),
        name: _s(j['name']),
        shortName: _s(j['shortName']),
        chapters: j['chapters'] is List ? (j['chapters'] as List).map(_i).where((c) => c > 0).toList() : const [],
      );
}

class BibleVerse {
  BibleVerse(this.verse, this.text);
  final int verse;
  final String text;
}

class ChapterAudio {
  ChapterAudio({required this.setCode, required this.title, required this.narrator, required this.url, required this.duration, required this.verseStarts});

  final String setCode;
  final String title;
  final String narrator;
  final String url;
  final int duration;
  final List<(int verse, double start)> verseStarts;

  /// Номер вірша, що звучить у мить [position].
  int? verseAt(Duration position) {
    final seconds = position.inMilliseconds / 1000;
    int? current;
    for (final (verse, start) in verseStarts) {
      if (start <= seconds) {
        current = verse;
      } else {
        break;
      }
    }
    return current;
  }
}

class Commentary {
  Commentary({required this.title, required this.author, required this.verseFrom, required this.verseTo, required this.text});
  final String title;
  final String author;
  final int verseFrom;
  final int verseTo;
  final String text;
}

class ChapterPoint {
  ChapterPoint(this.bookNr, this.chapter);
  final int bookNr;
  final int chapter;
}

class BibleChapter {
  BibleChapter({
    required this.translation,
    required this.bookNr,
    required this.bookName,
    required this.chapter,
    required this.verses,
    required this.parallel,
    required this.parallelTranslation,
    required this.audio,
    required this.commentaries,
    this.prev,
    this.next,
    this.url,
  });

  final String translation;
  final int bookNr;
  final String bookName;
  final int chapter;
  final List<BibleVerse> verses;
  final List<BibleVerse> parallel;
  final String? parallelTranslation;
  final List<ChapterAudio> audio;
  final List<Commentary> commentaries;
  final ChapterPoint? prev;
  final ChapterPoint? next;
  final String? url;

  static List<BibleVerse> _verses(Object? v) => _list(v, (m) => BibleVerse(_i(m['verse']), _s(m['plain']).isNotEmpty ? _s(m['plain']) : _s(m['text'])));

  static ChapterPoint? _point(Object? v) => v is Map ? ChapterPoint(_i(v['bookNr']), _i(v['chapter'])) : null;

  factory BibleChapter.fromJson(Map<String, dynamic> j) {
    final parallel = j['parallel'] is Map ? Map<String, dynamic>.from(j['parallel'] as Map) : null;
    return BibleChapter(
      translation: _s(j['translation']),
      bookNr: _i(j['bookNr']),
      bookName: _s(j['bookName']),
      chapter: _i(j['chapter']),
      verses: _verses(j['verses']),
      parallel: parallel == null ? const [] : _verses(parallel['verses']),
      parallelTranslation: _n(parallel?['translation']),
      audio: _list(
        j['audio'],
        (m) => ChapterAudio(
          setCode: _s(m['setCode']),
          title: _s(m['title']),
          narrator: _s(m['narrator']),
          url: _s(m['url']),
          duration: _i(m['durationSec']),
          verseStarts: (m['verseStarts'] is List ? m['verseStarts'] as List : const [])
              .whereType<Map>()
              .map((s) => (_i(s['verse']), (s['start'] is num ? (s['start'] as num).toDouble() : 0.0)))
              .toList(),
        ),
      ).where((a) => a.url.isNotEmpty).toList(),
      commentaries: _list(
        j['commentaries'],
        (m) => Commentary(
          title: _s(m['title']),
          author: _s(m['author']),
          verseFrom: _i(m['verseFrom']),
          verseTo: _i(m['verseTo']),
          text: _s(m['text']),
        ),
      ),
      prev: _point(j['prev']),
      next: _point(j['next']),
      url: _n(j['url']),
    );
  }
}

class BibleHit {
  BibleHit({required this.bookNr, required this.bookName, required this.chapter, required this.verse, required this.text});
  final int bookNr;
  final String bookName;
  final int chapter;
  final int verse;
  final String text;
}

class DictionaryHit {
  DictionaryHit({required this.dictionary, required this.topic, required this.definition});
  final String dictionary;
  final String topic;
  final String definition;
}

/// Ноти з розділу сайту /notes: сторінки для перегляду й оригінальні файли
/// (PDF, MIDI, MP3, ABC) — усе так само, як на сайті, з тим самим джерелом.
class SheetFile {
  const SheetFile({required this.kind, required this.url, required this.label, required this.sizeBytes});

  final String kind;
  final String url;
  final String label;
  final int sizeBytes;

  factory SheetFile.fromJson(Map<String, dynamic> j) => SheetFile(
        kind: (j['kind'] ?? 'other').toString(),
        url: (j['url'] ?? '').toString(),
        label: (j['label'] ?? '').toString(),
        sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
      );

  String get sizeLabel {
    if (sizeBytes <= 0) return '';
    if (sizeBytes < 1024 * 1024) return tr('{a} КБ', {'a': (sizeBytes / 1024).round()});
    return tr('{a} МБ', {'a': (sizeBytes / 1024 / 1024).toStringAsFixed(1)});
  }
}

class SheetMusic {
  const SheetMusic({
    required this.slug,
    required this.title,
    required this.subtitle,
    required this.collection,
    required this.source,
    required this.sourceUrl,
    required this.license,
    required this.cover,
    required this.pages,
    required this.files,
    required this.songBook,
    required this.songNumber,
  });

  final String slug;
  final String title;
  final String subtitle;
  final String collection;
  final String source;
  final String sourceUrl;
  final String license;
  final String? cover;
  final List<String> pages;
  final List<SheetFile> files;
  final String songBook;
  final int songNumber;

  bool get hasSong => songBook.isNotEmpty && songNumber > 0;
  SheetFile? fileOf(String kind) {
    for (final f in files) {
      if (f.kind == kind) return f;
    }
    return null;
  }

  factory SheetMusic.fromJson(Map<String, dynamic> j) {
    final song = j['song'] is Map ? Map<String, dynamic>.from(j['song'] as Map) : const <String, dynamic>{};
    return SheetMusic(
      slug: (j['slug'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      subtitle: (j['subtitle'] ?? '').toString(),
      collection: (j['collection'] ?? '').toString(),
      source: (j['source'] ?? '').toString(),
      sourceUrl: (j['sourceUrl'] ?? '').toString(),
      license: (j['license'] ?? '').toString(),
      cover: j['cover']?.toString(),
      pages: (j['pages'] is List ? j['pages'] as List : const []).map((p) => p.toString()).toList(),
      files: (j['files'] is List ? j['files'] as List : const [])
          .whereType<Map>()
          .map((m) => SheetFile.fromJson(Map<String, dynamic>.from(m)))
          .where((f) => f.url.isNotEmpty)
          .toList(),
      songBook: (song['book'] ?? '').toString(),
      songNumber: (song['number'] as num?)?.toInt() ?? 0,
    );
  }
}

class SheetMusicPage {
  const SheetMusicPage({required this.items, required this.total, required this.page, required this.pages, required this.collections});

  final List<SheetMusic> items;
  final int total;
  final int page;
  final int pages;

  /// Назва збірки → скільки в ній творів.
  final List<MapEntry<String, int>> collections;

  factory SheetMusicPage.fromJson(Map<String, dynamic> j) => SheetMusicPage(
        items: (j['items'] is List ? j['items'] as List : const [])
            .whereType<Map>()
            .map((m) => SheetMusic.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
        total: (j['total'] as num?)?.toInt() ?? 0,
        page: (j['page'] as num?)?.toInt() ?? 1,
        pages: (j['pages'] as num?)?.toInt() ?? 1,
        collections: (j['collections'] is List ? j['collections'] as List : const [])
            .whereType<Map>()
            .map((m) => MapEntry((m['name'] ?? '').toString(), (m['count'] as num?)?.toInt() ?? 0))
            .where((e) => e.key.isNotEmpty)
            .toList(),
      );
}
