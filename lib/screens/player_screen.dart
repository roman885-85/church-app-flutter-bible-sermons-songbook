import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/library.dart';
import '../services/player.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../i18n.dart';

/// Великий плеєр: перемотка, швидкість, таймер сну, обране, завантаження.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final player = context.watch<PlayerService>();
    final library = context.watch<LibraryService>();
    final now = player.current;

    if (now == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyView(icon: Icons.headphones_outlined, text: tr('Зараз нічого не грає')),
      );
    }
    final sermon = now.sermon;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.keyboard_arrow_down, size: 30), onPressed: () => Navigator.of(context).pop()),
        title: Text(sermon != null ? tr('Проповідь') : now.songUrl != null ? tr('Пісенник') : tr('Аудіо-Біблія'), style: TextStyle(fontSize: 15, color: p.mutedForeground)),
        centerTitle: true,
        actions: [
          if (sermon?.url != null)
            IconButton(
              tooltip: tr('Поділитися'),
              icon: const Icon(Icons.ios_share),
              onPressed: () => SharePlus.instance.share(ShareParams(text: '${sermon!.title}\n${sermon.url}')),
            ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          final art = (box.maxWidth - 64).clamp(160.0, box.maxHeight * 0.42);
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(children: [
              const SizedBox(height: 12),
              Center(
                child: NetImage(now.artUrl, width: art, height: art, radius: 24, icon: now.chapter != null ? Icons.menu_book : Icons.mic_none),
              ),
              const SizedBox(height: 28),
              Text(now.title, textAlign: TextAlign.center, style: heading(context, size: 26)),
              if (now.subtitle.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(now.subtitle, textAlign: TextAlign.center, style: TextStyle(color: p.mutedForeground)),
              ],
              const SizedBox(height: 20),
              StreamBuilder<Duration>(
                stream: player.player.positionStream,
                builder: (context, snap) {
                  final total = player.player.duration ?? Duration.zero;
                  final position = snap.data ?? Duration.zero;
                  final max = total.inMilliseconds.toDouble();
                  final value = (_dragging ?? position.inMilliseconds.toDouble()).clamp(0.0, max > 0 ? max : 1.0);
                  return Column(children: [
                    Slider(
                      min: 0,
                      max: max > 0 ? max : 1,
                      value: value,
                      onChanged: max > 0 ? (v) => setState(() => _dragging = v) : null,
                      onChangeEnd: (v) {
                        player.seek(Duration(milliseconds: v.round()));
                        setState(() => _dragging = null);
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text(clock(Duration(milliseconds: value.round())), style: TextStyle(fontSize: 12, color: p.mutedForeground)),
                        Text(total > Duration.zero ? '-${clock(total - Duration(milliseconds: value.round()))}' : '',
                            style: TextStyle(fontSize: 12, color: p.mutedForeground)),
                      ]),
                    ),
                  ]);
                },
              ),
              const SizedBox(height: 8),
              StreamBuilder<PlayerState>(
                stream: player.player.playerStateStream,
                builder: (context, snap) {
                  final state = snap.data;
                  final playing = state?.playing ?? false;
                  final busy = state?.processingState == ProcessingState.loading || state?.processingState == ProcessingState.buffering;
                  return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    IconButton(
                      onPressed: player.player.hasPrevious ? player.player.seekToPrevious : null,
                      icon: const Icon(Icons.skip_previous_rounded, size: 32),
                    ),
                    IconButton(onPressed: () => player.skip(const Duration(seconds: -15)), icon: const Icon(Icons.replay_10_rounded, size: 34)),
                    SizedBox(
                      width: 76,
                      height: 76,
                      child: FilledButton(
                        style: FilledButton.styleFrom(shape: const CircleBorder(), padding: EdgeInsets.zero),
                        onPressed: player.toggle,
                        child: busy && playing
                            ? SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 2.5, color: p.primaryForeground))
                            : Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 44),
                      ),
                    ),
                    IconButton(onPressed: () => player.skip(const Duration(seconds: 30)), icon: const Icon(Icons.forward_30_rounded, size: 34)),
                    IconButton(
                      onPressed: player.player.hasNext ? player.player.seekToNext : null,
                      icon: const Icon(Icons.skip_next_rounded, size: 32),
                    ),
                  ]);
                },
              ),
              if (player.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(player.error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFB3261E))),
                ),
              const SizedBox(height: 18),
              Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [
                ActionChip(
                  avatar: const Icon(Icons.speed, size: 18),
                  label: Text('${_speedLabel(player.speed)}×'),
                  onPressed: () => _chooseSpeed(context, player),
                ),
                ActionChip(
                  avatar: Icon(Icons.bedtime_outlined, size: 18, color: player.sleepAt != null || player.sleepAtEnd ? p.primary : null),
                  label: Text(_sleepLabel(player)),
                  onPressed: () => _chooseSleep(context, player),
                ),
                if (sermon != null)
                  ActionChip(
                    avatar: Icon(library.isFavorite(sermon.id) ? Icons.favorite : Icons.favorite_border,
                        size: 18, color: library.isFavorite(sermon.id) ? p.primary : null),
                    label: Text(tr('Обране')),
                    onPressed: () => library.toggleFavorite(sermon),
                  ),
                if (sermon != null) _DownloadChip(sermonId: sermon.id),
                if (now.chapter != null)
                  FilterChip(
                    avatar: const Icon(Icons.all_inclusive, size: 18),
                    label: Text(tr('Далі без зупинки')),
                    selected: library.bibleContinuous,
                    onSelected: (on) => library.setBibleContinuous(on),
                  ),
              ]),
              const SizedBox(height: 28),
            ]),
          );
        }),
      ),
    );
  }

  static String _speedLabel(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  String _sleepLabel(PlayerService player) {
    if (player.sleepAtEnd) return tr('До кінця запису');
    final at = player.sleepAt;
    if (at == null) return tr('Таймер сну');
    final left = at.difference(DateTime.now());
    return tr('Сон: {a} хв', {'a': left.inMinutes + 1});
  }

  Future<void> _chooseSpeed(BuildContext context, PlayerService player) async {
    const speeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    final chosen = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final s in speeds)
            ListTile(
              title: Text('${_speedLabel(s)}×'),
              trailing: player.speed == s ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, s),
            ),
        ]),
      ),
    );
    if (chosen != null) await player.setSpeed(chosen);
  }

  Future<void> _chooseSleep(BuildContext context, PlayerService player) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final m in [15, 30, 45, 60])
            ListTile(leading: const Icon(Icons.timer_outlined), title: Text(tr('Через {a} хв', {'a': m})), onTap: () => Navigator.pop(context, '$m')),
          ListTile(leading: const Icon(Icons.last_page), title: Text(tr('Наприкінці запису')), onTap: () => Navigator.pop(context, 'end')),
          if (player.sleepAt != null || player.sleepAtEnd)
            ListTile(leading: const Icon(Icons.close), title: Text(tr('Вимкнути таймер')), onTap: () => Navigator.pop(context, 'off')),
        ]),
      ),
    );
    if (chosen == null) return;
    if (chosen == 'off') {
      player.cancelSleep();
    } else if (chosen == 'end') {
      player.setSleepTimer(null, atEnd: true);
    } else {
      player.setSleepTimer(Duration(minutes: int.parse(chosen)));
    }
  }
}

class _DownloadChip extends StatelessWidget {
  const _DownloadChip({required this.sermonId});
  final int sermonId;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    final player = context.read<PlayerService>();
    final sermon = player.current?.sermon;
    if (sermon == null) return const SizedBox.shrink();
    final progress = library.downloading[sermonId];
    if (progress != null) {
      return ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (context, v, _) => ActionChip(
          avatar: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, value: v > 0 ? v : null)),
          label: Text(v > 0 ? '${(v * 100).round()}%' : tr('Завантаження')),
          onPressed: null,
        ),
      );
    }
    final done = library.isDownloaded(sermonId);
    return ActionChip(
      avatar: Icon(done ? Icons.download_done : Icons.download_outlined, size: 18),
      label: Text(done ? tr('Збережено') : tr('Зберегти')),
      onPressed: done
          ? null
          : () async {
              try {
                await library.download(sermon);
                if (context.mounted) showSnack(context, tr('Проповідь збережена — можна слухати без інтернету'));
              } catch (_) {
                if (context.mounted) showSnack(context, tr('Не вдалося завантажити проповідь'));
              }
            },
    );
  }
}
