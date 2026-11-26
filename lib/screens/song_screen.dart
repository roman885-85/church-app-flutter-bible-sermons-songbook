import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api.dart';
import '../api/songbook_models.dart';
import '../services/library.dart';
import '../services/player.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/midi_sheet.dart';
import '../i18n.dart';

/// Пісня: слова крупно; сусідні пісні — гортанням убік.
///
/// Ноти, мінус і записи — кнопками над словами: головне — слова, решта на прохання.
class SongScreen extends StatefulWidget {
  const SongScreen({super.key, required this.bookCode, required this.songs, required this.initialIndex});

  final String bookCode;
  final List<Song> songs;
  final int initialIndex;

  @override
  State<SongScreen> createState() => _SongScreenState();
}

class _SongScreenState extends State<SongScreen> {
  late final PageController _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  late double _font;
  late bool _notesOpen;

  @override
  void initState() {
    super.initState();
    final library = context.read<LibraryService>();
    _font = library.songFont;
    _notesOpen = library.songNotesOpen ?? false;
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _setFont(double value) {
    setState(() => _font = value.clamp(14, 40));
    context.read<LibraryService>().setSongFont(_font);
  }

  void _toggleNotes() {
    setState(() => _notesOpen = !_notesOpen);
    context.read<LibraryService>().setSongNotesOpen(_notesOpen);
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.songs[_index];
    return Scaffold(
      appBar: AppBar(
        title: Text('№ ${song.number}'),
        actions: [
          IconButton(icon: const Icon(Icons.text_decrease), tooltip: tr('Менший текст'), onPressed: () => _setFont(_font - 2)),
          IconButton(icon: const Icon(Icons.text_increase), tooltip: tr('Більший текст'), onPressed: () => _setFont(_font + 2)),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: tr('Поділитися'),
            onPressed: () => SharePlus.instance.share(ShareParams(
              text: '${song.number}. ${song.title}\n${Api.siteUrl}/songbook/${Uri.encodeComponent(widget.bookCode)}/${song.number}',
            )),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: widget.songs.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) => _SongPage(
          song: widget.songs[i],
          bookCode: widget.bookCode,
          font: _font,
          notesOpen: _notesOpen,
          onToggleNotes: _toggleNotes,
        ),
      ),
    );
  }
}

class _SongPage extends StatelessWidget {
  const _SongPage({required this.song, required this.bookCode, required this.font, required this.notesOpen, required this.onToggleNotes});

  final Song song;
  final String bookCode;
  final double font;
  final bool notesOpen;
  final VoidCallback onToggleNotes;

  String _labelled(String label, String value) {
    if (value.isEmpty) return '';
    return RegExp(r'^[\p{L} ]{3,20}:', unicode: true).hasMatch(value) ? value : '$label: $value';
  }

