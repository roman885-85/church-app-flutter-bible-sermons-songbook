import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:provider/provider.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../i18n.dart';

/// Куди перейти в Біблії: книга, глава і (не обовʼязково) вірш.
class BiblePlace {
  const BiblePlace(this.bookNr, this.chapter, [this.verse]);
  final int bookNr;
  final int chapter;
  final int? verse;
}

/// «/bible/jhn/3#v16» з коментарів і словників → місце в читанці.
BiblePlace? placeFromLink(String url, List<BibleBook> books) {
  final m = RegExp(r'/bible/([\w-]+)/(\d+)(?:[^#]*#v(\d+))?').firstMatch(url);
  if (m == null) return null;
  final slug = m.group(1);
  final book = books.where((b) => b.slug == slug).firstOrNull;
  if (book == null) return null;
  return BiblePlace(book.bookNr, int.parse(m.group(2)!), m.group(3) == null ? null : int.parse(m.group(3)!));
}

/// Вибір книги й глави.
class BookPickerScreen extends StatefulWidget {
  const BookPickerScreen({super.key, required this.books, required this.currentBook});
  final List<BibleBook> books;
  final int currentBook;

  @override
  State<BookPickerScreen> createState() => _BookPickerScreenState();
}

class _BookPickerScreenState extends State<BookPickerScreen> {
  int? _open;

  @override
  void initState() {
    super.initState();
    _open = widget.currentBook;
  }

  @override
  Widget build(BuildContext context) {
    final groups = <(String, List<BibleBook>)>[
      (tr('Старий Заповіт'), widget.books.where((b) => b.testament == 'ot').toList()),
      (tr('Новий Заповіт'), widget.books.where((b) => b.isNewTestament).toList()),
      (tr('Второканонічні книги'), widget.books.where((b) => b.testament != 'ot' && !b.isNewTestament).toList()),
    ].where((g) => g.$2.isNotEmpty).toList();
    final initial = groups.indexWhere((g) => g.$2.any((b) => b.bookNr == widget.currentBook));

    return DefaultTabController(
      length: groups.length,
      initialIndex: initial < 0 ? 0 : initial,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('Книги Біблії')),
          bottom: groups.length > 1
              ? TabBar(
                  isScrollable: groups.length > 2,
                  labelColor: context.palette.primary,
                  indicatorColor: context.palette.primary,
                  tabs: [for (final g in groups) Tab(text: g.$1)],
                )
              : null,
        ),
        body: TabBarView(children: [
          for (final g in groups)
            ListView.builder(
              itemCount: g.$2.length,
              itemBuilder: (context, i) => _bookTile(context, g.$2[i]),
            ),
        ]),
      ),
    );
  }

  Widget _bookTile(BuildContext context, BibleBook book) {
    final p = context.palette;
    final open = _open == book.bookNr;
    return Column(children: [
      ListTile(
        title: Text(book.name,
            style: TextStyle(
              fontWeight: book.bookNr == widget.currentBook ? FontWeight.w600 : FontWeight.w400,
              color: book.bookNr == widget.currentBook ? p.primary : null,
            )),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${book.chapters.length}', style: TextStyle(color: p.mutedForeground)),
          Icon(open ? Icons.expand_less : Icons.expand_more, color: p.mutedForeground),
        ]),
        onTap: () {
          if (book.chapters.length == 1) {
            Navigator.pop(context, BiblePlace(book.bookNr, book.chapters.first));
          } else {
            setState(() => _open = open ? null : book.bookNr);
          }
        },
      ),
      if (open)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in book.chapters)
              SizedBox(
                width: 48,
                height: 44,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.pop(context, BiblePlace(book.bookNr, c)),
                  child: Text('$c'),
                ),
              ),
          ]),
        ),
    ]);
  }
}

/// Пошук слів у вибраному перекладі.
class BibleSearchScreen extends StatefulWidget {
  const BibleSearchScreen({super.key, required this.translation, required this.translationTitle});
  final String translation;
  final String translationTitle;

  @override
  State<BibleSearchScreen> createState() => _BibleSearchScreenState();
}

