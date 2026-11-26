import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../api/songbook_models.dart';
import '../midi/midi_file.dart';
import '../services/midi.dart';
import '../services/player.dart';
import '../services/songbook.dart';
import '../theme.dart';
import '../util/format.dart';
import 'picker_button.dart';
import '../i18n.dart';

/// Мінус пісні — власним синтезатором застосунку (services/midi.dart): без
/// інтернету, у фоні, з тими самими звучаннями й вибором, що на сайті.
Future<void> showMidiSheet(BuildContext context, {required String bookCode, required Song song}) async {
  final info = context.read<SongbookService>().info;
  context.read<MidiService>().open(
        bookCode: bookCode,
        song: song,
        siteSoundUrl: info?.soundfontUrl,
        siteMelodyOn: info?.midiMelodyByDefault ?? true,
      );
  await showModalBottomSheet<void>(
    context: context,
    // Над нижньою панеллю й міні-програвачем, а не під ними.
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => const FractionallySizedBox(heightFactor: 0.92, child: _MidiSheet()),
  );
}

class _MidiSheet extends StatelessWidget {
  const _MidiSheet();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final midi = context.watch<MidiService>();
    context.watch<PlayerService>();
    final s = midi.session;
    if (s == null) return const SizedBox.shrink();
    final info = s.info;
    final keyName = transposeKey(s.song.tune, s.transpose);

    return ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 28), children: [
      Row(children: [
        Icon(Icons.piano, color: p.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(tr('Мінус · {a}', {'a': s.title}), style: heading(context, size: 20), maxLines: 2, overflow: TextOverflow.ellipsis)),
        IconButton(icon: const Icon(Icons.close), tooltip: tr('Закрити'), onPressed: () => Navigator.of(context).pop()),
      ]),
      if (s.variants.length > 1) ...[
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < s.variants.length; i++)
            ChoiceChip(
              label: Text(s.variants[i].title.isNotEmpty ? s.variants[i].title : tr('Варіант {a}', {'a': i + 1})),
              selected: i == s.variant,
              onSelected: (_) => midi.setVariant(i),
            ),
        ]),
      ],
      const SizedBox(height: 12),
      _Transport(midi: midi),
      if (midi.status == MidiStatus.bank) ...[
        const SizedBox(height: 10),
        LinearProgressIndicator(value: midi.bankTotal > 0 ? midi.bankLoaded / midi.bankTotal : null),
        const SizedBox(height: 6),
        Text(
          tr('Завантажую звучання «{a}» — {b} з {c} МБ.\nЛише вперше: далі мінуси звучать і без інтернету.', {'a': tr(midi.sound.label), 'b': _mb(midi.bankLoaded), 'c': _mb(midi.bankTotal)}),
          style: TextStyle(color: p.mutedForeground, fontSize: 13, height: 1.4),
        ),
      ],
      if (midi.error != null) ...[
        const SizedBox(height: 10),
        Text(midi.error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 14)),
      ],
      if (midi.isActive && info != null && info.lines.isNotEmpty) ...[
        const SizedBox(height: 14),
        _Karaoke(lines: info.lines, tempo: s.tempo),
      ],
      const SizedBox(height: 18),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: _Stepper(
            label: tr('Тональність'),
            value: s.transpose > 0 ? '+${s.transpose}' : '${s.transpose}',
            onMinus: s.transpose > -6 ? () => midi.setTranspose(s.transpose - 1) : null,
            onPlus: s.transpose < 6 ? () => midi.setTranspose(s.transpose + 1) : null,
            onReset: s.transpose != 0 ? () => midi.setTranspose(0) : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _Stepper(
            label: tr('Темп'),
            value: '${(s.tempo * 100).round()} %',
            onMinus: s.tempo > 0.5 ? () => midi.setTempo(s.tempo - 0.05) : null,
            onPlus: s.tempo < 1.5 ? () => midi.setTempo(s.tempo + 0.05) : null,
            onReset: s.tempo != 1.0 ? () => midi.setTempo(1.0) : null,
          ),
        ),
      ]),
      if (keyName != null) ...[
        const SizedBox(height: 6),
        Text(tr('Тональність: {a}', {'a': keyName}), style: TextStyle(color: p.mutedForeground, fontSize: 13)),
      ],
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
        decoration: BoxDecoration(border: Border.all(color: p.border), borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Part(
            label: tr('Мелодія'),
            hintOn: tr('звучить підказка голосу'),
            hintOff: tr('вимкнена — чистий мінус'),
            choice: midi.melody,
            options: melodyInstruments,
            onChanged: midi.setMelody,
          ),
          Divider(height: 20, color: p.border),
          _Part(
            label: tr('Акомпанемент'),
            hintOn: tr('звучить супровід'),
            hintOff: tr('вимкнений — лише мелодія для розучування'),
            choice: midi.accompaniment,
            options: accompanimentInstruments,
            onChanged: midi.setAccompaniment,
          ),
          const SizedBox(height: 14),
          PickerButton(
            caption: tr('Звучання'),
            value: tr(midi.sound.label),
            icon: Icons.graphic_eq,
            onPressed: () => _chooseSound(context, midi),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      Text(tr('Звук: {a}; синтезатор FluidSynth (LGPL 2.1).', {'a': tr(midi.sound.credit)}), style: TextStyle(color: p.mutedForeground, fontSize: 11, height: 1.4)),
    ]);
  }

  static String _mb(int bytes) => (bytes / 1048576).toStringAsFixed(1).replaceAll('.', ',');

  Future<void> _chooseSound(BuildContext context, MidiService midi) async {
    final p = context.palette;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(tr('Звучання'), style: heading(context, size: 24)),
          ),
          for (final s in midiSounds)
            ListTile(
              leading: Icon(s.id == midi.sound.id ? Icons.radio_button_checked : Icons.radio_button_off, color: s.id == midi.sound.id ? p.primary : null),
              title: Text(tr(s.label), style: TextStyle(fontWeight: s.id == midi.sound.id ? FontWeight.w600 : FontWeight.w400)),
              subtitle: Text('${tr(s.hint)} · ${midi.isOnPhone(s) ? tr('на телефоні') : tr('завантажиться {a}', {'a': s.sizeLabel})}'),
              onTap: () => Navigator.pop(context, s.id),
            ),
        ]),
      ),
    );
    if (chosen != null) midi.setSound(chosen);
  }
}

