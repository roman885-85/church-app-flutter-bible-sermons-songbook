import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/top_actions.dart';
import 'sheet_screen.dart';
import '../i18n.dart';

/// Ноти — те саме, що розділ «Ноти» на сайті: гімни з відкритих джерел,
/// сторінками, з пошуком і вибором збірки. Самі ноти й файли беруться з сайту.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final _api = Api();
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  String _query = '';
  String _collection = '';
  List<MapEntry<String, int>> _collections = const [];
  final List<SheetMusic> _items = [];
  int _page = 1;
  int _pages = 1;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _loadMore();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.sheetMusic(q: _query, collection: _collection);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(data.items);
        _page = data.page;
        _pages = data.pages;
        _total = data.total;
        if (data.collections.isNotEmpty) _collections = data.collections;
        _loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = tr('Не вдалося завантажити ноти. Перевірте інтернет.');
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loading || _page >= _pages) return;
    setState(() => _loadingMore = true);
    try {
      final data = await _api.sheetMusic(q: _query, collection: _collection, page: _page + 1);
      if (!mounted) return;
      setState(() {
        _items.addAll(data.items);
        _page = data.page;
        _pages = data.pages;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _query = value.trim();
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Ноти')),
        actions: topActions(context),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: _onSearch,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: tr('Назва гімну або мелодії'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _search.clear();
                        _query = '';
                        _load();
                      },
                    ),
            ),
          ),
        ),
        if (_collections.length > 1)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _chip(tr('Усі ноти'), _total > 0 && _collection.isEmpty ? _total : null, _collection.isEmpty, () {
                  _collection = '';
                  _load();
                }),
                for (final c in _collections)
                  _chip(c.key, c.value, _collection == c.key, () {
                    _collection = c.key;
                    _load();
                  }),
              ],
            ),
          ),
        Expanded(
          child: _loading
              ? LoadingView(label: tr('Завантажую ноти…'))
              : _error != null
                  ? ErrorView(message: _error!, onRetry: _load)
                  : _items.isEmpty
                      ? Center(child: Text(tr('Нічого не знайдено'), style: TextStyle(color: p.mutedForeground)))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: GridView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.62,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            itemCount: _items.length + (_page < _pages ? 1 : 0),
                            itemBuilder: (context, i) {
                              if (i >= _items.length) {
                                return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
                              }
                              return _card(_items[i]);
                            },
                          ),
                        ),
        ),
      ]),
    );
  }

  Widget _chip(String label, int? count, bool active, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          selected: active,
          onSelected: (_) => onTap(),
          label: Text(count == null ? label : '$label  $count'),
        ),
      );

  Widget _card(SheetMusic sheet) {
    final p = context.palette;
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SheetScreen(sheet: sheet))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Container(
              color: Colors.white,
              width: double.infinity,
              child: sheet.cover == null
                  ? Icon(Icons.queue_music, color: p.mutedForeground)
                  : NetImage(sheet.cover, fit: BoxFit.cover, radius: 0, icon: Icons.queue_music),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(sheet.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500, height: 1.2)),
              if (sheet.subtitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(sheet.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.mutedForeground)),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Відкрити ноти на сайті — запасний шлях, якщо файл не показується в застосунку.
Future<void> openSheetOnSite(BuildContext context, SheetMusic sheet) =>
    openExternal(context, '${Api.siteUrl}/notes/${Uri.encodeComponent(sheet.slug)}');
