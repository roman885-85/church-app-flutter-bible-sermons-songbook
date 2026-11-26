import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'fluidsynth.dart';
import '../i18n.dart';

const int midiSampleRate = 44100;

/// Що й як грати: одна пісня з одним набором вибору слухача.
class MidiRenderRequest {
  const MidiRenderRequest({
    required this.bankPath,
    required this.midiPath,
    required this.outPath,
    required this.frames,
    required this.mutedChannels,
    required this.programs,
    required this.transpose,
    required this.tempo,
    required this.gain,
  });

  final String bankPath;
  final String midiPath;

  /// Готовий файл; поки пишеться — поруч із суфіксом .part.
  final String outPath;

  /// Скільки кадрів буде у файлі (разом із «хвостом» після останньої ноти).
  final int frames;

  /// Канали без звуку (мелодія чи акомпанемент вимкнені).
  final Set<int> mutedChannels;

  /// Канал → програма, що замінює програму з файлу.
  final Map<int, int> programs;
  final int transpose;

  /// 1.0 — як у файлі, 1.2 — на п'яту частину швидше.
  final double tempo;

  /// Підсилення після FluidSynth (у нього самого 0,2) — своє для кожного звукового банку.
  final double gain;

  Map<String, Object> toMessage(int id) => {
        'cmd': 'render',
        'id': id,
        'bank': bankPath,
        'midi': midiPath,
        'out': '$outPath.$id.part',
        'final': outPath,
        'frames': frames,
        'muted': mutedChannels.fold<int>(0, (mask, ch) => mask | (1 << ch)),
        'programs': [for (var ch = 0; ch < 16; ch++) programs[ch] ?? -1],
        'transpose': transpose,
        'tempo': tempo,
        'gain': gain,
      };
}

/// Рендер, що йде (або вже скінчився): WAV-файл, який дописується на ходу.
class MidiRenderJob {
  MidiRenderJob._(this.id, this.path, this.finalPath, this.frames);

  final int id;

  /// Файл, що дописується (…part); щойно готовий — перейменовується у [finalPath].
  String path;
  final String finalPath;
  final int frames;

  int framesWritten = 0;
  bool done = false;
  bool cancelled = false;
  String? error;

  /// Скільки секунд звуку готово за секунду роботи — для журналу й підказок.
  double speed = 0;

  final _changed = StreamController<void>.broadcast();

  int get totalBytes => wavHeaderSize + frames * 4;
  int get bytesReady => done ? totalBytes : wavHeaderSize + framesWritten * 4;
  Duration get readyDuration => Duration(milliseconds: framesWritten * 1000 ~/ midiSampleRate);
  bool get failed => error != null || cancelled;

  void _notify() {
    if (!_changed.isClosed) _changed.add(null);
  }

  Future<void> _waitForMore() => _changed.stream.first.timeout(const Duration(milliseconds: 500), onTimeout: () {});

  /// Байти [start, end) — одразу те, що вже є, решта — щойно з'явиться.
  Stream<List<int>> read(int start, int end) async* {
    final file = await File(path).open();
    try {
      var pos = start;
      while (pos < end) {
        final ready = math.min(bytesReady, end);
        if (pos < ready) {
          await file.setPosition(pos);
          final chunk = await file.read(math.min(ready - pos, 256 * 1024));
          if (chunk.isEmpty) {
            await _waitForMore();
            continue;
          }
          pos += chunk.length;
          yield chunk;
        } else if (failed) {
          return;
        } else {
          await _waitForMore();
        }
      }
    } finally {
      await file.close();
    }
  }
}

/// Синтезатор мінусів у окремому isolate: FluidSynth пише пісню у WAV швидше,
/// ніж вона звучить, а програвач читає файл, поки той дописується.
class MidiRenderer {
  MidiRenderer._();
  static final MidiRenderer instance = MidiRenderer._();

  SendPort? _send;
  Future<void>? _starting;
  int _nextId = 1;
  final Map<int, MidiRenderJob> _jobs = {};

