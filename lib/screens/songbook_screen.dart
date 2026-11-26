import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/songbook_models.dart';
import '../services/library.dart';
import '../services/songbook.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/picker_button.dart';
import '../widgets/top_actions.dart';
import 'song_screen.dart';
import '../i18n.dart';

/// Пісенник: збірник, пошук за номером або словами, список пісень.
///
/// Збірник лежить на телефоні цілком — пошук і відкриття пісні працюють і без
/// мережі. Завантажується один раз, оновлюється тихо, коли на сайті щось змінилось.
class SongbookScreen extends StatefulWidget {
  const SongbookScreen({super.key});

  @override
  State<SongbookScreen> createState() => _SongbookScreenState();
}

class _SongbookScreenState extends State<SongbookScreen> {
  final _search = TextEditingController();
  String _query = '';
  String? _book;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final songbook = context.read<SongbookService>();
    final library = context.read<LibraryService>();
    if (songbook.info == null) await songbook.loadInfo();
    if (!mounted) return;
    final books = songbook.info?.books ?? const <SongbookBook>[];
    final saved = library.songBook;
    final code = books.any((b) => b.code == saved) ? saved : songbook.defaultBookCode;
    if (code == null) return;
    setState(() => _book = code);
    await songbook.openBook(code);
  }

  Future<void> _selectBook(String code) async {
    setState(() {
      _book = code;
      _search.clear();
      _query = '';
    });
    unawaited(context.read<LibraryService>().setSongBook(code));
    await context.read<SongbookService>().openBook(code);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQuery(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      if (mounted) setState(() => _query = value);
    });
  }

  void _open(List<Song> list, int index) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SongScreen(bookCode: _book!, songs: list, initialIndex: index),
    ));
  }

  /// Число й «Enter» — одразу до пісні з цим номером.
  void _submit(String value) {
    final songs = context.read<SongbookService>().songsOf(_book ?? '') ?? const <Song>[];
    final number = int.tryParse(value.trim());
    if (number == null) return;
    final index = songs.indexWhere((s) => s.number == number);
    if (index >= 0) _open(songs, index);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final songbook = context.watch<SongbookService>();
    final info = songbook.info;
    final books = info?.books ?? const <SongbookBook>[];
    final book = books.where((b) => b.code == _book).firstOrNull;
    final songs = _book == null ? null : songbook.songsOf(_book!);
    final results = songs == null ? const <Song>[] : songbook.search(_book!, _query);
    final maxNumber = songs == null || songs.isEmpty ? 0 : songs.last.number;

    Widget body;
    if (info == null && songbook.infoError != null) {
      body = ErrorView(message: songbook.infoError!, onRetry: _start);
    } else if (info != null && books.isEmpty) {
      body = EmptyView(icon: Icons.library_music_outlined, text: tr('Пісенник ще не завантажено на сайт.'));
    } else if (songs == null) {
      if (songbook.bookError != null && songbook.loadingBook == null) {
        body = ErrorView(message: songbook.bookError!, onRetry: _book == null ? _start : () => songbook.retry(_book!));
      } else {
        final progress = songbook.progress;
        body = Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 220, child: LinearProgressIndicator(value: progress)),
              const SizedBox(height: 16),
              Text(
                progress != null
                    ? tr('Завантажую пісенник на телефон — {a}%', {'a': (progress * 100).round()})
                    : songbook.downloadedBytes > 0
                        ? tr('Завантажую пісенник на телефон — {a} МБ', {'a': (songbook.downloadedBytes / 1048576).toStringAsFixed(1)})
                        : tr('Відкриваю пісенник…'),
                textAlign: TextAlign.center,
                style: TextStyle(color: p.mutedForeground),
              ),
              const SizedBox(height: 6),
              Text(tr('Лише вперше: далі пісні відкриваються й без інтернету.'),
                  textAlign: TextAlign.center, style: TextStyle(color: p.mutedForeground, fontSize: 12)),
            ]),
          ),
        );
      }
    } else {
      body = results.isEmpty
          ? EmptyView(icon: Icons.search_off, text: tr('Нічого не знайдено. Спробуйте інші слова або номер.'))
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: results.length,
              separatorBuilder: (_, _) => Divider(height: 1, indent: 72, color: p.border),
              itemBuilder: (context, i) {
                final song = results[i];
                final snippet = _query.isNotEmpty && int.tryParse(_query.trim()) == null && !song.titleFold.contains(foldSongText(_query).split(' ').first)
                    ? _snippet(song, _query)
                    : null;
                return ListTile(
                  onTap: () => _open(results, i),
                  leading: SizedBox(
                    width: 44,
                    child: Text('${song.number}',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontWeight: FontWeight.w700, color: p.primary, fontFeatures: const [FontFeature.tabularFigures()])),
                  ),
                  title: Text(song.title, style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: snippet == null ? null : Text('…$snippet', maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: _KindIcons(song: song),
                  minLeadingWidth: 44,
                );
              },
            );
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr('Пісенник')), actions: topActions(context)),
      body: Column(children: [
        // Збірник — такою самою кнопкою вибору, як книга й переклад у Біблії.
        if (books.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: PickerButton(
                caption: tr('Збірник'),
                value: book?.title ?? '…',
                icon: Icons.library_music_outlined,
                onPressed: () => _chooseBook(books),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: _onQuery,
            onSubmitted: _submit,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: maxNumber > 0 ? tr('Номер (1–{a}) або слова пісні', {'a': maxNumber}) : tr('Номер або слова пісні'),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: tr('Очистити'),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              isDense: true,
            ),
          ),
        ),
        if (book != null && songs != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Row(children: [
              Expanded(child: Text(book.title, style: heading(context, size: 20), maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text(_query.isEmpty ? tr('{a} пісень', {'a': songs.length}) : tr('Знайдено: {a}', {'a': results.length}),
                  style: TextStyle(color: p.mutedForeground, fontSize: 13)),
            ]),
          ),
        Expanded(child: body),
      ]),
    );
  }

  Future<void> _chooseBook(List<SongbookBook> books) async {
    final p = context.palette;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(tr('Збірник'), style: heading(context, size: 24)),
          ),
          for (final b in books)
            ListTile(
              leading: Icon(Icons.library_music_outlined, color: b.code == _book ? p.primary : null),
              title: Text(b.title, style: TextStyle(fontWeight: b.code == _book ? FontWeight.w600 : FontWeight.w400)),
              subtitle: Text(tr('{a} пісень', {'a': b.songs})),
              trailing: b.code == _book ? Icon(Icons.check, color: p.primary) : null,
              onTap: () => Navigator.pop(context, b.code),
            ),
        ]),
      ),
    );
    if (chosen != null && chosen != _book) await _selectBook(chosen);
  }

  String? _snippet(Song song, String query) {
    final words = foldSongText(query).split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return null;
    String? best;
    var bestHits = 0;
    for (final part in song.parts) {
      for (final line in part.text.split('\n')) {
        final folded = foldSongText(line);
        final hits = words.where(folded.contains).length;
        if (hits > bestHits) {
          bestHits = hits;
          best = line.trim();
        }
      }
    }
    return best;
  }
}

class _KindIcons extends StatelessWidget {
  const _KindIcons({required this.song});
  final Song song;

  @override
  Widget build(BuildContext context) {
    final color = context.palette.mutedForeground;
    final icons = <IconData>[
      if (song.has('midi')) Icons.piano,
      if (song.has('minus')) Icons.music_note,
      if (song.has('song')) Icons.mic_none,
      if (song.has('notes')) Icons.queue_music,
    ];
    if (icons.isEmpty) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (final icon in icons) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(icon, size: 16, color: color)),
    ]);
  }
}
