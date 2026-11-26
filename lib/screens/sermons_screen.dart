import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../services/app_state.dart';
import '../theme.dart';
import '../util/format.dart';
import '../services/library.dart';
import '../services/live_alerts.dart';
import '../widgets/common.dart';
import '../widgets/live_alerts_prompt.dart';
import '../widgets/picker_button.dart';
import '../widgets/sermon_tile.dart';
import '../widgets/top_actions.dart';
import 'library_screen.dart';
import '../i18n.dart';

/// Фонотека: пошук, проповідник, книга Біблії, тема — усе на телефоні, без мережі теж.
class SermonsScreen extends StatefulWidget {
  const SermonsScreen({super.key});

  @override
  State<SermonsScreen> createState() => _SermonsScreenState();
}

enum _Kind { all, sermons, readings }

class _SermonsScreenState extends State<SermonsScreen> {
  final _search = TextEditingController();
  String _query = '';
  String? _preacher;
  String? _book;
  String? _topic;
  _Kind _kind = _Kind.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Sermon> _filter(List<Sermon> all) {
    final q = fold(_query.trim());
    return all.where((s) {
      if (_kind == _Kind.sermons && s.isReading) return false;
      if (_kind == _Kind.readings && !s.isReading) return false;
      if (_preacher != null && s.preacher != _preacher) return false;
      if (_book != null && !s.books.contains(_book)) return false;
      if (_topic != null && !s.topics.contains(_topic)) return false;
      if (q.isNotEmpty) {
        final hay = fold('${s.title} ${s.preacher} ${s.books.join(' ')} ${s.topics.join(' ')}');
        for (final word in q.split(RegExp(r'\s+'))) {
          if (!hay.contains(word)) return false;
        }
      }
      return true;
    }).toList();
  }

  Future<String?> _pick(String title, List<Tally> options, String? current) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _PickerSheet(title: title, options: options, current: current),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = context.palette;
    final catalogue = state.catalogue;

    Widget body;
    if (catalogue == null) {
      body = state.sermonsError != null
          ? ErrorView(message: state.sermonsError!, onRetry: state.refresh)
          : LoadingView(label: tr('Завантажуємо проповіді…'));
    } else {
      final list = _filter(catalogue.sermons);
      body = RefreshIndicator(
        onRefresh: state.refresh,
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: tr('Пошук за назвою, проповідником, книгою'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            _search.clear();
                            _query = '';
                          }),
                        ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                _FilterChip(
                  caption: tr('Проповідник'),
                  icon: Icons.person_outline,
                  label: _preacher ?? tr('Усі'),
                  active: _preacher != null,
                  onTap: () async {
                    final v = await _pick(tr('Проповідник'), catalogue.preachers, _preacher);
                    if (v != null) setState(() => _preacher = v.isEmpty ? null : v);
                  },
                ),
                _FilterChip(
                  caption: tr('Книга Біблії'),
                  icon: Icons.menu_book_outlined,
                  label: _book != null ? tr(_book!) : tr('Усі'),
                  active: _book != null,
                  onTap: () async {
                    final v = await _pick(tr('Книга Біблії'), catalogue.books, _book);
                    if (v != null) setState(() => _book = v.isEmpty ? null : v);
                  },
                ),
                _FilterChip(
                  caption: tr('Тема'),
                  icon: Icons.label_outline,
                  label: _topic != null ? tr(_topic!) : tr('Усі'),
                  active: _topic != null,
                  onTap: () async {
                    final v = await _pick(tr('Тема'), catalogue.topics, _topic);
                    if (v != null) setState(() => _topic = v.isEmpty ? null : v);
                  },
                ),
                const SizedBox(width: 4),
                SegmentedButton<_Kind>(
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
                  segments: [
                    ButtonSegment(value: _Kind.all, label: Text(tr('Усі'))),
                    ButtonSegment(value: _Kind.sermons, label: Text(tr('Проповіді'))),
                    ButtonSegment(value: _Kind.readings, label: Text(tr('Читання'))),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (v) => setState(() => _kind = v.first),
                ),
              ]),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Row(children: [
                Text(tr('{a} записів', {'a': list.length}), style: TextStyle(color: p.mutedForeground, fontSize: 13)),
                const Spacer(),
                if (_preacher != null || _book != null || _topic != null || _query.isNotEmpty || _kind != _Kind.all)
                  TextButton(
                    onPressed: () => setState(() {
                      _preacher = _book = _topic = null;
                      _kind = _Kind.all;
                      _search.clear();
                      _query = '';
                    }),
                    child: Text(tr('Скинути фільтри')),
                  ),
              ]),
            ),
          ),
          if (list.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyView(icon: Icons.search_off, text: tr('Нічого не знайдено. Спробуйте інше слово або скиньте фільтри.')),
            )
          else
            SliverList.builder(
              itemCount: list.length,
              itemBuilder: (context, i) => SermonTile(sermon: list[i], list: list, index: i),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ]),
      );
    }

    // Вкладки вгорі, як у «Слові благодаті»: уся фонотека й «моє» — обране,
    // збережене на телефоні, історія — без переходу в окреме меню.
    final library = context.watch<LibraryService>();
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('Проповіді')),
          actions: topActions(context, before: const [AlertsBell(kind: AlertKind.sermons)]),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: p.primary,
            indicatorColor: p.primary,
            tabs: [Tab(text: tr('Усі')), Tab(text: tr('Обране')), Tab(text: tr('Збережене')), Tab(text: tr('Історія'))],
          ),
        ),
        body: TabBarView(children: [
          body,
          LibraryScreen.favorites(library),
          LibraryScreen.downloads(library),
          LibraryScreen.history(library),
        ]),
      ),
    );
  }
}

/// Фільтр фонотеки — тією самою кнопкою вибору, що й у Біблії та пісеннику.
class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.caption, required this.label, required this.active, required this.onTap, this.icon});
  final String caption;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: PickerButton(caption: caption, value: label, icon: icon, active: active, onPressed: onTap),
        ),
      );
}

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({required this.title, required this.options, required this.current});
  final String title;
  final List<Tally> options;
  final String? current;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final q = fold(_q);
    final items = widget.options.where((o) => q.isEmpty || fold(o.name).contains(q) || fold(tr(o.name)).contains(q)).toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(children: [
            Expanded(child: Text(widget.title, style: heading(context, size: 24))),
            if (widget.current != null) TextButton(onPressed: () => Navigator.pop(context, ''), child: Text(tr('Будь-який'))),
          ]),
        ),
        if (widget.options.length > 12)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: false,
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(hintText: tr('Знайти'), prefixIcon: Icon(Icons.search)),
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: controller,
            itemCount: items.length,
            itemBuilder: (context, i) {
              final o = items[i];
              final selected = o.name == widget.current;
              return ListTile(
                leading: o.photo != null ? NetImage(o.photo, width: 40, height: 40, radius: 20, icon: Icons.person_outline) : null,
                title: Text(tr(o.name), style: TextStyle(color: selected ? p.primary : null, fontWeight: selected ? FontWeight.w600 : null)),
                trailing: Text('${o.count}', style: TextStyle(color: p.mutedForeground)),
                onTap: () => Navigator.pop(context, o.name),
              );
            },
          ),
        ),
      ]),
    );
  }
}
