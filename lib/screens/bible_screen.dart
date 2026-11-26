import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../services/library.dart';
import '../services/player.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/picker_button.dart';
import '../widgets/top_actions.dart';
import 'bible_extras.dart';
import '../i18n.dart';

/// Біблія — та сама, що на сайті: переклади, паралельний переклад, аудіо з
/// підсвічуванням вірша, коментарі, словники, пошук.
class BibleScreen extends StatefulWidget {
  const BibleScreen({super.key});

  @override
  State<BibleScreen> createState() => _BibleScreenState();
}

class _BibleScreenState extends State<BibleScreen> {
  late final Api _api = context.read<Api>();
  late final LibraryService _library = context.read<LibraryService>();
  late final PlayerService _player = context.read<PlayerService>();

  BibleInfo? _info;
  String? _error;
  String _translation = 'cuv23';
  String? _parallel;
  List<BibleBook> _books = const [];
  int _bookNr = 1;
  int _chapter = 1;
  BibleChapter? _data;
  bool _loading = true;
  double _font = 18;
  int _audioIndex = 0;

  /// Вірш, що зараз звучить, — підсвічується і прокручується на екран.
  final ValueNotifier<int?> _audioVerse = ValueNotifier(null);
  final ValueNotifier<int?> _selected = ValueNotifier(null);
  final Map<int, GlobalKey> _keys = {};
  final ScrollController _scroll = ScrollController();
  DateTime _userScrolledAt = DateTime.fromMillisecondsSinceEpoch(0);
  StreamSubscription<Duration>? _positionSub;
  String? _lastPlayingKey;

  /// Коментарі до поточної глави — підвантажуються, коли їх вперше попросять.
  Future<List<Commentary>>? _commentaries;

  @override
  void initState() {
    super.initState();
    _font = _library.bibleFont;
    _parallel = _library.bibleParallel;
    _positionSub = _player.player.positionStream.listen(_onPosition);
    _player.addListener(_onPlayer);
    _start(fromInit: true);
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _player.removeListener(_onPlayer);
    _scroll.dispose();
    _audioVerse.dispose();
    _selected.dispose();
    super.dispose();
  }

