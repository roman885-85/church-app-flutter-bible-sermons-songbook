import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../screens/sermon_screen.dart';
import '../services/library.dart';
import '../services/player.dart';
import '../theme.dart';
import '../util/format.dart';
import 'common.dart';
import '../i18n.dart';

/// Рядок проповіді: обкладинка, назва, хто і коли, скільки прослухано.
/// Натиск — сторінка проповіді, кнопка праворуч — одразу слухати.
class SermonTile extends StatelessWidget {
  const SermonTile({super.key, required this.sermon, required this.list, required this.index});

  final Sermon sermon;
  final List<Sermon> list;
  final int index;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final library = context.watch<LibraryService>();
    final player = context.watch<PlayerService>();
    final progress = library.progressOf(sermon);
    final isCurrent = player.isCurrentSermon(sermon.id);
    final meta = [
      if (sermon.preacher.isNotEmpty) sermon.preacher,
      if (sermon.date.isNotEmpty) humanDate(sermon.date),
      if (sermon.duration > 0) humanDuration(sermon.duration),
    ].join(' · ');

    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SermonScreen(sermon: sermon, list: list))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Stack(children: [
            NetImage(sermon.coverUrl, width: 56, height: 56, radius: 10, icon: Icons.mic_none),
            if (library.isDownloaded(sermon.id))
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(color: p.primary, shape: BoxShape.circle),
                  child: Icon(Icons.download_done, size: 12, color: p.primaryForeground),
                ),
              ),
          ]),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(sermon.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, height: 1.25, color: isCurrent ? p.primary : p.foreground)),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: p.mutedForeground)),
              ],
              if (progress > 0) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(value: progress, minHeight: 3, backgroundColor: p.secondary),
                ),
              ],
            ]),
          ),
          const SizedBox(width: 6),
          _PlayButton(sermon: sermon, list: list, index: index, isCurrent: isCurrent),
        ]),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.sermon, required this.list, required this.index, required this.isCurrent});

  final Sermon sermon;
  final List<Sermon> list;
  final int index;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final player = context.read<PlayerService>();
    if (!isCurrent) {
      return IconButton(
        tooltip: tr('Слухати'),
        onPressed: () => player.playSermons(list, index),
        icon: Icon(Icons.play_circle_outline, size: 32, color: p.primary),
      );
    }
    return StreamBuilder<PlayerState>(
      stream: player.player.playerStateStream,
      builder: (context, snap) {
        final playing = snap.data?.playing ?? false;
        return IconButton(
          tooltip: playing ? tr('Пауза') : tr('Слухати'),
          onPressed: player.toggle,
          icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_filled, size: 32, color: p.primary),
        );
      },
    );
  }
}