  Future<void> _ensure() {
    if (_send != null) return Future.value();
    return _starting ??= () async {
      final fromIsolate = ReceivePort();
      final ready = Completer<SendPort>();
      fromIsolate.listen((message) {
        if (message is SendPort) {
          ready.complete(message);
          return;
        }
        final m = message as Map;
        final job = _jobs[m['id']];
        if (job == null) return;
        if (m['frames'] is int) job.framesWritten = m['frames'] as int;
        if (m['speed'] is double) job.speed = m['speed'] as double;
        if (m['error'] != null) job.error = '${m['error']}';
        if (m['cancelled'] == true) job.cancelled = true;
        if (m['done'] == true) {
          if (m['path'] is String) job.path = m['path'] as String;
          job.done = true;
        }
        job._notify();
        if (job.done || job.failed) _jobs.remove(job.id);
      });
      await Isolate.spawn(_isolateMain, fromIsolate.sendPort, debugName: 'midi-synth');
      _send = await ready.future;
    }();
  }

  Future<MidiRenderJob> start(MidiRenderRequest request) async {
    await _ensure();
    final id = _nextId++;
    final job = MidiRenderJob._(id, '${request.outPath}.$id.part', request.outPath, request.frames);
    // Заголовок — одразу: програвач читає файл ще до того, як синтезатор
    // відкриє звуковий банк (на телефоні це кілька секунд).
    File(job.path).writeAsBytesSync(wavHeader(request.frames), flush: true);
    _jobs[id] = job;
    _send!.send(request.toMessage(id));
    return job;
  }

  /// Відкрити звуковий банк заздалегідь (екран мінусу відкрито — ▶ ось-ось натиснуть).
  Future<void> preload(String bankPath) async {
    await _ensure();
    _send!.send({'cmd': 'preload', 'bank': bankPath});
  }

  void cancel(MidiRenderJob job) {
    if (job.done || job.failed) return;
    _send?.send({'cmd': 'cancel', 'id': job.id});
  }
}

const int wavHeaderSize = 44;

Uint8List wavHeader(int frames) {
  final dataBytes = frames * 4;
  final b = ByteData(wavHeaderSize);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      b.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  b.setUint32(4, 36 + dataBytes, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, 2, Endian.little); // стерео
  b.setUint32(24, midiSampleRate, Endian.little);
  b.setUint32(28, midiSampleRate * 4, Endian.little);
  b.setUint16(32, 4, Endian.little);
  b.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  b.setUint32(40, dataBytes, Endian.little);
  return b.buffer.asUint8List();
}

// ── Isolate синтезатора ─────────────────────────────────────────────────────

void _isolateMain(SendPort toMain) {
  final commands = ReceivePort();
  toMain.send(commands.sendPort);
  final engine = _Engine(toMain);
  commands.listen((message) {
    final m = message as Map;
    switch (m['cmd']) {
      case 'render':
        engine.enqueue(m);
      case 'preload':
        engine.preload(m['bank'] as String);
      case 'cancel':
        engine.cancelled.add(m['id'] as int);
    }
  });
}

// Стан для перехоплення подій програвача FluidSynth: колбек — статична функція.
late FluidSynth _fs;
Pointer<Void> _cbSynth = nullptr;
int _cbMuted = 0;
List<int> _cbPrograms = List.filled(16, -1);
int _cbTranspose = 0;

/// Кожна подія MIDI-файла проходить тут: вимкнені партії мовчать, інструмент
/// слухача замінює той, що у файлі, ноти зсуваються на тональність (крім ударних).
int _onMidiEvent(Pointer<Void> data, Pointer<Void> event) {
  final type = _fs.eventType(event);
  final channel = _fs.eventChannel(event);
  switch (type) {
    case 0x90:
      if ((_cbMuted >> channel) & 1 == 1) return FluidSynth.ok;
      final key = _fs.eventKey(event) + (channel == 9 ? 0 : _cbTranspose);
      if (key < 0 || key > 127) return FluidSynth.ok;
      _fs.noteOn(_cbSynth, channel, key, _fs.eventVelocity(event));
      return FluidSynth.ok;
    case 0x80:
      final key = _fs.eventKey(event) + (channel == 9 ? 0 : _cbTranspose);
      if (key < 0 || key > 127) return FluidSynth.ok;
      _fs.noteOff(_cbSynth, channel, key);
      return FluidSynth.ok;
    case 0xa0:
      if (_cbTranspose != 0) return FluidSynth.ok;
    case 0xc0:
      final forced = _cbPrograms[channel];
      if (forced >= 0) {
        _fs.programChange(_cbSynth, channel, forced);
        return FluidSynth.ok;
      }
  }
  return _fs.handleMidiEvent(_cbSynth, event);
}