  Future<void> _start({bool fromInit = false}) async {
    if (!fromInit) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final info = await _api.bible();
      final codes = info.translations.map((t) => t.code).toSet();
      final last = _library.lastReading;
      _info = info;
      _translation = last != null && codes.contains(last.$1)
          ? last.$1
          : info.defaults.firstWhere(codes.contains, orElse: () => codes.contains('cuv23') ? 'cuv23' : codes.first);
      if (_parallel != null && !codes.contains(_parallel)) _parallel = null;
      _books = await _api.books(_translation);
      if (last != null && _books.any((b) => b.bookNr == last.$2)) {
        _bookNr = last.$2;
        _chapter = last.$3;
      } else {
        final start = _books.where((b) => b.slug == info.startBook).firstOrNull ?? _books.firstOrNull;
        _bookNr = start?.bookNr ?? 1;
        _chapter = info.startChapter;
      }
      await _load(_bookNr, _chapter);
    } catch (err) {
      if (mounted) {
        setState(() {
          _error = err is ApiException ? err.message : tr('Не вдалося відкрити Біблію');
          _loading = false;
        });
      }
    }
  }

  BibleBook? get _book => _books.where((b) => b.bookNr == _bookNr).firstOrNull;

  Translation? _translationOf(String? code) => _info?.translations.where((t) => t.code == code).firstOrNull;

  Future<void> _load(int bookNr, int chapter, {int? verse, bool keepScroll = false}) async {
    setState(() => _loading = true);
    try {
      final data = await _api.chapter(_translation, bookNr, chapter, parallel: _parallel);
      if (!mounted) return;
      final previousSet = _data != null && _data!.audio.length > _audioIndex ? _data!.audio[_audioIndex].setCode : null;
      setState(() {
        _data = data;
        _bookNr = bookNr;
        _chapter = chapter;
        _loading = false;
        _error = null;
        _keys.clear();
        _commentaries = null;
        _selected.value = verse;
        final same = data.audio.indexWhere((a) => a.setCode == previousSet);
        _audioIndex = same >= 0 ? same : 0;
      });
      _syncAudioVerse();
      unawaited(_library.saveReading(_translation, bookNr, chapter));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (verse != null) {
          _scrollToVerse(verse, animate: false);
        } else if (!keepScroll && _scroll.hasClients) {
          _scroll.jumpTo(0);
        }
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = err is ApiException ? err.message : tr('Не вдалося завантажити главу');
      });
    }
  }

  Future<void> _setTranslation(String code) async {
    if (code == _translation) return;
    _translation = code;
    if (_parallel == code) {
      _parallel = null;
      unawaited(_library.setBibleParallel(null));
    }
    setState(() => _loading = true);
    try {
      _books = await _api.books(code);
      var book = _books.where((b) => b.bookNr == _bookNr).firstOrNull;
      var chapter = _chapter;
      if (book == null) {
        book = _books.firstOrNull;
        chapter = 1;
      }
      if (book != null && !book.chapters.contains(chapter)) chapter = book.chapters.isEmpty ? 1 : book.chapters.first;
      await _load(book?.bookNr ?? 1, chapter);
    } catch (err) {
      if (mounted) setState(() => _loading = false);
      if (mounted) showSnack(context, tr('Не вдалося відкрити переклад'));
    }
  }

  // ── Аудіо ──

  ChapterAudio? get _audio {
    final list = _data?.audio ?? const <ChapterAudio>[];
    return list.isEmpty ? null : list[_audioIndex.clamp(0, list.length - 1)];
  }

  bool get _playingThisChapter => _data != null && _player.isCurrentChapter(_data!);

  void _onPosition(Duration position) {
    if (!_playingThisChapter) {
      if (_audioVerse.value != null) _audioVerse.value = null;
      return;
    }
    final verse = _player.current?.audio?.verseAt(position);
    if (verse != _audioVerse.value) {
      _audioVerse.value = verse;
      if (verse != null && DateTime.now().difference(_userScrolledAt) > const Duration(seconds: 5)) {
        _scrollToVerse(verse);
      }
    }
  }

  void _syncAudioVerse() => _onPosition(_player.player.position);

  /// Глава, до якої читанка йде слідом за голосом: поки вона вантажиться (або
  /// не завантажилась без мережі), читанка все одно вважається «тут».
  BibleChapter? _pendingFollow;

  /// Аудіо перейшло до наступної глави — читанка йде слідом, якщо ми слухали цю.
  void _onPlayer() {
    final now = _player.current;
    final key = now?.key;
    if (key == _lastPlayingKey) return;
    bool shows(BibleChapter? c) => c != null && _lastPlayingKey!.startsWith('bible:${c.translation}:${c.bookNr}:${c.chapter}:');
    final wasHere = _lastPlayingKey != null && (shows(_data) || shows(_pendingFollow));
    _lastPlayingKey = key;
    final next = now?.chapter;
    if (wasHere && next != null && next.translation == _translation && mounted) {
      _pendingFollow = next;
      unawaited(_load(next.bookNr, next.chapter).whenComplete(() {
        if (!mounted) return;
        if (_data?.bookNr == next.bookNr && _data?.chapter == next.chapter) _pendingFollow = null;
        setState(() {});
      }));
    }
  }

  void _scrollToVerse(int verse, {bool animate = true}) {
    final ctx = _keys[verse]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.3,
      duration: animate ? const Duration(milliseconds: 450) : Duration.zero,
      curve: Curves.easeInOut,
    );
  }

  Duration? _startOf(int verse) {
    final audio = _audio;
    if (audio == null) return null;
    for (final (v, start) in audio.verseStarts) {
      if (v == verse) return Duration(milliseconds: (start * 1000).round());
    }
    return null;
  }

  Future<void> _playAudio({int? fromVerse}) async {
    final data = _data;
    final audio = _audio;
    if (data == null || audio == null) return;
    final from = fromVerse != null ? _startOf(fromVerse) : null;
    await _player.playChapter(data, audio, from: from);
  }

  // ── Навігація ──

  Future<void> _openPicker() async {
    final place = await Navigator.of(context).push<BiblePlace>(
      MaterialPageRoute(builder: (_) => BookPickerScreen(books: _books, currentBook: _bookNr)),
    );
    if (place != null) await _load(place.bookNr, place.chapter, verse: place.verse);
  }

  /// Розділ поточної книги — сіткою номерів, одним дотиком.
  Future<void> _pickChapter(BibleBook book) async {
    final p = context.palette;
    final chosen = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: book.chapters.length > 40 ? 0.75 : 0.5,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(controller: controller, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(tr('{a}: розділ', {'a': book.name}), style: heading(context, size: 24)),
          ),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in book.chapters)
              SizedBox(
                width: 56,
                height: 48,
                child: c == _chapter
                    ? FilledButton(
                        style: FilledButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        onPressed: () => Navigator.pop(context, c),
                        child: Text('$c'),
                      )
                    : OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          foregroundColor: p.foreground,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => Navigator.pop(context, c),
                        child: Text('$c'),
                      ),
              ),
          ]),
        ]),
      ),
    );
    if (chosen != null && chosen != _chapter) await _load(book.bookNr, chosen);
  }

  Future<void> _openSearch() async {
    final place = await Navigator.of(context).push<BiblePlace>(
      MaterialPageRoute(
        builder: (_) => BibleSearchScreen(translation: _translation, translationTitle: _translationOf(_translation)?.title ?? ''),
      ),
    );
    if (place != null) await _load(place.bookNr, place.chapter, verse: place.verse);
  }

  Future<void> _chooseTranslation({required bool parallel}) async {
    final info = _info;
    if (info == null) return;
    final byLang = <String, List<Translation>>{};
    for (final t in info.translations) {
      byLang.putIfAbsent(t.lang, () => []).add(t);
    }
    final langNames = {'uk': tr('Українською'), 'ru': tr('Російською'), 'en': tr('Англійською'), 'el': tr('Грецькою'), 'he': tr('Івритом')};
    final current = parallel ? _parallel : _translation;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(controller: controller, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(parallel ? tr('Паралельний переклад') : tr('Переклад'), style: heading(context, size: 24)),
          ),
          if (parallel)
            ListTile(
              leading: const Icon(Icons.close),
              title: Text(tr('Без паралельного перекладу')),
              trailing: current == null ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, ''),
            ),
          for (final entry in (byLang.entries.toList()..sort((a, b) => a.key == 'uk' ? -1 : (b.key == 'uk' ? 1 : 0)))) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Text((langNames[entry.key] ?? entry.key).toUpperCase(),
                  style: TextStyle(fontSize: 11, letterSpacing: 1.6, color: context.palette.accent)),
            ),
            for (final t in entry.value)
              if (!parallel || t.code != _translation)
                ListTile(
                  title: Text(t.title),
                  subtitle: Text(t.abbrev),
                  trailing: t.code == current ? Icon(Icons.check, color: context.palette.primary) : null,
                  onTap: () => Navigator.pop(context, t.code),
                ),
          ],
          const SizedBox(height: 24),
        ]),
      ),
    );
    if (chosen == null) return;
    if (parallel) {
      _parallel = chosen.isEmpty ? null : chosen;
      unawaited(_library.setBibleParallel(_parallel));
      await _load(_bookNr, _chapter, keepScroll: true);
    } else {
      await _setTranslation(chosen);
    }
  }

  Future<void> _textSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Розмір тексту'), style: heading(context, size: 22)),
              Row(children: [
                const Icon(Icons.text_decrease),
                Expanded(
                  child: Slider(
                    min: 14,
                    max: 30,
                    divisions: 8,
                    value: _font,
                    onChanged: (v) {
                      setSheet(() {});
                      setState(() => _font = v);
                    },
                    onChangeEnd: _library.setBibleFont,
                  ),
                ),
                const Icon(Icons.text_increase),
              ]),
              Text(tr('На початку створив Бог небо та землю.'), style: TextStyle(fontSize: _font, height: 1.6)),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _openVerse(BibleVerse verse) async {
    final data = _data;
    if (data == null) return;
    _selected.value = verse.verse;
    final parallel = data.parallel.where((v) => v.verse == verse.verse).firstOrNull;
    _commentaries ??= _api.chapter(_translation, data.bookNr, data.chapter, commentaries: true).then((c) => c.commentaries).catchError(
      (Object err) {
        _commentaries = null; // наступного разу спробуємо ще
        throw err;
      },
    );
    final place = await showModalBottomSheet<BiblePlace>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _VerseSheet(
        chapter: data,
        verse: verse,
        parallel: parallel,
        parallelTitle: _translationOf(data.parallelTranslation)?.abbrev,
        translationTitle: _translationOf(_translation)?.abbrev ?? '',
        commentaries: _commentaries!,
        canListen: _startOf(verse.verse) != null,
        onListen: () => _playAudio(fromVerse: verse.verse),
        books: _books,
        dictionaryEndpoint: _info?.dictionaryEndpoint ?? '',
      ),
    );
    if (mounted) _selected.value = null;
    if (place != null) await _load(place.bookNr, place.chapter, verse: place.verse);
  }

  // ── Вигляд ──

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    context.watch<PlayerService>();
    final data = _data;
    final book = _book;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Біблія')),
        // Угорі — як в інших розділах: «Ефір», пошук (тут — у тексті Біблії) і повне
        // меню; паралельний переклад і розмір тексту — у «⋮».
        actions: [
          const LivePill(),
          IconButton(tooltip: tr('Пошук у Біблії'), onPressed: _info == null ? null : _openSearch, icon: const Icon(Icons.search)),
          PopupMenuButton<String>(
            tooltip: tr('Ще'),
            onSelected: (value) {
              if (value == 'parallel') _chooseTranslation(parallel: true);
              if (value == 'font') _textSettings();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'parallel',
                enabled: _info != null,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.view_agenda_outlined, color: _parallel != null ? p.primary : null),
                  title: Text(_parallel != null
                      ? tr('Паралельно: {a}', {'a': _translationOf(_parallel)?.abbrev ?? _parallel})
                      : tr('Паралельний переклад')),
                ),
              ),
              PopupMenuItem(
                value: 'font',
                child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.format_size), title: Text(tr('Розмір тексту'))),
              ),
            ],
          ),
          IconButton(tooltip: tr('Меню'), icon: const Icon(Icons.menu), onPressed: () => openMenu(context)),
        ],
        // Книга, розділ і переклад — помітними кнопками, однаковими в усьому застосунку.
        // Великий шрифт телефона (понад 125 %): три кнопки в рядок різали підписи до «Ро…» й «Пере…»,
        // тож книга — окремим рядком на всю ширину, розділ і переклад — другим. Висота — від шрифту.
        bottom: () {
          final ts = MediaQuery.textScalerOf(context);
          // Android 14+ масштабує шрифт нелінійно: великі розміри ростуть менше, тож міряємо на розмірі тексту.
          final big = ts.scale(14) > 14 * 1.25;
          final pickerHeight = math.max(48.0, 1.2 * ts.scale(11) + 1.25 * ts.scale(15) + 12);
          final bookPicker = PickerButton(
            caption: tr('Книга'),
            value: book?.name ?? '…',
            icon: Icons.menu_book_outlined,
            onPressed: _books.isEmpty ? null : _openPicker,
          );
          final chapterPicker = PickerButton(
            caption: tr('Розділ'),
            value: '$_chapter',
            onPressed: book == null || book.chapters.length < 2 ? null : () => _pickChapter(book),
          );
          final translationPicker = PickerButton(
            caption: tr('Переклад'),
            value: _translationOf(_translation)?.abbrev ?? _translation,
            onPressed: _info == null ? null : () => _chooseTranslation(parallel: false),
          );
          return PreferredSize(
            preferredSize: Size.fromHeight(big ? 2 * pickerHeight + 8 + 8 : math.max(60.0, pickerHeight + 8)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: big
                  ? Column(children: [
                      SizedBox(width: double.infinity, child: bookPicker),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(flex: 3, child: chapterPicker),
                        const SizedBox(width: 8),
                        Expanded(flex: 4, child: translationPicker),
                      ]),
                    ])
                  : Row(children: [
                      Expanded(flex: 5, child: bookPicker),
                      const SizedBox(width: 8),
                      Expanded(flex: 3, child: chapterPicker),
                      const SizedBox(width: 8),
                      Expanded(flex: 4, child: translationPicker),
                    ]),
            ),
          );
        }(),
      ),
      body: _body(context, data),
    );
  }

  Widget _body(BuildContext context, BibleChapter? data) {
    final p = context.palette;
    if (data == null) {
      if (_error != null) return ErrorView(message: _error!, onRetry: () => _start());
      return LoadingView(label: tr('Відкриваємо Біблію…'));
    }

    final parallel = {for (final v in data.parallel) v.verse: v};
    return Column(children: [
      if (_loading) const LinearProgressIndicator(minHeight: 2),
      if (data.audio.isNotEmpty) _audioBar(context, data),
      Expanded(
        child: NotificationListener<UserScrollNotification>(
          onNotification: (_) {
            _userScrolledAt = DateTime.now();
            return false;
          },
          child: GestureDetector(
            onHorizontalDragEnd: (details) {
              final v = details.primaryVelocity ?? 0;
              if (v < -500 && data.next != null) _load(data.next!.bookNr, data.next!.chapter);
              if (v > 500 && data.prev != null) _load(data.prev!.bookNr, data.prev!.chapter);
            },
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              itemCount: data.verses.length + 2,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(children: [
                      Text(data.bookName, textAlign: TextAlign.center, style: heading(context, size: 30)),
                      Text(tr('Розділ {a}', {'a': data.chapter}), style: TextStyle(color: p.mutedForeground, letterSpacing: 1.2)),
                      if (data.parallelTranslation != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${_translationOf(_translation)?.abbrev ?? _translation} · ${_translationOf(data.parallelTranslation)?.abbrev ?? data.parallelTranslation}',
                            style: TextStyle(fontSize: 12, color: p.mutedForeground),
                          ),
                        ),
                    ]),
                  );
                }
                if (i == data.verses.length + 1) return _chapterNav(context, data);
                final verse = data.verses[i - 1];
                final key = _keys.putIfAbsent(verse.verse, () => GlobalKey());
                return _VerseView(
                  key: key,
                  verse: verse,
                  parallel: parallel[verse.verse],
                  font: _font,
                  audioVerse: _audioVerse,
                  selected: _selected,
                  onTap: () => _openVerse(verse),
                );
              },
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _audioBar(BuildContext context, BibleChapter data) {
    final p = context.palette;
    final audio = _audio!;
    // «Тут» — звучить саме ця глава цим читцем, або голос уже пішов далі, а
    // читанка ще не догнала: ▶ тоді ставить на паузу, а не починає стару главу.
    final here = (_playingThisChapter && _player.current?.audio?.setCode == audio.setCode) ||
        (_pendingFollow != null && _player.current?.chapter != null);
    final playing = here && _player.player.playing;
    return Material(
      color: p.card,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
        child: Row(children: [
          IconButton(
            iconSize: 34,
            color: p.primary,
            onPressed: () => here ? _player.toggle() : _playAudio(),
            icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_filled),
          ),
          Expanded(
            child: InkWell(
              onTap: data.audio.length < 2
                  ? null
                  : () async {
                      final chosen = await showModalBottomSheet<int>(
                        context: context,
                        showDragHandle: true,
                        builder: (context) => SafeArea(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            for (var i = 0; i < data.audio.length; i++)
                              ListTile(
                                title: Text(data.audio[i].title),
                                subtitle: Text(data.audio[i].narrator),
                                trailing: i == _audioIndex ? const Icon(Icons.check) : null,
                                onTap: () => Navigator.pop(context, i),
                              ),
                          ]),
                        ),
                      );
                      if (chosen != null) setState(() => _audioIndex = chosen);
                    },
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(here ? tr('Звучить {a} {b}', {'a': data.bookName, 'b': data.chapter}) : tr('Слухати розділ'),
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                Row(children: [
                  Flexible(
                    child: Text(
                      [audio.narrator, if (audio.duration > 0) humanDuration(audio.duration)].where((e) => e.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: p.mutedForeground),
                    ),
                  ),
                  if (data.audio.length > 1) Icon(Icons.arrow_drop_down, size: 18, color: p.mutedForeground),
                ]),
              ]),
            ),
          ),
          if (here)
            IconButton(onPressed: () => _player.skip(const Duration(seconds: -10)), icon: const Icon(Icons.replay_10)),
        ]),
      ),
    );
  }

  Widget _chapterNav(BuildContext context, BibleChapter data) => Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Row(children: [
          if (data.prev != null)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _load(data.prev!.bookNr, data.prev!.chapter),
                icon: const Icon(Icons.chevron_left),
                label: Text(tr('Попередній')),
              ),
            ),
          if (data.prev != null && data.next != null) const SizedBox(width: 12),
          if (data.next != null)
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _load(data.next!.bookNr, data.next!.chapter),
                icon: const Icon(Icons.chevron_right),
                label: Text(tr('Наступний')),
              ),
            ),
        ]),
      );
}

