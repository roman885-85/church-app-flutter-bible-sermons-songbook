import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../api/models.dart';
import '../services/app_state.dart';
import '../services/player.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/sermon_tile.dart';
import '../i18n.dart';

/// Відео з нашого каналу — офіційним плеєром YouTube.
///
/// Відео YouTube не можна грати у фоні чи з вимкненим екраном (так вимагають
/// правила YouTube), тож коли застосунок згортають, відео стає на паузу. Для
/// фону — «Слухати»: той самий запис звуком із сервера церкви.
class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key, required this.videoId, required this.title, this.video, this.live = false});

  final String videoId;
  final String title;
  final VideoItem? video;
  final bool live;

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> with WidgetsBindingObserver {
  late final YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        showFullscreenButton: true,
        strictRelatedVideos: true,
        interfaceLanguage: 'uk',
        captionLanguage: 'uk',
      ),
    );
    // Звук проповіді й відео разом — какофонія: відео починається, звук стає.
    final player = context.read<PlayerService>();
    if (player.player.playing) player.player.pause();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) _controller.pauseVideo();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = context.watch<AppState>();
    final video = widget.video;
    final sermons = video != null
        ? state.sermonsForVideo(video)
        : (state.catalogue?.sermons ?? const <Sermon>[]).where((s) => s.videoId == widget.videoId).toList();
    final url = 'https://www.youtube.com/watch?v=${widget.videoId}';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.live ? tr('Пряма трансляція') : tr('Відео'), style: const TextStyle(fontSize: 22)),
        actions: [
          IconButton(
            tooltip: tr('Поділитися'),
            icon: const Icon(Icons.ios_share),
            onPressed: () => SharePlus.instance.share(ShareParams(text: '${widget.title}\n$url')),
          ),
        ],
      ),
      body: ListView(children: [
        YoutubePlayer(controller: _controller, aspectRatio: 16 / 9),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (widget.live) ...[const LiveBadge(), const SizedBox(height: 10)],
            Text(widget.title, style: heading(context, size: 26)),
            if (video?.published.isNotEmpty ?? false) ...[
              const SizedBox(height: 6),
              Text(humanDate(video!.published), style: TextStyle(color: p.mutedForeground)),
            ],
            const SizedBox(height: 16),
            Wrap(spacing: 10, runSpacing: 10, children: [
              OutlinedButton.icon(
                onPressed: () => openExternal(context, url),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(tr('Відкрити в YouTube')),
              ),
            ]),
          ]),
        ),
        if (sermons.isNotEmpty) ...[
          SectionTitle(
            sermons.length == 1 ? tr('Слухати звуком') : tr('Звук цього богослужіння'),
            eyebrow: tr('Можна у фоні й без екрана'),
          ),
          for (var i = 0; i < sermons.length; i++) SermonTile(sermon: sermons[i], list: sermons, index: i),
        ],
        const SizedBox(height: 32),
      ]),
    );
  }
}