/// ▶/⏸ і смуга перемотування.
class _Transport extends StatelessWidget {
  const _Transport({required this.midi});
  final MidiService midi;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final player = context.read<PlayerService>().player;
    final active = midi.isActive;
    final preparing = midi.status == MidiStatus.bank || midi.status == MidiStatus.song;
    return StreamBuilder<PlayerState>(
      stream: player.playerStateStream,
      builder: (context, snap) {
        final state = snap.data;
        final playing = active && (state?.playing ?? false) && state?.processingState != ProcessingState.completed;
        final buffering = active && (state?.processingState == ProcessingState.loading || state?.processingState == ProcessingState.buffering);
        return Row(children: [
          SizedBox(
            width: 60,
            height: 60,
            child: FilledButton(
              style: FilledButton.styleFrom(shape: const CircleBorder(), padding: EdgeInsets.zero),
              onPressed: preparing ? null : midi.toggle,
              child: preparing || buffering
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      // Поки готується, кнопка неактивна (світла) — колесо темне, щоб його було видно.
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: preparing ? p.primary : p.primaryForeground),
                    )
                  : Icon(playing ? Icons.pause : Icons.play_arrow, size: 32),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: active
                ? StreamBuilder<Duration>(
                    stream: player.positionStream,
                    builder: (context, snap) {
                      final total = player.duration ?? Duration.zero;
                      final position = snap.data ?? Duration.zero;
                      final max = total.inMilliseconds > 0 ? total.inMilliseconds.toDouble() : 1.0;
                      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Slider(
                          value: position.inMilliseconds.clamp(0, max).toDouble(),
                          max: max,
                          onChanged: total > Duration.zero ? (v) => player.seek(Duration(milliseconds: v.round())) : null,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 22),
                          child: Row(children: [
                            Text(clock(position), style: TextStyle(fontSize: 12, color: p.mutedForeground)),
                            const Spacer(),
                            Text(total > Duration.zero ? clock(total) : '', style: TextStyle(fontSize: 12, color: p.mutedForeground)),
                          ]),
                        ),
                      ]);
                    },
                  )
                : Text(
                    switch (midi.status) {
                      MidiStatus.bank => tr('Завантажую звучання…'),
                      MidiStatus.song => tr('Готую пісню…'),
                      _ => tr('Натисніть ▶ — мінус звучить і у фоні, і без інтернету.'),
                    },
                    style: TextStyle(color: p.mutedForeground, fontSize: 14, height: 1.35),
                  ),
          ),
        ]);
      },
    );
  }
}

