import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api.dart';
import '../api/songbook_models.dart';
import '../midi/midi_audio_source.dart';
import '../midi/midi_file.dart';
import '../midi/renderer.dart';
import 'player.dart';
import '../i18n.dart';

/// Звучання — ті самі звукові банки, що на сайті (lib/songbook-synth.ts SOUNDS,
/// tools/soundfont/README.md).
class MidiSound {
  const MidiSound({
    required this.id,
    required this.label,
    required this.hint,
    required this.file,
    required this.sizeBytes,
    required this.credit,
    required this.gain,
  });

  final String id;
  final String label;
  final String hint;
  final String file;
  final int sizeBytes;
  final String credit;

  /// Підсилення після синтезатора: банки записані з різною гучністю (на тій самій
  /// пісні піки −5, −13 і −14 дБ) — так звучання однаково гучні.
  final double gain;

  String get url => '${Api.siteUrl}/uploads/soundfonts/$file';
  String get sizeLabel => tr('{a} МБ', {'a': (sizeBytes / 1048576).toStringAsFixed(sizeBytes < 10485760 ? 1 : 0).replaceAll('.', ',')});
}

const midiSounds = <MidiSound>[
  MidiSound(
    id: 'sgp',
    label: 'Концертний рояль',
    hint: 'Salamander Grand + GeneralUser GS',
    file: 'hymns-sgp-gu-v1.sf3',
    sizeBytes: 11801242,
    credit: 'рояль Salamander Grand Piano (Alexander Holm, CC BY 3.0), інструменти GeneralUser GS (S. Christian Collins)',
    gain: 3.0,
  ),
  MidiSound(
    id: 'msg',
    label: 'MuseScore General',
    hint: "м'якший рояль Steinway",
    file: 'hymns-msg-v1.sf3',
    sizeBytes: 19683758,
    credit: 'MuseScore General (S. Christian Collins, MIT)',
    gain: 7.0,
  ),
  MidiSound(
    id: 'gu',
    label: 'Легкий',
    hint: 'GeneralUser GS — для повільного інтернету',
    file: 'hymns-gu-v1.sf3',
    sizeBytes: 2186734,
    credit: 'GeneralUser GS (S. Christian Collins)',
    gain: 6.5,
  ),
];

/// Канал мелодії в усіх караоке-MIDI збірника; 0 — акомпанемент (рояль).
const int melodyChannel = 1;
const int accompanimentChannel = 0;

/// −1 — як у файлі пісні. Лише ті програми, що є в усіх трьох банках.
const accompanimentInstruments = <(int, String)>[(-1, 'Рояль (як у файлі)'), (19, 'Орган'), (48, 'Струнні')];
const melodyInstruments = <(int, String)>[
  (-1, 'Як у файлі'),
  (40, 'Скрипка'),
  (73, 'Флейта'),
  (71, 'Кларнет'),
  (52, 'Хор «а-а»'),
  (19, 'Орган'),
  (57, 'Тромбон'),
  (21, 'Акордеон'),
];

String instrumentLabel(List<(int, String)> options, int program) =>
    tr(options.where((o) => o.$1 == program).firstOrNull?.$2 ?? options.first.$2);

class PartChoice {
  const PartChoice({required this.on, required this.program});
  final bool on;
  final int program;
  PartChoice copyWith({bool? on, int? program}) => PartChoice(on: on ?? this.on, program: program ?? this.program);
  Map<String, Object> toJson() => {'on': on, 'program': program};
  static PartChoice? fromJson(Object? raw) =>
      raw is Map ? PartChoice(on: raw['on'] != false, program: (raw['program'] as num?)?.toInt() ?? -1) : null;
}

/// Пісня, відкрита в програвачі мінусу.
class MidiSession {
  MidiSession({required this.bookCode, required this.song});

  final String bookCode;
  final Song song;
  int variant = 0;
  int transpose = 0;
  double tempo = 1.0;
  final Map<String, MidiInfo> _info = {};

  List<SongMedia> get variants => song.mediaOf('midi');
  SongMedia? get media => variants.isEmpty ? null : variants[variant.clamp(0, variants.length - 1)];
  MidiInfo? get info => media == null ? null : _info[media!.url];
  String get title => '${song.number}. ${song.title}';
  String get key => 'midi:$bookCode/${song.number}/$variant';
}