void _deleteQuietly(String path) {
  try {
    File(path).deleteSync();
  } catch (_) {}
}

class _Engine {
  _Engine(this.toMain) {
    _fs = FluidSynth.open();
    // Інформаційні повідомлення FluidSynth — не в журнал телефона.
    _fs.setLogFunction(FluidSynth.logInfo, nullptr, nullptr);
    _fs.setLogFunction(FluidSynth.logDebug, nullptr, nullptr);
  }

  final SendPort toMain;
  final Set<int> cancelled = {};
  final List<Map> _queue = [];
  bool _busy = false;
  Timer? _idle;

  Pointer<Void> _settings = nullptr;
  Pointer<Void> _synth = nullptr;
  String? _bank;
  int _sfont = -1;

  /// Межа, вище якої звук стискається обмежувачем.
  static const double _ceiling = 0.89; // −1 дБ

  void preload(String bank) {
    if (_busy || _bank == bank) return;
    _idle?.cancel();
    try {
      _ensureBank(bank);
    } catch (_) {}
    _idle = Timer(const Duration(minutes: 10), _release);
  }

  void enqueue(Map m) {
    // Нове замовлення скасовує всі ще не початі: слухач уже передумав.
    for (final old in _queue) {
      _deleteQuietly(old['out'] as String);
      toMain.send({'id': old['id'], 'cancelled': true});
    }
    _queue
      ..clear()
      ..add(m);
    if (!_busy) unawaited(_run());
  }

  Future<void> _run() async {
    _busy = true;
    _idle?.cancel();
    while (_queue.isNotEmpty) {
      final m = _queue.removeAt(0);
      await _render(m);
    }
    _busy = false;
    // Звуковий банк займає пам'ять: без роботи десять хвилин — звільняємо.
    _idle = Timer(const Duration(minutes: 10), _release);
  }

  void _release() {
    if (_busy) return;
    if (_synth != nullptr) _fs.deleteSynth(_synth);
    if (_settings != nullptr) _fs.deleteSettings(_settings);
    _synth = nullptr;
    _settings = nullptr;
    _bank = null;
    _sfont = -1;
  }

  bool _ensureBank(String path) {
    if (_synth == nullptr) {
      _settings = _fs.newSettings();
      _fs.setNum(_settings, 'synth.sample-rate', midiSampleRate.toDouble());
      _fs.setInt(_settings, 'synth.polyphony', 256);
      _fs.setInt(_settings, 'synth.lock-memory', 0);
      _fs.setStr(_settings, 'player.timing-source', 'sample');
      // Програми з вибору слухача ставляться до старту; скидання програвачем їх стерло б.
      _fs.setInt(_settings, 'player.reset-synth', 0);
      _synth = _fs.newSynth(_settings);
      if (_synth == nullptr) throw StateError(tr('FluidSynth не запустився'));
    }
    if (_bank == path) return true;
    if (_sfont >= 0) _fs.sfunload(_synth, _sfont, 1);
    _bank = null;
    _sfont = using((arena) => _fs.sfload(_synth, path.toNativeUtf8(allocator: arena), 1));
    if (_sfont < 0) return false;
    _bank = path;
    return true;
  }

