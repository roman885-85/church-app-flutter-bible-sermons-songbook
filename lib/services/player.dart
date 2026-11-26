import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../api/api.dart';
import '../api/models.dart';
import 'library.dart';
import '../i18n.dart';

/// Що зараз грає: проповідь або глава аудіо-Біблії.
class NowPlaying {
  NowPlaying({
    required this.key,
    required this.title,
    required this.subtitle,
    this.artUrl,
    this.sermon,
    this.chapter,
    this.audio,
    this.songUrl,
    this.replay,
  });

  final String key;
  final String title;
  final String subtitle;
  final String? artUrl;
  final Sermon? sermon;
  final BibleChapter? chapter;
  final ChapterAudio? audio;
  /// Запис до пісні з пісенника (фонограма чи спів).
  final String? songUrl;

  /// Мінус із синтезатора застосунку: як завантажити його заново після збою.
  final Future<void> Function()? replay;
}

/// Відтворення звуку з сервера церкви — у фоні, на заблокованому екрані, з
/// кнопками в сповіщенні. Звук лише свій: проповіді й аудіо-Біблія лежать на
/// baptist.com.ua, тож фон законний (на відміну від відео YouTube).
class PlayerService extends ChangeNotifier {
  PlayerService(this._library, this._api);

  final LibraryService _library;
  final Api _api;
  final AudioPlayer player = AudioPlayer();

  /// Росте щоразу, як черга замінюється (інша проповідь, глава, зупинка): довга
  /// дозагрузка наступної глави, що почалася для старої черги, нічого не допише в нову.
  int _generation = 0;
  Future<void>? _appendTask;

  List<NowPlaying> _queue = const [];
  NowPlaying? get current {
    final index = player.currentIndex;
    if (index == null || index < 0 || index >= _queue.length) return null;
    return _queue[index];
  }