enum MidiStatus { idle, bank, song, ready, error }

class MidiException implements Exception {
  MidiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Мінус пісні власним синтезатором застосунку (FluidSynth, lib/midi/).
///
/// Звучить без інтернету, у фоні й на заблокованому екрані — через той самий
/// програвач, що проповіді. Звуковий банк завантажується один раз; файл пісні —
/// при першому відкритті. Слухач обирає звучання, інструменти мелодії й
/// акомпанементу, вмикає й вимикає їх, змінює тональність і темп — синтезатор
/// переписує пісню за секунди й продовжує з того самого місця.
class MidiService extends ChangeNotifier {
  MidiService(this._player);

  final PlayerService _player;
  SharedPreferences? _prefs;

  static const _kPrefs = 'midi.prefs.v1';

  // ── Вибір слухача (зберігається) ──
  String? _soundId;
  PartChoice? _melody;
  PartChoice _accompaniment = const PartChoice(on: true, program: -1);

  /// Налаштування сайту: з якого звучання й чи з мелодією починати.
  String? _siteSoundUrl;
  bool _siteMelodyOn = true;

  MidiSound get sound => midiSounds.where((s) => s.id == _soundId).firstOrNull ?? _siteSound;
  MidiSound get _siteSound => midiSounds.where((s) => _siteSoundUrl != null && _siteSoundUrl!.endsWith(s.file)).firstOrNull ?? midiSounds.first;
  PartChoice get melody => _melody ?? PartChoice(on: _siteMelodyOn, program: -1);
  PartChoice get accompaniment => _accompaniment;

  // ── Стан ──
  MidiSession? session;
  MidiStatus status = MidiStatus.idle;
  String? error;
  int bankLoaded = 0;
  int bankTotal = 0;
  MidiRenderJob? job;

  int _startGeneration = 0;
  bool _starting = false;
  double _renderedTempo = 1.0;
  Timer? _restart;
  final Map<String, Future<void>> _bankDownloads = {};
  final Set<String> _banksOnPhone = {};

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    try {
      final raw = _prefs!.getString(_kPrefs);
      if (raw != null) {
        final m = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        _soundId = m['sound'] as String?;
        _melody = PartChoice.fromJson(m['melody']);
        _accompaniment = PartChoice.fromJson(m['accompaniment']) ?? _accompaniment;
      }
    } catch (_) {}
    for (final s in midiSounds) {
      if (await (await _bankFile(s)).exists()) _banksOnPhone.add(s.id);
    }
    _player.addListener(_onPlayer);
    unawaited(_cleanup(startup: true));
  }

  void _save() {
    unawaited(_prefs?.setString(
      _kPrefs,
      jsonEncode({
        if (_soundId != null) 'sound': _soundId,
        if (_melody != null) 'melody': _melody!.toJson(),
        'accompaniment': _accompaniment.toJson(),
      }),
    ));
  }

  bool isOnPhone(MidiSound s) => _banksOnPhone.contains(s.id);

  /// Цей мінус зараз у програвачі (грає чи на паузі).
  bool get isActive => session != null && _player.current?.key == session!.key;

  /// Відкрити пісню в програвачі мінусу. Та сама пісня, що вже грає, — зі своїм станом.
  MidiSession open({required String bookCode, required Song song, String? siteSoundUrl, bool siteMelodyOn = true}) {
    _siteSoundUrl = siteSoundUrl;
    _siteMelodyOn = siteMelodyOn;
    final current = session;
    if (current != null && current.bookCode == bookCode && current.song.number == song.number) return current;
    session = MidiSession(bookCode: bookCode, song: song);
    status = MidiStatus.idle;
    error = null;
    notifyListeners();
    unawaited(_preload());
    return session!;
  }

  /// Звучання вже на телефоні — синтезатор відкриває його, поки людина дивиться на екран.
  Future<void> _preload() async {
    try {
      final bank = await _bankFile(sound);
      if (await bank.exists()) await MidiRenderer.instance.preload(bank.path);
    } catch (_) {}
  }

