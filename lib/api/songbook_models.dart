/// Пісенник: збірники й пісні так, як їх віддає сайт (/api/app/v1/songbook).
library;

String _s(Object? v) => v == null ? '' : v.toString();
int _i(Object? v) => v is num ? v.toInt() : int.tryParse(_s(v)) ?? 0;

/// Як на сайті (lib/songbook-format.ts foldText): без регістру й розділових
/// знаків, і/ї/ы/и та є/э/е — одне. Щоб «Слухайте» знаходило «Слушайте».
String foldSongText(String value) {
  final lower = value.toLowerCase();
  final buffer = StringBuffer();
  var space = true;
  for (final rune in lower.runes) {
    var ch = String.fromCharCode(rune);
    switch (ch) {
      case 'ё':
        ch = 'е';
      case 'і' || 'ї' || 'ы':
        ch = 'и';
      case 'є' || 'э':
        ch = 'е';
      case 'ґ':
        ch = 'г';
      case 'ь' || 'ъ' || '\'' || 'ʼ' || '’' || '`':
        continue;
    }
    // Літера — те, що має велику й малу форму (кирилиця, латиниця), або цифра.
    final isWord = ch.toUpperCase() != ch.toLowerCase() || (rune >= 0x30 && rune <= 0x39);
    if (isWord) {
      buffer.write(ch);
      space = false;
    } else if (!space) {
      buffer.write(' ');
      space = true;
    }
  }
  return buffer.toString().trim();
}

class SongbookBook {
  SongbookBook({required this.code, required this.title, required this.shortTitle, required this.lang, required this.copyright, required this.songs, required this.updatedAt});

  final String code;
  final String title;
  final String shortTitle;
  final String lang;
  final String copyright;
  final int songs;
  final String updatedAt;

  factory SongbookBook.fromJson(Map<String, dynamic> j) => SongbookBook(
        code: _s(j['code']),
        title: _s(j['title']),
        shortTitle: _s(j['shortTitle']),
        lang: _s(j['lang']),
        copyright: _s(j['copyright']),
        songs: _i(j['songs']),
        updatedAt: _s(j['updatedAt']),
      );
}

class SongbookInfo {
  SongbookInfo({
    required this.books,
    required this.defaultBook,
    required this.intro,
    required this.kinds,
    required this.notesOpenByDefault,
    required this.midiMelodyByDefault,
    required this.soundfontUrl,
    required this.textScale,
  });

  final List<SongbookBook> books;
  final String? defaultBook;
  final String intro;
  final Set<String> kinds;
  final bool notesOpenByDefault;
  final bool midiMelodyByDefault;
  final String? soundfontUrl;
  final int textScale;

  factory SongbookInfo.fromJson(Map<String, dynamic> j) => SongbookInfo(
        books: (j['books'] is List ? j['books'] as List : const [])
            .whereType<Map>()
            .map((m) => SongbookBook.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
        defaultBook: j['defaultBook'] == null ? null : _s(j['defaultBook']),
        intro: _s(j['intro']),
        kinds: {for (final k in (j['kinds'] is List ? j['kinds'] as List : const [])) _s(k)},
        notesOpenByDefault: j['notesOpenByDefault'] == true,
        midiMelodyByDefault: j['midiMelodyByDefault'] != false,
        soundfontUrl: _s(j['soundfontUrl']).isEmpty ? null : _s(j['soundfontUrl']),
        textScale: _i(j['textScale']) == 0 ? 100 : _i(j['textScale']),
      );
}

class SongPart {
  SongPart({required this.label, required this.kind, required this.text});

  final String label;
  /// verse | chorus | bridge | ending | other
  final String kind;
  final String text;

  factory SongPart.fromJson(Map<String, dynamic> j) => SongPart(label: _s(j['label']), kind: _s(j['kind']), text: _s(j['text']));
}

class SongMedia {
  SongMedia({required this.kind, required this.title, required this.url, required this.pages, required this.source, required this.sourceUrl, required this.durationSec});

  /// midi | minus | song | notes
  final String kind;
  final String title;
  final String url;
  final List<String> pages;
  final String source;
  final String? sourceUrl;
  final int durationSec;

  factory SongMedia.fromJson(Map<String, dynamic> j) => SongMedia(
        kind: _s(j['kind']),
        title: _s(j['title']),
        url: _s(j['url']),
        pages: [for (final p in (j['pages'] is List ? j['pages'] as List : const [])) _s(p)],
        source: _s(j['source']),
        sourceUrl: j['sourceUrl'] == null ? null : _s(j['sourceUrl']),
        durationSec: _i(j['durationSec']),
      );
}

class Song {
  Song({
    required this.number,
    required this.title,
    required this.lang,
    required this.wordsBy,
    required this.musicBy,
    required this.tune,
    required this.parts,
    required this.media,
  });

  final int number;
  final String title;
  final String lang;
  final String wordsBy;
  final String musicBy;
  final String tune;
  final List<SongPart> parts;
  final List<SongMedia> media;

  late final String titleFold = foldSongText(title);
  late final String textFold = foldSongText('$title ${parts.map((p) => p.text).join(' ')}');

  String get firstLine => parts.isEmpty ? '' : parts.first.text.split('\n').first.trim();

  List<SongMedia> mediaOf(String kind) => media.where((m) => m.kind == kind).toList();
  bool has(String kind) => media.any((m) => m.kind == kind);

  factory Song.fromJson(Map<String, dynamic> j) => Song(
        number: _i(j['number']),
        title: _s(j['title']),
        lang: _s(j['lang']),
        wordsBy: _s(j['wordsBy']),
        musicBy: _s(j['musicBy']),
        tune: _s(j['tune']),
        parts: (j['parts'] is List ? j['parts'] as List : const [])
            .whereType<Map>()
            .map((m) => SongPart.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
        media: (j['media'] is List ? j['media'] as List : const [])
            .whereType<Map>()
            .map((m) => SongMedia.fromJson(Map<String, dynamic>.from(m)))
            .where((m) => m.url.isNotEmpty)
            .toList(),
      );
}