  double get speed => player.speed;
  final List<StreamSubscription<dynamic>> _subs = [];
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);

  /// Що пішло не так востаннє (немає мережі, файл недоступний) — показується під плеєром.
  String? error;

  /// Таймер сну: зупинитися о вказаній миті або наприкінці запису.
  Timer? _sleepTimer;
  DateTime? sleepAt;
  bool sleepAtEnd = false;

  Future<void> init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    _subs.add(player.currentIndexStream.listen((index) {
      final now = current;
      if (now?.sermon != null) unawaited(_library.recordPlayed(now!.sermon!));
      // Аудіо-Біблія читається далі сама: коли звучить остання глава в черзі,
      // дописуємо наступну.
      if (now?.chapter != null && index == _queue.length - 1) unawaited(_appendNextChapter());
      notifyListeners();
    }));
    _subs.add(player.playerStateStream.listen(onError: (Object _) {}, (state) {
      final idle = state.processingState == ProcessingState.idle;
      if (!idle && (!state.playing || state.processingState == ProcessingState.completed)) unawaited(_saveNow(notify: true));
      notifyListeners();
    }));
    _subs.add(player.positionDiscontinuityStream.listen((event) {
      // Запис скінчився і почався наступний у черзі — «до кінця запису» спрацьовує тут.
      if (sleepAtEnd && event.reason == PositionDiscontinuityReason.autoAdvance) {
        unawaited(player.pause());
        cancelSleep();
      }
    }));
    _subs.add(player.processingStateStream.listen((state) {
      if (sleepAtEnd && state == ProcessingState.completed) cancelSleep();
      // Глава скінчилась, а наступна ще не встигла дописатись (не було мережі) —
      // пробуємо ще раз; щойно допишеться, заграє сама.
      if (state == ProcessingState.completed && current?.chapter != null) unawaited(_appendNextChapter());
    }));
    _subs.add(player.positionStream.listen((position) {
      if (DateTime.now().difference(_lastSave) > const Duration(seconds: 10)) unawaited(_saveNow());
    }, onError: (Object _) {}));
    // Помилки відтворення приходять сюди. Місце вже збережене (щоразу за 10 с
    // гри) — тут його не пишемо: після збою плеєр може показувати нуль.
    _subs.add(player.playbackEventStream.listen((_) {
      if (error != null && player.playing) {
        error = null;
        notifyListeners();
      }
    }, onError: (Object err, StackTrace _) {
      error = tr('Не вдалося відтворити запис. Перевірте інтернет і натисніть ▶ ще раз.');
      notifyListeners();
    }));
  }

  Future<void> _saveNow({bool notify = false}) async {
    _lastSave = DateTime.now();
    final sermon = current?.sermon;
    if (sermon == null) return;
    await _library.savePosition(sermon.id, player.position, total: player.duration, notify: notify);
  }

  Future<AudioSource> _sermonSource(Sermon s) async {
    final local = await _library.localPath(s.id);
    final tag = MediaItem(
      id: 'sermon:${s.id}',
      title: s.title,
      artist: s.preacher.isEmpty ? tr('Церква «Відродження»') : s.preacher,
      album: tr('Проповіді'),
      artUri: s.coverUrl != null ? Uri.parse(s.coverUrl!) : null,
      duration: s.duration > 0 ? Duration(seconds: s.duration) : null,
    );
    return local != null ? AudioSource.file(local, tag: tag) : AudioSource.uri(Uri.parse(s.audioUrl), tag: tag);
  }

  /// Грати проповідь; решта списку — черга далі.
  Future<void> playSermons(List<Sermon> list, int index) async {
    if (list.isEmpty) return;
    final chosen = list[index];
    if (current?.key == 'sermon:${chosen.id}' && error == null && player.processingState != ProcessingState.idle) {
      await player.play();
      return;
    }
    error = null;
    _generation++;
    // Черга — від вибраної і не довша за 50 записів: список з 600 проповідей
    // у плеєр ніхто не слухає підряд, а кожен запис — робота для плеєра.
    final slice = list.sublist(index, (index + 50).clamp(0, list.length));
    _queue = [
      for (final s in slice)
        NowPlaying(key: 'sermon:${s.id}', title: s.title, subtitle: s.preacher, artUrl: s.coverUrl, sermon: s),
    ];
    final sources = [for (final s in slice) await _sermonSource(s)];
    final resume = _library.positionOf(chosen.id);
    notifyListeners();
    try {
      await player.setAudioSources(sources, initialIndex: 0, initialPosition: resume);
      unawaited(player.play());
    } catch (_) {
      error = tr('Не вдалося відтворити запис. Перевірте інтернет і натисніть ▶ ще раз.');
    }
    notifyListeners();
  }

  static String _chapterKey(BibleChapter c, ChapterAudio a) => 'bible:${c.translation}:${c.bookNr}:${c.chapter}:${a.setCode}';

  NowPlaying _chapterItem(BibleChapter chapter, ChapterAudio audio) => NowPlaying(
        key: _chapterKey(chapter, audio),
        title: '${chapter.bookName} ${chapter.chapter}',
        subtitle: audio.narrator.isNotEmpty ? audio.narrator : audio.title,
        chapter: chapter,
        audio: audio,
      );

  AudioSource _chapterSource(NowPlaying item) => AudioSource.uri(
        Uri.parse(item.audio!.url),
        tag: MediaItem(
          id: item.key,
          title: item.title,
          artist: item.subtitle.isNotEmpty ? item.subtitle : tr('Аудіо-Біблія'),
          album: tr('Біблія'),
          duration: item.audio!.duration > 0 ? Duration(seconds: item.audio!.duration) : null,
        ),
      );

  /// Слухати главу (з [from] — наприклад, з вибраного вірша), далі — наступні глави.
  Future<void> playChapter(BibleChapter chapter, ChapterAudio audio, {Duration? from}) async {
    final item = _chapterItem(chapter, audio);
    if (current?.key == item.key && error == null && player.processingState != ProcessingState.idle) {
      if (from != null) await player.seek(from);
      await player.play();
      return;
    }
    error = null;
    _generation++;
    _queue = [item];
    notifyListeners();
    try {
      await player.setAudioSources([_chapterSource(item)], initialIndex: 0, initialPosition: from ?? Duration.zero);
      unawaited(player.play());
      unawaited(_appendNextChapter());
    } catch (_) {
      error = tr('Не вдалося відтворити запис. Перевірте інтернет і натисніть ▶ ще раз.');
    }
    notifyListeners();
  }

  /// Дописати в чергу наступну главу того самого читця.
  ///
  /// Глави без запису цього читця пропускаються (до дванадцяти поспіль — далі
  /// хіба кінець перекладу); сайт недоступний — ще дві спроби з паузою. Якщо
  /// поточна глава вже скінчилась, поки йшов запит, дописана одразу грає.
  Future<void> _appendNextChapter() {
    if (!_library.bibleContinuous || _queue.isEmpty || _queue.last.chapter == null) return Future.value();
    final running = _appendTask;
    if (running != null) return running;
    final generation = _generation;
    final task = _appendFor(generation);
    _appendTask = task;
    return task.whenComplete(() {
      _appendTask = null;
      // Поки дописували для старої черги, з'явилась нова — допишемо вже для неї.
      if (generation != _generation) unawaited(_appendNextChapter());
    });
  }

  Future<void> _appendFor(int generation) async {
    final last = _queue.last;
    final audio = last.audio;
    var from = last.chapter;
    if (audio == null || from == null) return;
    bool stale() => generation != _generation || _queue.isEmpty || !identical(_queue.last, last);
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        var hops = 0;
        while (from!.next != null && hops < 12) {
          final next = await _api.chapter(from.translation, from.next!.bookNr, from.next!.chapter);
          if (stale()) return;
          final nextAudio = next.audio.where((a) => a.setCode == audio.setCode).firstOrNull;
          if (nextAudio != null) {
            final item = _chapterItem(next, nextAudio);
            final finished = player.processingState == ProcessingState.completed;
            _queue = [..._queue, item];
            await player.addAudioSource(_chapterSource(item));
            if (finished && !stale()) {
              await player.seek(Duration.zero, index: _queue.length - 1);
              unawaited(player.play());
            }
            notifyListeners();
            return;
          }
          from = next;
          hops++;
        }
        return; // кінець перекладу — зупиняємось
      } catch (_) {
        if (attempt == 2) return;
        await Future<void>.delayed(Duration(seconds: 5 * (attempt + 1)));
        if (stale()) return;
      }
    }
  }

  static String songKey(String url) => 'song:$url';

  /// Фонограма чи запис співу до пісні — у фоні, з кнопками в сповіщенні, як проповідь.
  Future<void> playSongRecording({required String url, required String title, required String subtitle}) async {
    final item = NowPlaying(key: songKey(url), title: title, subtitle: subtitle, songUrl: url);
    if (current?.key == item.key && error == null && player.processingState != ProcessingState.idle) {
      await player.play();
      return;
    }
    error = null;
    _generation++;
    _queue = [item];
    notifyListeners();
    try {
      await player.setAudioSources([
        AudioSource.uri(Uri.parse(url), tag: MediaItem(id: item.key, title: title, artist: subtitle, album: tr('Пісенник'))),
      ], initialIndex: 0, initialPosition: Duration.zero);
      unawaited(player.play());
    } catch (_) {
      error = tr('Не вдалося відтворити запис. Перевірте інтернет і натисніть ▶ ще раз.');
    }
    notifyListeners();
  }

  /// Мінус пісні з синтезатора застосунку (services/midi.dart). Джерело — уже
  /// готовий файл або той, що синтезатор ще дописує.
  Future<void> playMidi({
    required String key,
    required AudioSource source,
    required String title,
    required String subtitle,
    required Future<void> Function() replay,
    Duration position = Duration.zero,
    bool autoplay = true,
  }) async {
    error = null;
    _generation++;
    _queue = [NowPlaying(key: key, title: title, subtitle: subtitle, replay: replay)];
    notifyListeners();
    try {
      await player.setAudioSources([source], initialIndex: 0, initialPosition: position);
      if (autoplay) unawaited(player.play());
    } catch (_) {
      error = tr('Не вдалося відтворити мінус. Натисніть ▶ ще раз.');
    }
    notifyListeners();
  }

  bool isCurrentSermon(int id) => current?.key == 'sermon:$id';

  bool isCurrentChapter(BibleChapter chapter) {
    final now = current;
    return now?.chapter != null &&
        now!.chapter!.translation == chapter.translation &&
        now.chapter!.bookNr == chapter.bookNr &&
        now.chapter!.chapter == chapter.chapter;
  }

  Future<void> seek(Duration position) => player.seek(position);

  void setSleepTimer(Duration? after, {bool atEnd = false}) {
    _sleepTimer?.cancel();
    sleepAtEnd = atEnd;
    sleepAt = after == null ? null : DateTime.now().add(after);
    if (after != null) {
      _sleepTimer = Timer(after, () {
        unawaited(player.pause());
        cancelSleep();
      });
    }
    notifyListeners();
  }

  void cancelSleep() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepAt = null;
    sleepAtEnd = false;
    notifyListeners();
  }

  Future<void> toggle() async {
    if (error != null || player.processingState == ProcessingState.idle) {
      await retry();
      return;
    }
    await (player.playing ? player.pause() : player.play());
  }

  /// Після помилки плеєр порожній: завантажуємо ту саму чергу заново з місця зупинки.
  Future<void> retry() async {
    final items = _queue;
    if (items.isEmpty) return;
    final index = (player.currentIndex ?? 0).clamp(0, items.length - 1);
    final now = items[index];
    final position = player.position;
    error = null;
    _queue = const [];
    if (now.sermon != null) {
      await playSermons([for (final item in items) if (item.sermon != null) item.sermon!], index);
    } else if (now.chapter != null && now.audio != null) {
      await playChapter(now.chapter!, now.audio!, from: position);
    } else if (now.songUrl != null) {
      await playSongRecording(url: now.songUrl!, title: now.title, subtitle: now.subtitle);
    } else if (now.replay != null) {
      _queue = items;
      await now.replay!();
    }
  }

  Future<void> skip(Duration by) async {
    final duration = player.duration ?? Duration.zero;
    var target = player.position + by;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    await player.seek(target);
  }

  Future<void> setSpeed(double value) async {
    await player.setSpeed(value);
    notifyListeners();
  }

  Future<void> stop() async {
    await _saveNow(notify: true);
    await player.stop();
    _generation++;
    _queue = const [];
    notifyListeners();
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    for (final sub in _subs) {
      sub.cancel();
    }
    player.dispose();
    super.dispose();
  }
}
