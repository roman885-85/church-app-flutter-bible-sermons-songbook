import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../services/library.dart';
import '../services/player.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/sermon_tile.dart';
import 'video_screen.dart';
import '../i18n.dart';

/// Сторінка проповіді — як на сайті: звук, опис, проповідник і схожі записи.
class SermonScreen extends StatefulWidget {
  const SermonScreen({super.key, required this.sermon, this.list});

  final Sermon sermon;
  final List<Sermon>? list;

  @override
  State<SermonScreen> createState() => _SermonScreenState();
}

class _SermonScreenState extends State<SermonScreen> {
  late Future<SermonDetail> _detail;

  @override
  void initState() {
    super.initState();
    _detail = context.read<Api>().sermon(widget.sermon.id);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = widget.sermon;
    final library = context.watch<LibraryService>();
    final player = context.watch<PlayerService>();
    final isCurrent = player.isCurrentSermon(s.id);
    final resume = library.positionOf(s.id);

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: tr('Обране'),
            onPressed: () => library.toggleFavorite(s),
            icon: Icon(library.isFavorite(s.id) ? Icons.favorite : Icons.favorite_border,
                color: library.isFavorite(s.id) ? p.primary : null),
          ),
          if (s.url != null)
            IconButton(
              tooltip: tr('Поділитися'),
              icon: const Icon(Icons.ios_share),
              onPressed: () => SharePlus.instance.share(ShareParams(text: '${s.title}\n${s.url}')),
            ),
        ],
      ),
      body: FutureBuilder<SermonDetail>(
        future: _detail,
        builder: (context, snap) {
          final detail = snap.data;
          return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (s.coverUrl != null) ...[
                  AspectRatio(aspectRatio: 16 / 9, child: NetImage(s.coverUrl, radius: 18)),
                  const SizedBox(height: 18),
                ],
                Text(s.title, style: heading(context, size: 30)),
                const SizedBox(height: 8),
                Text(
                  [
                    if (s.preacher.isNotEmpty) s.preacher,
                    if (s.date.isNotEmpty) humanDate(s.date),
                    if (s.duration > 0) humanDuration(s.duration),
                  ].join(' · '),
                  style: TextStyle(color: p.mutedForeground),
                ),
                if (s.books.isNotEmpty || s.topics.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final b in s.books) Chip(avatar: const Icon(Icons.menu_book_outlined, size: 16), label: Text(b)),
                    for (final t in s.topics) Chip(label: Text(t)),
                  ]),
                ],
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                    child: StreamBuilder<PlayerState>(
                      stream: player.player.playerStateStream,
                      builder: (context, state) {
                        final playing = isCurrent && (state.data?.playing ?? false);
                        return FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                          onPressed: () {
                            if (isCurrent) {
                              player.toggle();
                            } else {
                              final list = widget.list ?? [s];
                              final index = list.indexWhere((e) => e.id == s.id);
                              player.playSermons(index < 0 ? [s] : list, index < 0 ? 0 : index);
                            }
                          },
                          icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                          label: Text(playing
                              ? tr('Пауза')
                              : resume > Duration.zero && !isCurrent
                                  ? tr('Продовжити з {a}', {'a': clock(resume)})
                                  : tr('Слухати')),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  _DownloadButton(sermon: s),
                ]),
                if (s.videoId != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                    onPressed: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
                      builder: (_) => VideoScreen(videoId: s.videoId!, title: s.title),
                    )),
                    icon: const Icon(Icons.smart_display_outlined),
                    label: Text(tr('Дивитися відео')),
                  ),
                ],
                if (detail != null && detail.description.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  SelectableText(detail.description, style: const TextStyle(fontSize: 15.5, height: 1.55)),
                ],
                if (detail != null && (detail.preacherPhoto != null || detail.preacherBio.isNotEmpty)) ...[
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (detail.preacherPhoto != null) ...[
                          NetImage(detail.preacherPhoto, width: 64, height: 64, radius: 32, icon: Icons.person_outline),
                          const SizedBox(width: 14),
                        ],
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(s.preacher, style: heading(context, size: 22)),
                            if (detail.preacherBio.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(detail.preacherBio, style: TextStyle(color: p.mutedForeground, height: 1.45)),
                            ],
                          ]),
                        ),
                      ]),
                    ),
                  ),
                ],
              ]),
            ),
            if (snap.connectionState == ConnectionState.waiting)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
            if (detail != null && detail.byPreacher.isNotEmpty) ...[
              SectionTitle(tr('Ще цього проповідника'), eyebrow: s.preacher),
              for (var i = 0; i < detail.byPreacher.length; i++)
                SermonTile(sermon: detail.byPreacher[i], list: detail.byPreacher, index: i),
            ],
            if (detail != null && detail.byBook.isNotEmpty) ...[
              SectionTitle(tr('Ще з цієї книги'), eyebrow: s.books.join(', ')),
              for (var i = 0; i < detail.byBook.length; i++) SermonTile(sermon: detail.byBook[i], list: detail.byBook, index: i),
            ],
          ]);
        },
      ),
    );
  }
}

class _DownloadButton extends StatelessWidget {
  const _DownloadButton({required this.sermon});
  final Sermon sermon;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    final progress = library.downloading[sermon.id];
    if (progress != null) {
      return SizedBox(
        width: 50,
        height: 50,
        child: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (context, v, _) => Stack(alignment: Alignment.center, children: [
            CircularProgressIndicator(strokeWidth: 2.5, value: v > 0 ? v : null),
            Text('${(v * 100).round()}', style: const TextStyle(fontSize: 11)),
          ]),
        ),
      );
    }
    final done = library.isDownloaded(sermon.id);
    return IconButton.outlined(
      iconSize: 24,
      style: IconButton.styleFrom(minimumSize: const Size(50, 50)),
      tooltip: done ? tr('Видалити з телефона') : tr('Зберегти для прослуховування без інтернету'),
      onPressed: () async {
        if (done) {
          final ok = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(tr('Видалити з телефона?')),
              content: Text(tr('Проповідь лишиться на сайті, її можна буде слухати онлайн.')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Скасувати'))),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Видалити'))),
              ],
            ),
          );
          if (ok == true) await library.deleteDownload(sermon.id);
          return;
        }
        try {
          await library.download(sermon);
          if (context.mounted) showSnack(context, tr('Збережено — можна слухати без інтернету'));
        } catch (_) {
          if (context.mounted) showSnack(context, tr('Не вдалося завантажити проповідь'));
        }
      },
      icon: Icon(done ? Icons.download_done : Icons.download_outlined),
    );
  }
}