class _VerseView extends StatelessWidget {
  const _VerseView({
    super.key,
    required this.verse,
    required this.parallel,
    required this.font,
    required this.audioVerse,
    required this.selected,
    required this.onTap,
  });

  final BibleVerse verse;
  final BibleVerse? parallel;
  final double font;
  final ValueNotifier<int?> audioVerse;
  final ValueNotifier<int?> selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedBuilder(
      animation: Listenable.merge([audioVerse, selected]),
      builder: (context, _) {
        final sounding = audioVerse.value == verse.verse;
        final picked = selected.value == verse.verse;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: sounding
                  ? p.accent.withValues(alpha: 0.22)
                  : picked
                      ? p.primary.withValues(alpha: 0.10)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: '${verse.verse} ',
                    style: TextStyle(fontSize: font * 0.62, color: p.accent, fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: verse.text),
                ]),
                style: TextStyle(fontSize: font, height: 1.6, color: p.foreground),
              ),
              if (parallel != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 4),
                  child: Text(parallel!.text, style: TextStyle(fontSize: font - 3, height: 1.5, color: p.mutedForeground)),
                ),
            ]),
          ),
        );
      },
    );
  }
}

class _VerseSheet extends StatelessWidget {
  const _VerseSheet({
    required this.chapter,
    required this.verse,
    required this.parallel,
    required this.parallelTitle,
    required this.translationTitle,
    required this.commentaries,
    required this.canListen,
    required this.onListen,
    required this.books,
    required this.dictionaryEndpoint,
  });