/// Слова караоке: рядок, що звучить (проспівані склади — кольором), і наступний.
class _Karaoke extends StatelessWidget {
  const _Karaoke({required this.lines, required this.tempo});
  final List<LyricLine> lines;
  final double tempo;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final player = context.read<PlayerService>().player;
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, snap) {
        final time = (snap.data ?? Duration.zero).inMilliseconds / 1000 * tempo;
        var index = -1;
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].start <= time + 0.05) {
            index = i;
          } else {
            break;
          }
        }
        final current = lines[index < 0 ? 0 : index];
        final next = index + 1 < lines.length ? lines[index + 1] : null;
        // Висота не стрибає від рядка до рядка — кнопки нижче лишаються на місці.
        return Container(
          constraints: const BoxConstraints(minHeight: 104),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: p.secondary, borderRadius: BorderRadius.circular(14)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Проспіване — заливкою основного кольору зі світлим текстом, решта —
            // приглушено. Лише кольором тексту стани майже не розрізнялись: у
            // світлій темі основний колір темний, як і сам текст.
            Text.rich(
              TextSpan(children: [
                for (final syl in current.syllables)
                  if (index >= 0 && syl.time <= time + 0.05)
                    TextSpan(
                      text: syl.text,
                      style: TextStyle(color: p.primaryForeground, backgroundColor: p.primary),
                    )
                  else
                    TextSpan(text: syl.text, style: TextStyle(color: p.foreground.withValues(alpha: 0.55))),
              ]),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 19, height: 1.35, fontWeight: FontWeight.w500),
            ),
            if (next != null) ...[
              const SizedBox(height: 4),
              Text(next.text, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: p.mutedForeground)),
            ],
          ]),
        );
      },
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.label, required this.value, this.onMinus, this.onPlus, this.onReset});
  final String label;
  final String value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: TextStyle(fontSize: 12, color: p.mutedForeground, fontWeight: FontWeight.w500)),
        if (onReset != null)
          InkWell(
            onTap: onReset,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(tr('скинути'), style: TextStyle(fontSize: 12, color: p.primary)),
            ),
          ),
      ]),
      const SizedBox(height: 4),
      Row(children: [
        IconButton.outlined(onPressed: onMinus, icon: const Icon(Icons.remove), tooltip: tr('{a}: менше', {'a': label})),
        Expanded(
          child: Text(value, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
        ),
        IconButton.outlined(onPressed: onPlus, icon: const Icon(Icons.add), tooltip: tr('{a}: більше', {'a': label})),
      ]),
    ]);
  }
}

/// Партія: увімкнути/вимкнути й обрати інструмент.
class _Part extends StatelessWidget {
  const _Part({required this.label, required this.hintOn, required this.hintOff, required this.choice, required this.options, required this.onChanged});
  final String label;
  final String hintOn;
  final String hintOff;
  final PartChoice choice;
  final List<(int, String)> options;
  final ValueChanged<PartChoice> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(choice.on ? hintOn : hintOff, style: TextStyle(color: p.mutedForeground, fontSize: 13)),
        value: choice.on,
        onChanged: (on) => onChanged(choice.copyWith(on: on)),
      ),
      PickerButton(
        caption: tr('Інструмент'),
        value: instrumentLabel(options, choice.program),
        icon: Icons.music_note_outlined,
        onPressed: choice.on ? () => _pick(context) : null,
      ),
    ]);
  }

  Future<void> _pick(BuildContext context) async {
    final p = context.palette;
    final chosen = await showModalBottomSheet<int>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(tr('{a}: інструмент', {'a': label}), style: heading(context, size: 22)),
          ),
          for (final (program, name) in options)
            ListTile(
              leading: Icon(program == choice.program ? Icons.radio_button_checked : Icons.radio_button_off, color: program == choice.program ? p.primary : null),
              title: Text(tr(name)),
              onTap: () => Navigator.pop(context, program),
            ),
        ]),
      ),
    );
    if (chosen != null) onChanged(choice.copyWith(program: chosen, on: true));
  }
}
