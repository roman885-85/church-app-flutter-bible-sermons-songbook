import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'song_screen.dart';
import '../i18n.dart';

/// Одні ноти: сторінки для перегляду (дотик — на весь екран), запис для
/// прослуховування і оригінальні файли на завантаження — те саме, що на сайті.
class SheetScreen extends StatefulWidget {
  const SheetScreen({super.key, required this.sheet});

  final SheetMusic sheet;

  @override
  State<SheetScreen> createState() => _SheetScreenState();
}

class _SheetScreenState extends State<SheetScreen> {
  AudioPlayer? _player;
  bool _playing = false;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggleAudio(String url) async {
    final player = _player ??= AudioPlayer();
    try {
      if (_playing) {
        await player.pause();
        if (mounted) setState(() => _playing = false);
        return;
      }
      if (player.audioSource == null) await player.setUrl(url);
      await player.play();
      if (mounted) setState(() => _playing = true);
      player.playerStateStream.listen((state) {
        if (!mounted) return;
        if (state.processingState == ProcessingState.completed) setState(() => _playing = false);
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Не вдалося програти запис'))));
        setState(() => _playing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheet = widget.sheet;
    final p = context.palette;
    final mp3 = sheet.fileOf('mp3');
    return Scaffold(
      appBar: AppBar(title: Text(sheet.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 28), children: [
        Text(sheet.title, style: heading(context, size: 26)),
        if (sheet.subtitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(sheet.subtitle, style: TextStyle(color: p.mutedForeground, fontSize: 13, height: 1.4)),
          ),
        const SizedBox(height: 14),

        if (mp3 != null)
          FilledButton.icon(
            onPressed: () => _toggleAudio(mp3.url),
            icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
            label: Text(_playing ? tr('Пауза') : tr('Прослухати запис')),
          ),

        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final file in sheet.files.where((f) => f.kind != 'image'))
            OutlinedButton.icon(
              onPressed: () => openExternal(context, file.url),
              icon: Icon(file.kind == 'pdf'
                  ? Icons.picture_as_pdf_outlined
                  : file.kind == 'midi'
                      ? Icons.piano_outlined
                      : file.kind == 'mp3'
                          ? Icons.download_outlined
                          : Icons.description_outlined),
              label: Text(file.sizeLabel.isEmpty ? file.label : '${file.label} · ${file.sizeLabel}'),
            ),
        ]),

        if (sheet.hasSong)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: FilledButton.tonalIcon(
              onPressed: () => openExternal(context, '${Api.siteUrl}/songbook/${Uri.encodeComponent(sheet.songBook)}/${sheet.songNumber}'),
              icon: const Icon(Icons.library_music_outlined),
              label: Text(tr('Ця пісня в пісеннику')),
            ),
          ),

        if (sheet.source.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              tr('Джерело: {a}{b}', {'a': sheet.source, 'b': sheet.license.isEmpty ? '' : '\n${sheet.license}'}),
              style: TextStyle(color: p.mutedForeground, fontSize: 11.5, height: 1.4),
            ),
          ),

        const SizedBox(height: 16),
        for (var i = 0; i < sheet.pages.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotesZoom(url: sheet.pages[i]))),
              child: Container(
                color: Colors.white,
                child: NetImage(sheet.pages[i], fit: BoxFit.fitWidth, radius: 8, icon: Icons.queue_music),
              ),
            ),
          ),
        if (sheet.pages.isEmpty)
          Text(tr('Сторінок для перегляду немає — відкрийте файл кнопкою вище.'), style: TextStyle(color: p.mutedForeground)),
      ]),
    );
  }
}