  Future<void> toggle() async {
    if (isActive && error == null && _player.error == null && _player.player.processingState != ProcessingState.idle) {
      await (_player.player.playing ? _player.player.pause() : _player.player.play());
      return;
    }
    await _start();
  }

  // ── Зміни вибору: якщо мінус звучить — переписати й грати далі з того ж місця ──

  void setTranspose(int value) {
    final s = session;
    if (s == null || s.transpose == value) return;
    s.transpose = value.clamp(-6, 6);
    _changed();
  }

  void setTempo(double value) {
    final s = session;
    if (s == null) return;
    final next = (value.clamp(0.5, 1.5) * 100).round() / 100;
    if (next == s.tempo) return;
    s.tempo = next;
    _changed();
  }

  void setVariant(int index) {
    final s = session;
    if (s == null || s.variant == index) return;
    s.variant = index;
    _changed(fromStart: true);
  }

  void setMelody(PartChoice value) {
    _melody = value;
    _save();
    _changed();
  }

  void setAccompaniment(PartChoice value) {
    _accompaniment = value;
    _save();
    _changed();
  }

  void setSound(String id) {
    if (sound.id == id) return;
    _soundId = id;
    _save();
    unawaited(_preload());
    _changed();
  }

  void _changed({bool fromStart = false}) {
    notifyListeners();
    if (!isActive) return;
    _restart?.cancel();
    // Кілька натисків «+» поспіль — один перерахунок.
    _restart = Timer(const Duration(milliseconds: 450), () {
      final s = session;
      if (s == null || !isActive) return;
      final wasPlaying = _player.player.playing;
      final position = fromStart ? Duration.zero : _player.player.position * (_renderedTempo / s.tempo);
      unawaited(_start(from: position, autoplay: wasPlaying));
    });
  }

  // ── Підготовка й запуск ──

  Future<void> _start({Duration from = Duration.zero, bool autoplay = true}) async {
    final s = session;
    final media = s?.media;
    if (s == null || media == null) return;
    final generation = ++_startGeneration;
    bool stale() => generation != _startGeneration || !identical(session, s);
    _starting = true;
    error = null;
    try {
      final chosen = sound;
      final bank = await _bankFile(chosen);
      if (!await bank.exists()) {
        status = MidiStatus.bank;
        notifyListeners();
        // Два натиски ▶ — одне завантаження. (Колбек без значення: якби він
        // повертав прибраний Future, той чекав би сам на себе.)
        await (_bankDownloads[chosen.id] ??= _downloadBank(chosen).whenComplete(() {
          _bankDownloads.remove(chosen.id);
        }));
        if (stale()) return;
      }
      status = MidiStatus.song;
      notifyListeners();
      final midiFile = await _midiFile(media.url);
      final info = s._info[media.url] ??= MidiInfo.parse(await midiFile.readAsBytes());
      if (stale()) return;

      final tempo = s.tempo;
      final frames = ((info.duration / tempo + 2.0) * midiSampleRate).ceil();
      final mel = melody;
      final acc = accompaniment;
      final muted = <int>{if (!acc.on) accompanimentChannel, if (!mel.on) melodyChannel};
      final programs = <int, int>{
        if (acc.program >= 0) accompanimentChannel: acc.program,
        if (mel.program >= 0) melodyChannel: mel.program,
      };
      final renderKey = _hash('${chosen.file}|${media.url}|${muted.toList()..sort()}|$programs|${s.transpose}|$tempo|${frames}f|g${chosen.gain}|v2');
      final dir = await _renderDir();
      final out = '${dir.path}/$renderKey.wav';
      final tag = MediaItem(
        id: s.key,
        title: s.title,
        artist: tr('Мінус · {a}', {'a': tr(chosen.label)}),
        album: tr('Пісенник'),
        duration: Duration(milliseconds: (info.duration / tempo * 1000).round()),
      );

      AudioSource source;
      MidiRenderJob? rendering;
      final ready = File(out);
      if (await ready.exists() && await ready.length() == wavHeaderSize + frames * 4) {
        unawaited(ready.setLastModified(DateTime.now()).catchError((_) {}));
        source = AudioSource.file(out, tag: tag);
      } else {
        rendering = await MidiRenderer.instance.start(MidiRenderRequest(
          bankPath: bank.path,
          midiPath: midiFile.path,
          outPath: out,
          frames: frames,
          mutedChannels: muted,
          programs: programs,
          transpose: s.transpose,
          tempo: tempo,
          gain: chosen.gain,
        ));
        source = MidiAudioSource(rendering, tag: tag);
      }
      if (stale()) {
        if (rendering != null) MidiRenderer.instance.cancel(rendering);
        return;
      }
      final previous = job;
      job = rendering;
      _renderedTempo = tempo;
      final target = from > tag.duration! ? Duration.zero : from;
      await _player.playMidi(
        key: s.key,
        source: source,
        title: s.title,
        subtitle: tr('Мінус · {a}', {'a': tr(chosen.label)}),
        position: target,
        autoplay: autoplay,
        replay: () => _start(from: _player.player.position),
      );
      if (previous != null && !identical(previous, rendering)) MidiRenderer.instance.cancel(previous);
      if (stale()) return;
      status = _player.error == null ? MidiStatus.ready : MidiStatus.error;
      error = _player.error;
    } on MidiException catch (e) {
      if (stale()) return;
      status = MidiStatus.error;
      error = e.message;
    } catch (e) {
      if (stale()) return;
      status = MidiStatus.error;
      error = tr('Не вдалося підготувати мінус ({a}).', {'a': e});
    } finally {
      if (generation == _startGeneration) _starting = false;
    }
    notifyListeners();
    unawaited(_cleanup());
  }