  final BibleChapter chapter;
  final BibleVerse verse;
  final BibleVerse? parallel;
  final String? parallelTitle;
  final String translationTitle;
  final Future<List<Commentary>> commentaries;
  final bool canListen;
  final VoidCallback onListen;
  final List<BibleBook> books;
  final String dictionaryEndpoint;

  String get reference => '${chapter.bookName} ${chapter.chapter}:${verse.verse}';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final words = <String>{};
    for (final w in verse.text.split(RegExp(r"[^\p{L}ʼ'’-]+", unicode: true))) {
      final clean = w.replaceAll(RegExp(r"^[ʼ'’-]+|[ʼ'’-]+$"), '');
      if (clean.length >= 4) words.add(clean);
    }
    final shareText = '«${verse.text}» ($reference, $translationTitle)${chapter.url != null ? '\n${chapter.url}#v${verse.verse}' : ''}';

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(controller: controller, padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
        Text(reference, style: heading(context, size: 26)),
        const SizedBox(height: 8),
        SelectableText(verse.text, style: const TextStyle(fontSize: 17, height: 1.55)),
        if (parallel != null) ...[
          const SizedBox(height: 8),
          Text('${parallelTitle ?? ''}: ${parallel!.text}', style: TextStyle(color: p.mutedForeground, height: 1.5)),
        ],
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ActionChip(
            avatar: const Icon(Icons.copy, size: 18),
            label: Text(tr('Копіювати')),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: '«${verse.text}» ($reference)'));
              if (context.mounted) Navigator.pop(context);
            },
          ),
          ActionChip(
            avatar: const Icon(Icons.ios_share, size: 18),
            label: Text(tr('Поділитися')),
            onPressed: () => SharePlus.instance.share(ShareParams(text: shareText)),
          ),
          if (canListen)
            ActionChip(
              avatar: const Icon(Icons.headphones, size: 18),
              label: Text(tr('Слухати звідси')),
              onPressed: () {
                onListen();
                Navigator.pop(context);
              },
            ),
        ]),
        const SizedBox(height: 22),
        Text(tr('Коментарі'), style: heading(context, size: 22)),
        FutureBuilder<List<Commentary>>(
          future: commentaries,
          builder: (context, snap) {
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(tr('Не вдалося завантажити коментарі'), style: TextStyle(color: p.mutedForeground)),
              );
            }
            if (!snap.hasData) {
              return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
            }
            final v = verse.verse;
            final list = snap.data!.where((c) {
              if (c.verseFrom == 0) return false;
              final to = c.verseTo < c.verseFrom ? c.verseFrom : c.verseTo;
              return c.verseFrom <= v && v <= to;
            }).toList();
            final intro = snap.data!.where((c) => c.verseFrom == 0 && c.text.replaceAll(RegExp(r'<[^>]+>'), '').trim().length > 20).toList();
            if (list.isEmpty && intro.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(tr('До цього вірша коментарів немає'), style: TextStyle(color: p.mutedForeground)),
              );
            }
            Widget tile(Commentary c, String label) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(c.title),
                  subtitle: Text(
                    [label, if (c.author.isNotEmpty) c.author].join(' · '),
                    style: TextStyle(color: p.mutedForeground, fontSize: 12.5),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final place = await Navigator.of(context).push<BiblePlace>(MaterialPageRoute(
                      builder: (_) => CommentaryScreen(commentary: c, reference: label, books: books),
                    ));
                    if (place != null && context.mounted) Navigator.pop(context, place);
                  },
                );
            return Column(children: [
              for (final c in list)
                tile(c, c.verseTo > c.verseFrom ? '${chapter.bookName} ${chapter.chapter}:${c.verseFrom}–${c.verseTo}' : reference),
              for (final c in intro) tile(c, tr('{a} {b} — вступ', {'a': chapter.bookName, 'b': chapter.chapter})),
            ]);
          },
        ),
        if (words.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(tr('Словник'), style: heading(context, size: 22)),
          const SizedBox(height: 4),
          Text(tr('Натисніть слово — покажемо статті біблійних словників'), style: TextStyle(fontSize: 12.5, color: p.mutedForeground)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final w in words)
              ActionChip(
                label: Text(w),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => DictionaryScreen(word: w, endpoint: dictionaryEndpoint),
                )),
              ),
          ]),
        ],
      ]),
    );
  }
}
