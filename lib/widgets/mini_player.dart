import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../screens/player_screen.dart';
import '../services/player.dart';
import '../theme.dart';
import 'common.dart';
import '../i18n.dart';

/// Смужка над нижнім меню, поки щось грає: назва, пауза, закрити.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final now = player.current;
    if (now == null) return const SizedBox.shrink();
    final p = context.palette;

    return Material(
      color: p.card,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlayerScreen())),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          StreamBuilder<Duration>(
            stream: player.player.positionStream,
            builder: (context, snap) {
              final total = player.player.duration?.inMilliseconds ?? 0;
              final value = total > 0 ? ((snap.data?.inMilliseconds ?? 0) / total).clamp(0.0, 1.0) : 0.0;
              return LinearProgressIndicator(value: value, minHeight: 2, backgroundColor: p.border);
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(children: [
              NetImage(now.artUrl, width: 42, height: 42, radius: 8, icon: now.chapter != null ? Icons.menu_book : Icons.mic_none),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(now.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
                  if (player.error != null)
                    Text(tr('Помилка відтворення — натисніть ▶'),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFFB3261E)))
                  else if (now.subtitle.isNotEmpty)
                    Text(now.subtitle,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.mutedForeground)),
                ]),
              ),
              StreamBuilder<PlayerState>(
                stream: player.player.playerStateStream,
                builder: (context, snap) {
                  final state = snap.data;
                  final loading = state?.processingState == ProcessingState.loading || state?.processingState == ProcessingState.buffering;
                  if (loading && (state?.playing ?? false)) {
                    return const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                    );
                  }
                  final playing = state?.playing ?? false;
                  return IconButton(
                    onPressed: player.toggle,
                    icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 32, color: p.primary),
                  );
                },
              ),
              IconButton(onPressed: player.stop, icon: Icon(Icons.close, color: p.mutedForeground)),
            ]),
          ),
          Divider(height: 1, color: p.border),
        ]),
      ),
    );
  }
}