  /// Заграло щось інше (проповідь, Біблія) — синтезатору більше нема для кого писати.
  void _onPlayer() {
    final running = job;
    if (running == null || running.done || running.failed || _starting) return;
    final current = _player.current;
    if (current != null && current.key != session?.key) {
      MidiRenderer.instance.cancel(running);
      job = null;
    }
  }

  // ── Файли ──

  Future<File> _bankFile(MidiSound s) async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/soundfonts');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/${s.file}');
  }

  Future<void> _downloadBank(MidiSound s) async {
    final file = await _bankFile(s);
    final part = File('${file.path}.part');
    final client = http.Client();
    bankLoaded = 0;
    bankTotal = s.sizeBytes;
    notifyListeners();
    try {
      final response = await client.send(http.Request('GET', Uri.parse(s.url))).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw MidiException(tr('Звучання «{a}» зараз недоступне (сайт відповів {b}).', {'a': tr(s.label), 'b': response.statusCode}));
      bankTotal = response.contentLength ?? s.sizeBytes;
      final sink = part.openWrite();
      var notified = 0;
      try {
        await for (final chunk in response.stream.timeout(const Duration(seconds: 60))) {
          sink.add(chunk);
          bankLoaded += chunk.length;
          if (bankLoaded - notified > 250000) {
            notified = bankLoaded;
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }
      if (response.contentLength != null && bankLoaded != response.contentLength) {
        throw MidiException(tr('Звучання завантажилось не до кінця. Натисніть ▶ ще раз.'));
      }
      await part.rename(file.path);
      _banksOnPhone.add(s.id);
    } on MidiException {
      rethrow;
    } catch (_) {
      throw MidiException(tr('Не вдалося завантажити звучання «{a}». Перевірте інтернет і натисніть ▶ ще раз.', {'a': tr(s.label)}));
    } finally {
      client.close();
      if (await part.exists()) await part.delete().catchError((_) => part);
    }
  }

  /// Файл пісні лежить на телефоні після першого відкриття — далі без мережі.
  Future<File> _midiFile(String url) async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/songbook-midi');
    if (!await dir.exists()) await dir.create(recursive: true);
    final name = Uri.parse(url).pathSegments.lastOrNull?.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_') ?? _hash(url);
    final file = File('${dir.path}/$name');
    if (await file.exists() && await file.length() > 0) return file;
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw MidiException(tr('Файл мінусу недоступний (сайт відповів {a}).', {'a': response.statusCode}));
      MidiInfo.parse(response.bodyBytes); // не MIDI — не зберігаємо
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(response.bodyBytes, flush: true);
      await tmp.rename(file.path);
      return file;
    } on MidiException {
      rethrow;
    } on FormatException {
      throw MidiException(tr('Файл мінусу пошкоджений.'));
    } catch (_) {
      throw MidiException(tr('Не вдалося завантажити мінус. Перевірте інтернет і натисніть ▶ ще раз.'));
    }
  }

  Future<Directory> _renderDir() async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/midi-render');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Готові мінуси — лише два останні (кожен ~30 МБ); недописані — геть.
  Future<void> _cleanup({bool startup = false}) async {
    try {
      final dir = await _renderDir();
      final wavs = <File>[];
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        if (entity.path.endsWith('.wav')) {
          wavs.add(entity);
        } else if (startup && entity.path.endsWith('.part')) {
          await entity.delete();
        }
      }
      wavs.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      for (final old in wavs.skip(2)) {
        await old.delete();
      }
    } catch (_) {}
  }

  static String _hash(String value) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toUnsigned(64).toRadixString(16);
  }

  @override
  void dispose() {
    _restart?.cancel();
    _player.removeListener(_onPlayer);
    super.dispose();
  }
}

