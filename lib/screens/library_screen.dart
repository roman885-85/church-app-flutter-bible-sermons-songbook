import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../services/library.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/sermon_tile.dart';
import '../i18n.dart';

/// Моя фонотека: обране, збережене на телефоні, нещодавно слухане.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    return DefaultTabController(
      length: 3,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('Моя фонотека')),
          bottom: TabBar(
            labelColor: context.palette.primary,
            indicatorColor: context.palette.primary,
            tabs: [Tab(text: tr('Обране')), Tab(text: tr('Збережене')), Tab(text: tr('Історія'))],
          ),
        ),
        body: TabBarView(children: [
          favorites(library),
          downloads(library),
          history(library),
        ]),
      ),
    );
  }

  /// Вкладки фонотеки окремо — їх показують і вгорі розділу «Проповіді».
  static Widget favorites(LibraryService library) =>
      _list(library.favorites, Icons.favorite_border, tr('Тут будуть проповіді, які ви позначите сердечком.'));
  static Widget downloads(LibraryService library) => _Downloads(library: library);
  static Widget history(LibraryService library) =>
      _list(library.history, Icons.history, tr('Тут зʼявляться проповіді, які ви слухали.'));

  static Widget _list(List<Sermon> list, IconData icon, String empty) {
    if (list.isEmpty) return EmptyView(icon: icon, text: empty);
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, i) => SermonTile(sermon: list[i], list: list, index: i),
    );
  }
}

class _Downloads extends StatelessWidget {
  const _Downloads({required this.library});
  final LibraryService library;

  @override
  Widget build(BuildContext context) {
    final list = library.downloads;
    if (list.isEmpty) {
      return EmptyView(
        icon: Icons.download_outlined,
        text: tr('Збережіть проповідь кнопкою завантаження — і слухайте її без інтернету.'),
      );
    }
    return ListView(children: [
      FutureBuilder<int>(
        future: library.downloadsSize(),
        builder: (context, snap) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Text(
            snap.hasData ? tr('Займає на телефоні {a} МБ', {'a': (snap.data! / 1048576).toStringAsFixed(0)}) : ' ',
            style: TextStyle(color: context.palette.mutedForeground, fontSize: 13),
          ),
        ),
      ),
      for (var i = 0; i < list.length; i++)
        Dismissible(
          key: ValueKey('dl-${list[i].id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            color: const Color(0xFFB3261E),
            child: const Icon(Icons.delete_outline, color: Colors.white),
          ),
          onDismissed: (_) => library.deleteDownload(list[i].id),
          child: SermonTile(sermon: list[i], list: list, index: i),
        ),
    ]);
  }
}
