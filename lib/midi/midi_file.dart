import 'dart:convert';
import 'dart:typed_data';
import '../i18n.dart';

/// Склад караоке з часом (секунди від початку пісні при темпі 100 %).
class Syllable {
  const Syllable(this.time, this.text);
  final double time;
  final String text;
}

class LyricLine {
  LyricLine(this.start);
  final double start;
  final List<Syllable> syllables = [];
  String get text => syllables.map((s) => s.text).join();
}

/// Що треба знати про MIDI-файл пісні до рендеру: скільки він звучить, слова
/// караоке з часом і інструменти каналів — так само, як на сайті
/// (lib/songbook-synth.ts loadSong).
class MidiInfo {
  MidiInfo({required this.duration, required this.lines, required this.programs});

  /// Секунди до кінця останньої доріжки при темпі 100 %.
  final double duration;
  final List<LyricLine> lines;

  /// Перша зміна програми кожного каналу у файлі.
  final Map<int, int> programs;

  /// Розбір стандартного MIDI (.mid/.kar). Кидає [FormatException], якщо це не MIDI.
  factory MidiInfo.parse(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    var pos = 0;
    String tag() => ascii.decode(bytes.sublist(pos, pos + 4), allowInvalid: true);
    if (bytes.length < 14) throw FormatException(tr('не MIDI'));
    // RIFF-обгортка (.rmi) — MIDI всередині.
    if (tag() == 'RIFF') {
      final idx = _indexOf(bytes, ascii.encode('MThd'));
      if (idx < 0) throw FormatException(tr('не MIDI'));
      pos = idx;
    }
    if (tag() != 'MThd') throw FormatException(tr('не MIDI'));
    final headerLen = data.getUint32(pos + 4);
    final trackCount = data.getUint16(pos + 10);
    final division = data.getUint16(pos + 12);
    pos += 8 + headerLen;

    final tempos = <(int, int)>[]; // (tick, мікросекунд на чверть)
    final texts = <(int, Uint8List)>[];
    final programs = <int, int>{};
    var maxTick = 0;

    for (var t = 0; t < trackCount && pos + 8 <= bytes.length; t++) {
      final id = tag();
      final len = data.getUint32(pos + 4);
      pos += 8;
      final end = (pos + len).clamp(0, bytes.length);
      if (id != 'MTrk') {
        pos = end;
        t--;
        if (pos >= bytes.length) break;
        continue;
      }
      var tick = 0;
      var status = 0;
      var p = pos;
      int varLen() {
        var value = 0;
        for (var i = 0; i < 4 && p < end; i++) {
          final b = bytes[p++];
          value = (value << 7) | (b & 0x7f);
          if (b & 0x80 == 0) break;
        }
        return value;
      }

      while (p < end) {
        tick += varLen();
        if (p >= end) break;
        final b = bytes[p];
        if (b & 0x80 != 0) {
          status = b;
          p++;
        } else if (status == 0) {
          break; // зіпсована доріжка
        }
        if (status == 0xff) {
          if (p >= end) break;
          final type = bytes[p++];
          final l = varLen();
          final from = p;
          p = (p + l).clamp(0, end);
          if (type == 0x51 && l == 3) {
            tempos.add((tick, (bytes[from] << 16) | (bytes[from + 1] << 8) | bytes[from + 2]));
          } else if (type == 0x01) {
            texts.add((tick, Uint8List.sublistView(bytes, from, p)));
          } else if (type == 0x2f) {
            break;
          }
          status = 0; // мета-подія не задає «running status»
        } else if (status == 0xf0 || status == 0xf7) {
          final l = varLen();
          p = (p + l).clamp(0, end);
          status = 0;
        } else {
          final kind = status & 0xf0;
          final channel = status & 0x0f;
          final size = (kind == 0xc0 || kind == 0xd0) ? 1 : 2;
          if (p + size > end) break;
          if (kind == 0xc0) programs.putIfAbsent(channel, () => bytes[p]);
          p += size;
        }
      }
      if (tick > maxTick) maxTick = tick;
      pos = end;
    }

    final seconds = _TempoMap(division, tempos);
    // Слова — текстові події (0x01) у CP1251; «/» — новий рядок, «\» — нова строфа,
    // «@…» — службові (назва, мова).
    final syllables = <Syllable>[];
    for (final (tick, raw) in texts) {
      // Після складу в цих файлах лежить сміття з буфера програми, що їх робила:
      // «/Вот \0\0\0\x16\0\0\0\x01/С в». Склад — лише до першого нульового байта;
      // без цього в караоке змішувались уривки інших складів («Вот /С внадостстал»).
      final zero = raw.indexOf(0);
      final text = decodeCp1251(zero >= 0 ? raw.sublist(0, zero) : raw);
      if (text.isEmpty || text.startsWith('@') || text.toLowerCase().contains('karmaker')) continue;
      syllables.add(Syllable(seconds.at(tick), text));
    }
    syllables.sort((a, b) => a.time.compareTo(b.time));
    final lines = <LyricLine>[];
    final breakRe = RegExp(r'^[\\/]');
    final cleanRe = RegExp(r'[^\p{L}\p{N}\p{P}\p{Zs}]', unicode: true);
    // «шайv», «во z», «ли &» були тим самим сміттям після нульового байта — тепер
    // його відрізано вище; тут лишається прибрати службові знаки.
    for (final s in syllables) {
      final breaks = breakRe.hasMatch(s.text);
      final clean = s.text.replaceFirst(RegExp(r'^[\\/]+'), '').replaceAll(cleanRe, '');
      if (breaks || lines.isEmpty) lines.add(LyricLine(s.time));
      if (clean.isNotEmpty) lines.last.syllables.add(Syllable(s.time, clean));
    }

    return MidiInfo(
      duration: seconds.at(maxTick),
      lines: lines.where((l) => l.syllables.isNotEmpty).toList(),
      programs: programs,
    );
  }
}