class _BibleSearchScreenState extends State<BibleSearchScreen> {
  final _field = TextEditingController();
  Future<List<BibleHit>>? _future;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _run() {
    final q = _field.text.trim();
    if (q.length < 2) return;
    setState(() => _future = context.read<Api>().searchBible(q, widget.translation));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Пошук у Біблії'))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _field,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _run(),
            decoration: InputDecoration(
              hintText: tr('Слово або фраза'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _run),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(widget.translationTitle, style: TextStyle(fontSize: 12.5, color: p.mutedForeground)),
          ),
        ),
        Expanded(
          child: _future == null
              ? EmptyView(icon: Icons.manage_search, text: tr('Введіть слово — знайдемо вірші, де воно є'))
              : FutureBuilder<List<BibleHit>>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.hasError) return ErrorView(message: '${snap.error}', onRetry: _run);
                    if (!snap.hasData) return const LoadingView();
                    final hits = snap.data!;
                    if (hits.isEmpty) return EmptyView(icon: Icons.search_off, text: tr('Нічого не знайдено'));
                    return ListView.separated(
                      itemCount: hits.length,
                      separatorBuilder: (_, _) => const Divider(indent: 20, endIndent: 20),
                      itemBuilder: (context, i) {
                        final h = hits[i];
                        return ListTile(
                          title: Text('${h.bookName} ${h.chapter}:${h.verse}', style: TextStyle(color: p.primary, fontWeight: FontWeight.w600)),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(h.text, style: TextStyle(color: p.foreground, height: 1.4)),
                          ),
                          onTap: () => Navigator.pop(context, BiblePlace(h.bookNr, h.chapter, h.verse)),
                        );
                      },
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

/// Один коментар повністю.
class CommentaryScreen extends StatelessWidget {
  const CommentaryScreen({super.key, required this.commentary, required this.reference, required this.books});
  final Commentary commentary;
  final String reference;
  final List<BibleBook> books;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text(reference, style: const TextStyle(fontSize: 22))),
      body: HtmlWidget(
        '<h3>${_esc(commentary.title)}</h3>'
        '${commentary.author.isNotEmpty ? '<p><i>${_esc(commentary.author)}</i></p>' : ''}'
        '${commentary.text}',
        baseUrl: Uri.parse(Api.siteUrl),
        renderMode: RenderMode.listView,
        textStyle: TextStyle(fontSize: 16, height: 1.55, color: p.foreground),
        customStylesBuilder: (element) => element.localName == 'body' ? {'padding': '16px 20px 40px'} : null,
        onTapUrl: (url) {
          final place = placeFromLink(url, books);
          if (place != null) {
            Navigator.of(context).pop(place);
            return true;
          }
          openExternal(context, url);
          return true;
        },
      ),
    );
  }
}

/// Словникова стаття.
class DictionaryScreen extends StatefulWidget {
  const DictionaryScreen({super.key, required this.word, required this.endpoint});
  final String word;
  final String endpoint;

  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  late Future<List<DictionaryHit>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<Api>().dictionary(widget.endpoint, widget.word);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text(widget.word)),
      body: FutureBuilder<List<DictionaryHit>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(message: '${snap.error}');
          if (!snap.hasData) return const LoadingView();
          final hits = snap.data!;
          if (hits.isEmpty) {
            return EmptyView(icon: Icons.menu_book_outlined, text: tr('У словниках немає статті «{a}»', {'a': widget.word}));
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: hits.length,
            itemBuilder: (context, i) {
              final h = hits[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(h.dictionary.toUpperCase(), style: TextStyle(fontSize: 11, letterSpacing: 1.4, color: p.accent)),
                      const SizedBox(height: 4),
                      Text(h.topic, style: heading(context, size: 22)),
                      const SizedBox(height: 8),
                      HtmlWidget(
                        h.definition,
                        baseUrl: Uri.parse(Api.siteUrl),
                        textStyle: TextStyle(fontSize: 15, height: 1.5, color: p.foreground),
                        onTapUrl: (url) {
                          openExternal(context, url.startsWith('/') ? '${Api.siteUrl}$url' : url);
                          return true;
                        },
                      ),
                    ]),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
