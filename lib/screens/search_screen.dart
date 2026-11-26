import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../api/songbook_models.dart';
import '../services/app_state.dart';
import '../services/songbook.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import 'news_screen.dart';
import 'sermon_screen.dart';
import 'song_screen.dart';
import 'videos_screen.dart';
import '../i18n.dart';

/// Пошук по всьому застосунку: пісні (номер або слова), проповіді, відео,
/// новини й статті.
///
/// Пісні, проповіді й відео вже лежать у телефоні, тож шукаються миттєво й без
/// мережі. Новин на телефоні немає — їх шукає сайт (/api/app/v1/search). Біблію
/// шукає її власний пошук — там інша мова запитів (посилання, вірші).
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.initialQuery});

  /// Одразу шукати це (ярлик «Пошук» із текстом, перевірка через adb).
  final String? initialQuery;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _field = TextEditingController();
  String _query = '';
  Timer? _debounce;

  List<NewsItem> _news = const [];
  bool _newsLoading = false;
  bool _newsOffline = false;
  int _newsRequest = 0;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialQuery?.trim() ?? '';
    if (initial.isNotEmpty) {
      _field.text = initial;
      _query = initial;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchNews(initial);
      });
    }
    // Пісенник у пошуку — навіть якщо його ще не відкривали: збірник за
    // замовчуванням підтягується тихо.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final songbook = context.read<SongbookService>();
      if (songbook.info == null) await songbook.loadInfo();
      final code = songbook.defaultBookCode;
      if (code != null && songbook.songsOf(code) == null) unawaited(songbook.openBook(code));
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      final q = value.trim();
      setState(() => _query = q);
      _searchNews(q);
    });
  }

  /// Новини шукає сайт. Відповідь на старий запит, що прийшла пізніше за
  /// новий, відкидається.
  Future<void> _searchNews(String q) async {
    final request = ++_newsRequest;
    if (q.length < 3 || RegExp(r'^\d+$').hasMatch(q)) {
      setState(() {
        _news = const [];
        _newsLoading = false;
        _newsOffline = false;
      });
      return;
    }
    final api = context.read<Api>();
    setState(() => _newsLoading = true);
    try {
      final items = await api.searchNews(q);
      if (!mounted || request != _newsRequest) return;
      setState(() {
        _news = items;
        _newsLoading = false;
        _newsOffline = false;
      });
    } catch (_) {
      if (!mounted || request != _newsRequest) return;
      setState(() {
        _news = const [];
        _newsLoading = false;
        _newsOffline = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = context.watch<AppState>();
    final songbook = context.watch<SongbookService>();
    final q = _query;

    final songHits = <(SongbookBook, List<Song>, Song)>[];
    final sermonHits = <Sermon>[];
    final videoHits = <VideoItem>[];
    final collectionHits = <VideoCollection>[];

    if (q.isNotEmpty) {
      for (final book in songbook.info?.books ?? const <SongbookBook>[]) {
        final all = songbook.songsOf(book.code);
        if (all == null) continue;
        for (final song in songbook.search(book.code, q).take(8)) {
          songHits.add((book, all, song));
        }
      }
      // Та сама згортка, що на сайті й у пісеннику: «молодь» знаходить «молоді».
      final words = foldSongText(q).split(' ').where((w) => w.isNotEmpty).toList();
      bool matches(String hay) {
        final h = foldSongText(hay);
        return words.every(h.contains);
      }

      if (words.isNotEmpty) {
        for (final s in state.catalogue?.sermons ?? const <Sermon>[]) {
          if (matches('${s.title} ${s.preacher} ${s.books.join(' ')} ${s.topics.join(' ')}')) sermonHits.add(s);
          if (sermonHits.length >= 30) break;
        }
        for (final v in state.videos?.latest ?? const <VideoItem>[]) {
          if (matches(v.title)) videoHits.add(v);
        }
        for (final section in state.videos?.sections ?? const <VideoSection>[]) {
          for (final c in section.items) {
            if (matches('${c.title} ${c.description}')) collectionHits.add(c);
          }
        }
      }
    }

    final nothing = q.isNotEmpty &&
        songHits.isEmpty &&
        sermonHits.isEmpty &&
        videoHits.isEmpty &&
        collectionHits.isEmpty &&
        _news.isEmpty &&
        !_newsLoading;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _field,
          autofocus: true,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: tr('Пісня, проповідь, відео, новина…'),
            border: InputBorder.none,
            filled: false,
            suffixIcon: _field.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: tr('Очистити'),
                    onPressed: () {
                      _field.clear();
                      setState(() => _query = '');
                      _searchNews('');
                    },
                  ),
          ),
        ),
      ),
      body: q.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.search, size: 44, color: p.mutedForeground),
                  const SizedBox(height: 12),
                  Text(
                    tr('Номер або слова пісні, назва чи проповідник, назва відео, новини й статті.\nПісні, проповіді й відео шукаються й без інтернету.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.mutedForeground, height: 1.4),
                  ),
                ]),
              ),
            )
          : nothing
              ? EmptyView(
                  icon: Icons.search_off,
                  text: _newsOffline
                      ? tr('Нічого не знайдено. Новини й статті шукаються лише з інтернетом.')
                      : tr('Нічого не знайдено. Спробуйте інші слова.'),
                )
              : ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                  if (songHits.isNotEmpty) ...[
                    _Header(tr('Пісні')),
                    for (final (book, all, song) in songHits)
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: p.secondary,
                          child: Text('${song.number}',
                              style: TextStyle(fontSize: song.number > 999 ? 11 : 13, fontWeight: FontWeight.w700, color: p.primary)),
                        ),
                        title: Text(song.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(book.shortTitle.isNotEmpty ? book.shortTitle : book.title),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => SongScreen(bookCode: book.code, songs: all, initialIndex: all.indexOf(song)),
                        )),
                      ),
                  ],
                  if (sermonHits.isNotEmpty) ...[
                    _Header(tr('Проповіді')),
                    for (final s in sermonHits)
                      ListTile(
                        leading: const Icon(Icons.headphones_outlined),
                        title: Text(s.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text([s.preacher, humanDate(s.date)].where((x) => x.isNotEmpty).join(' · '),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SermonScreen(sermon: s, list: sermonHits))),
                      ),
                  ],
                  if (videoHits.isNotEmpty || collectionHits.isNotEmpty) ...[
                    _Header(tr('Відео')),
                    for (final c in collectionHits)
                      ListTile(
                        leading: const Icon(Icons.video_library_outlined),
                        title: Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(tr('Добірка відео')),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CollectionScreen(collection: c))),
                      ),
                    for (final v in videoHits)
                      ListTile(
                        leading: const Icon(Icons.smart_display_outlined),
                        title: Text(v.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: v.published.isEmpty ? null : Text(humanDate(v.published)),
                        onTap: () => openVideo(context, v),
                      ),
                  ],
                  if (_news.isNotEmpty) ...[
                    _Header(tr('Новини й статті')),
                    for (final n in _news)
                      ListTile(
                        leading: n.image == null
                            ? const Icon(Icons.article_outlined)
                            : NetImage(n.image, width: 56, height: 40, radius: 6),
                        title: Text(n.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text([n.category, n.date].where((x) => x.isNotEmpty).join(' · '),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ArticleScreen(item: n))),
                      ),
                  ],
                  if (_newsLoading)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
                    ),
                  if (_newsOffline)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Text(tr('Новини й статті шукаються, коли є інтернет.'),
                          style: TextStyle(color: p.mutedForeground, fontSize: 13)),
                    ),
                ]),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
        child: Text(text.toUpperCase(),
            style: TextStyle(fontSize: 12, letterSpacing: 1.8, fontWeight: FontWeight.w600, color: context.palette.accent)),
      );
}