int _indexOf(Uint8List hay, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= hay.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}

class _TempoMap {
  _TempoMap(int division, List<(int, int)> tempos) {
    if (division & 0x8000 != 0) {
      // SMPTE: -кадри/с і тиків на кадр — темп не діє.
      final fps = 256 - (division >> 8);
      _smpteTickSeconds = 1 / (fps * (division & 0xff));
    }
    _ppq = division & 0x7fff == 0 ? 480 : division & 0x7fff;
    final sorted = [...tempos]..sort((a, b) => a.$1.compareTo(b.$1));
    var tick = 0;
    var seconds = 0.0;
    var us = 500000;
    _points.add((0, 0.0, us));
    for (final (t, value) in sorted) {
      seconds += (t - tick) * us / 1e6 / _ppq;
      tick = t;
      us = value == 0 ? 500000 : value;
      _points.add((tick, seconds, us));
    }
  }

  late final int _ppq;
  double? _smpteTickSeconds;
  final List<(int, double, int)> _points = [];

  double at(int tick) {
    final smpte = _smpteTickSeconds;
    if (smpte != null) return tick * smpte;
    var point = _points.first;
    for (final p in _points) {
      if (p.$1 > tick) break;
      point = p;
    }
    return point.$2 + (tick - point.$1) * point.$3 / 1e6 / _ppq;
  }
}

/// Windows-1251 → рядок (караоке-файли збірника написані в ній).
String decodeCp1251(List<int> bytes) {
  final out = StringBuffer();
  for (final b in bytes) {
    if (b < 0x80) {
      if (b != 0) out.writeCharCode(b);
    } else {
      out.writeCharCode(_cp1251[b - 0x80]);
    }
  }
  return out.toString();
}

const List<int> _cp1251 = [
  0x0402, 0x0403, 0x201A, 0x0453, 0x201E, 0x2026, 0x2020, 0x2021, 0x20AC, 0x2030, 0x0409, 0x2039, 0x040A, 0x040C, 0x040B, 0x040F, //
  0x0452, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0xFFFD, 0x2122, 0x0459, 0x203A, 0x045A, 0x045C, 0x045B, 0x045F, //
  0x00A0, 0x040E, 0x045E, 0x0408, 0x00A4, 0x0490, 0x00A6, 0x00A7, 0x0401, 0x00A9, 0x0404, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x0407, //
  0x00B0, 0x00B1, 0x0406, 0x0456, 0x0491, 0x00B5, 0x00B6, 0x00B7, 0x0451, 0x2116, 0x0454, 0x00BB, 0x0458, 0x0405, 0x0455, 0x0457, //
  0x0410, 0x0411, 0x0412, 0x0413, 0x0414, 0x0415, 0x0416, 0x0417, 0x0418, 0x0419, 0x041A, 0x041B, 0x041C, 0x041D, 0x041E, 0x041F, //
  0x0420, 0x0421, 0x0422, 0x0423, 0x0424, 0x0425, 0x0426, 0x0427, 0x0428, 0x0429, 0x042A, 0x042B, 0x042C, 0x042D, 0x042E, 0x042F, //
  0x0430, 0x0431, 0x0432, 0x0433, 0x0434, 0x0435, 0x0436, 0x0437, 0x0438, 0x0439, 0x043A, 0x043B, 0x043C, 0x043D, 0x043E, 0x043F, //
  0x0440, 0x0441, 0x0442, 0x0443, 0x0444, 0x0445, 0x0446, 0x0447, 0x0448, 0x0449, 0x044A, 0x044B, 0x044C, 0x044D, 0x044E, 0x044F, //
];