  Future<void> _playRecordings(BuildContext context, String kind) async {
    final items = song.mediaOf(kind);
    if (items.isEmpty) return;
    final player = context.read<PlayerService>();
    final subtitle = kind == 'minus' ? tr('Фонограма') : tr('Спів');
    Future<void> play(SongMedia m) => player.playSongRecording(
          url: m.url,
          title: '${song.number}. ${song.title}',
          subtitle: m.title.isNotEmpty ? '$subtitle · ${m.title}' : subtitle,
        );
    if (items.length == 1) {
      await play(items.first);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(kind == 'minus' ? tr('Фонограми') : tr('Записи співу'), style: heading(sheet, size: 22)),
          ),
          for (var i = 0; i < items.length; i++)
            ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: Text(items[i].title.isNotEmpty ? items[i].title : tr('Варіант {a}', {'a': i + 1})),
              subtitle: items[i].durationSec > 0
                  ? Text('${items[i].durationSec ~/ 60}:${(items[i].durationSec % 60).toString().padLeft(2, '0')}')
                  : null,
              onTap: () {
                Navigator.of(sheet).pop();
                play(items[i]);
              },
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final credits = [
      if (song.tune.isNotEmpty) tr('Тональність: {a}', {'a': song.tune}),
      _labelled(tr('Слова'), song.wordsBy),
      _labelled(tr('Музика'), song.musicBy),
    ].where((c) => c.isNotEmpty).join(' · ');
    final notes = song.mediaOf('notes');
    final sources = {for (final m in song.media) if (m.source.isNotEmpty) m.source}.toList();

    var verse = 0;
    final numbers = [
      for (final part in song.parts)
        if (part.kind == 'verse') () {
          final digits = RegExp(r'\d+').firstMatch(part.label)?.group(0);
          verse = digits != null ? int.parse(digits) : verse + 1;
          return '$verse';
        }() else null,
    ];

    return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
      Text(song.title, style: heading(context, size: 28)),
      if (credits.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(credits, style: TextStyle(color: p.mutedForeground, fontSize: 13)),
      ],
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (song.has('midi'))
          FilledButton.tonalIcon(
            onPressed: () => showMidiSheet(context, bookCode: bookCode, song: song),
            icon: const Icon(Icons.piano, size: 18),
            label: Text(tr('Мінус')),
          ),
        if (song.has('minus'))
          FilledButton.tonalIcon(
            onPressed: () => _playRecordings(context, 'minus'),
            icon: const Icon(Icons.music_note, size: 18),
            label: Text(tr('Фонограма')),
          ),
        if (song.has('song'))
          FilledButton.tonalIcon(
            onPressed: () => _playRecordings(context, 'song'),
            icon: const Icon(Icons.mic_none, size: 18),
            label: Text(tr('Спів')),
          ),
      ]),
      // Вигляд пісні: просто слова або слова з нотами (сторінки нот зі словами під нотним станом).
      if (notes.isNotEmpty) ...[
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(tr('Слова')), icon: Icon(Icons.notes)),
            ButtonSegment(value: true, label: Text(tr('З нотами')), icon: Icon(Icons.queue_music)),
          ],
          selected: {notesOpen},
          showSelectedIcon: false,
          onSelectionChanged: (value) {
            if (value.first != notesOpen) onToggleNotes();
          },
        ),
      ],
      if (notesOpen && notes.isNotEmpty) ...[
        const SizedBox(height: 14),
        for (final n in notes)
          for (final page in (n.pages.isNotEmpty ? n.pages : [n.url]))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotesZoom(url: page))),
                child: Container(
                  color: Colors.white,
                  child: NetImage(page, fit: BoxFit.fitWidth, radius: 8, icon: Icons.queue_music),
                ),
              ),
            ),
        // Слова окремо — нижче: у нотах бувають не всі куплети.
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(tr('СЛОВА'), style: TextStyle(fontSize: 12, letterSpacing: 1.6, fontWeight: FontWeight.w600, color: p.mutedForeground)),
        ),
      ],
      const SizedBox(height: 18),
      for (var i = 0; i < song.parts.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: song.parts[i].kind == 'chorus'
              ? Container(
                  padding: const EdgeInsets.only(left: 14),
                  decoration: BoxDecoration(border: Border(left: BorderSide(color: p.primary.withValues(alpha: 0.4), width: 2))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(song.parts[i].label.toUpperCase(),
                        style: TextStyle(fontSize: 11, letterSpacing: 1.6, color: p.mutedForeground, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(song.parts[i].text, style: TextStyle(fontSize: font, height: 1.5, fontStyle: FontStyle.italic)),
                  ]),
                )
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 26,
                    child: numbers[i] == null
                        ? null
                        : Text(numbers[i]!, style: TextStyle(fontSize: font * 0.8, height: 1.9, color: p.primary, fontWeight: FontWeight.w700)),
                  ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (song.parts[i].kind != 'verse' && song.parts[i].label.isNotEmpty)
                        Text(song.parts[i].label.toUpperCase(),
                            style: TextStyle(fontSize: 11, letterSpacing: 1.6, color: p.mutedForeground, fontWeight: FontWeight.w600)),
                      Text(song.parts[i].text, style: TextStyle(fontSize: font, height: 1.5)),
                    ]),
                  ),
                ]),
        ),
      if (sources.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(tr('Записи й мінуси: {a}', {'a': sources.join('; ')}), style: TextStyle(color: p.mutedForeground, fontSize: 11)),
      ],
    ]);
  }
}

/// Ноти на весь екран (спільне для пісенника й розділу «Ноти»).
class NotesZoom extends StatelessWidget {
  const NotesZoom({super.key, required this.url});
  final String url;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(title: Text(tr('Ноти'))),
        body: InteractiveViewer(
          maxScale: 5,
          child: Center(child: NetImage(url, fit: BoxFit.contain, radius: 0, icon: Icons.queue_music)),
        ),
      );
}