// ── Тональність для підпису: «ля мажор» + 2 → «сі мажор» (як на сайті) ──

/// Назви нот і ладів мовою застосунку (як на сайті, lib/note-names.ts).
const _noteNames = {
  'uk': ['до', 'до-дієз', 'ре', 'мі-бемоль', 'мі', 'фа', 'фа-дієз', 'соль', 'ля-бемоль', 'ля', 'сі-бемоль', 'сі'],
  'ru': ['до', 'до-диез', 'ре', 'ми-бемоль', 'ми', 'фа', 'фа-диез', 'соль', 'ля-бемоль', 'ля', 'си-бемоль', 'си'],
  'en': ['C', 'C♯', 'D', 'E♭', 'E', 'F', 'F♯', 'G', 'A♭', 'A', 'B♭', 'B'],
};
const _modeNames = {'uk': ('мажор', 'мінор'), 'ru': ('мажор', 'минор'), 'en': ('major', 'minor')};
final _parse = <(RegExp, int)>[
  (RegExp(r'^до[-\s]?(диез|дієз)'), 1),
  (RegExp(r'^ре[-\s]?бемоль'), 1),
  (RegExp(r'^до'), 0),
  (RegExp(r'^ре[-\s]?(диез|дієз)'), 3),
  (RegExp(r'^(ми|мі)[-\s]?бемоль'), 3),
  (RegExp(r'^ре'), 2),
  (RegExp(r'^(ми|мі)'), 4),
  (RegExp(r'^фа[-\s]?(диез|дієз)'), 6),
  (RegExp(r'^соль[-\s]?бемоль'), 6),
  (RegExp(r'^фа'), 5),
  (RegExp(r'^соль[-\s]?(диез|дієз)'), 8),
  (RegExp(r'^ля[-\s]?бемоль'), 8),
  (RegExp(r'^соль'), 7),
  (RegExp(r'^ля[-\s]?(диез|дієз)'), 10),
  (RegExp(r'^(си|сі)[-\s]?бемоль'), 10),
  (RegExp(r'^ля'), 9),
  (RegExp(r'^(си|сі)'), 11),
];

/// Назва тональності після транспонування; null — коли збірник пише щось складніше.
String? transposeKey(String tune, int semitones) {
  final t = tune.trim().toLowerCase();
  if (t.isEmpty || RegExp(r'[а-яіїє]\)').hasMatch(t)) return null;
  final minor = RegExp(r'минор|мінор').hasMatch(t);
  if (!minor && !t.contains('мажор')) return null;
  final hit = _parse.where((p) => p.$1.hasMatch(t)).firstOrNull;
  if (hit == null) return null;
  final lang = LangService.instance.lang;
  final names = _noteNames[lang] ?? _noteNames['uk']!;
  final modes = _modeNames[lang] ?? _modeNames['uk']!;
  return '${names[((hit.$2 + semitones) % 12 + 12) % 12]} ${minor ? modes.$2 : modes.$1}';
}