  Future<void> _render(Map m) async {
    final id = m['id'] as int;
    if (cancelled.remove(id)) {
      _deleteQuietly(m['out'] as String);
      toMain.send({'id': id, 'cancelled': true});
      return;
    }
    Pointer<Void> player = nullptr;
    Pointer<Uint8> midiMem = nullptr;
    Pointer<Float> left = nullptr;
    Pointer<Float> right = nullptr;
    RandomAccessFile? out;
    final started = DateTime.now();
    try {
      final loadStarted = DateTime.now();
      if (!_ensureBank(m['bank'] as String)) {
        toMain.send({'id': id, 'error': tr('звуковий банк не відкрився')});
        return;
      }
      final loadMs = DateTime.now().difference(loadStarted).inMilliseconds;
      final midi = File(m['midi'] as String).readAsBytesSync();
      final frames = m['frames'] as int;

      _fs.systemReset(_synth);
      _cbSynth = _synth;
      _cbMuted = m['muted'] as int;
      _cbPrograms = List<int>.from(m['programs'] as List);
      _cbTranspose = m['transpose'] as int;
      for (var ch = 0; ch < 16; ch++) {
        if (_cbPrograms[ch] >= 0) _fs.programChange(_synth, ch, _cbPrograms[ch]);
      }

      player = _fs.newPlayer(_synth);
      midiMem = malloc<Uint8>(midi.length);
      midiMem.asTypedList(midi.length).setAll(0, midi);
      if (_fs.playerAddMem(player, midiMem, midi.length) != FluidSynth.ok) {
        toMain.send({'id': id, 'error': tr('файл мінусу пошкоджений')});
        return;
      }
      _fs.playerSetPlaybackCallback(player, Pointer.fromFunction<MidiEventHandler>(_onMidiEvent, FluidSynth.failed), nullptr);
      final tempo = (m['tempo'] as num).toDouble();
      if (tempo != 1.0) _fs.playerSetTempo(player, FluidSynth.tempoInternal, tempo);
      _fs.playerPlay(player);

      // Заголовок уже записав головний isolate — дописуємо звук після нього.
      final file = File(m['out'] as String).openSync(mode: FileMode.writeOnlyAppend);
      out = file;

      const block = 4096;
      left = malloc<Float>(block);
      right = malloc<Float>(block);
      final l = left.asTypedList(block);
      final r = right.asTypedList(block);
      final pcm = Int16List(block * 2);
      final pcmBytes = pcm.buffer.asUint8List();
      // Обмежувач: миттєва атака, відпускання за ~0,3 с.
      final release = math.exp(-1 / (0.3 * midiSampleRate));
      final makeup = (m['gain'] as num).toDouble();
      var envelope = 0.0;
      var written = 0;
      var silentTail = false;
      var peak = 0.0;
      var lastReport = 0;

      while (written < frames) {
        if (cancelled.remove(id)) {
          file.closeSync();
          out = null;
          _deleteQuietly(m['out'] as String);
          toMain.send({'id': id, 'cancelled': true});
          return;
        }
        final n = math.min(block, frames - written);
        if (silentTail) {
          pcm.fillRange(0, n * 2, 0);
        } else {
          _fs.writeFloat(_synth, n, left, 0, 1, right, 0, 1);
          for (var i = 0; i < n; i++) {
            final a = l[i] * makeup;
            final b = r[i] * makeup;
            final level = math.max(a.abs(), b.abs());
            if (level > peak) peak = level;
            envelope = level > envelope ? level : envelope * release;
            final g = envelope > _ceiling ? _ceiling / envelope : 1.0;
            pcm[2 * i] = (a * g * 32767).round().clamp(-32768, 32767);
            pcm[2 * i + 1] = (b * g * 32767).round().clamp(-32768, 32767);
          }
          // Пісня скінчилась і відзвучало все — решту файла заповнює тиша.
          if (_fs.playerStatus(player) != FluidSynth.playerPlaying && _fs.activeVoices(_synth) == 0) silentTail = true;
        }
        file.writeFromSync(pcmBytes, 0, n * 4);
        written += n;
        if (written - lastReport >= midiSampleRate || written >= frames) {
          lastReport = written;
          final elapsed = DateTime.now().difference(started).inMicroseconds / 1e6;
          toMain.send({'id': id, 'frames': written, 'speed': elapsed > 0 ? written / midiSampleRate / elapsed : 0.0});
          // Дати isolate прочитати «скасувати».
          await Future<void>.delayed(Duration.zero);
        }
      }
      file.closeSync();
      out = null;
      final finalPath = m['final'] as String;
      File(m['out'] as String).renameSync(finalPath);
      final elapsed = DateTime.now().difference(started).inMilliseconds;
      // ignore: avoid_print
      print('midi-synth: ${frames / midiSampleRate} s за $elapsed мс (банк $loadMs мс), пік ${(20 * math.log(math.max(peak, 1e-9)) / math.ln10).toStringAsFixed(1)} дБ');
      toMain.send({'id': id, 'frames': written, 'done': true, 'path': finalPath});
    } catch (e) {
      try {
        out?.closeSync();
      } catch (_) {}
      out = null;
      _deleteQuietly(m['out'] as String);
      toMain.send({'id': id, 'error': '$e'});
    } finally {
      out?.closeSync();
      if (player != nullptr) {
        _fs.playerStop(player);
        _fs.deletePlayer(player);
      }
      if (midiMem != nullptr) malloc.free(midiMem);
      if (left != nullptr) malloc.free(left);
      if (right != nullptr) malloc.free(right);
    }
  }
}
