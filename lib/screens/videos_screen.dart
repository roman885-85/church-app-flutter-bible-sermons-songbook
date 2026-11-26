import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../services/app_state.dart';
import '../services/live.dart';
import '../theme.dart';
import '../util/format.dart';
import '../services/live_alerts.dart';
import '../widgets/common.dart';
import '../widgets/live_alerts_prompt.dart';
import '../widgets/top_actions.dart';
import 'live_screen.dart';
import 'video_screen.dart';
import '../i18n.dart';

void openVideo(BuildContext context, VideoItem video) {
  Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
    builder: (_) => VideoScreen(videoId: video.id, title: video.title, video: video),
  ));
}

/// Відео: вкладки вгорі — нові з каналу, а далі серії, проповідники, вивчення
/// книг, як «Новые / Серии / Книги Библии» у «Слові благодаті».
class VideosScreen extends StatelessWidget {
  const VideosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final live = context.watch<LiveService>();
    final p = context.palette;
    final videos = state.videos;
    final actions = topActions(context, before: const [AlertsBell(kind: AlertKind.videos)]);

    if (videos == null) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Відео')), actions: actions),
        body: state.videosError != null
            ? ErrorView(message: state.videosError!, onRetry: state.refresh)
            : LoadingView(label: tr('Завантажуємо відео…')),
      );
    }

    final sections = videos.sections.where((s) => s.items.isNotEmpty).toList();
    final latest = RefreshIndicator(
      onRefresh: state.refresh,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
        if (live.isLive) ...[
          LiveNowCard(status: live.status!),
          const SizedBox(height: 16),
        ],
        for (final video in videos.latest) ...[
          VideoCard(video: video),
          const SizedBox(height: 18),
        ],
        if (videos.channelUrl != null)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => openExternal(context, videos.channelUrl!),
            icon: const Icon(Icons.smart_display_outlined),
            label: Text(tr('Усі відео на YouTube')),
          ),
      ]),
    );

    return DefaultTabController(
      length: 1 + sections.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('Відео')),
          actions: actions,
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: p.primary,
            indicatorColor: p.primary,
            tabs: [Tab(text: tr('Нові')), for (final section in sections) Tab(text: tr(section.title))],
          ),
        ),
        body: TabBarView(children: [
          latest,
          for (final section in sections)
            RefreshIndicator(
              onRefresh: state.refresh,
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 260,
                  mainAxisSpacing: 18,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.92,
                ),
                itemCount: section.items.length,
                itemBuilder: (context, i) => _CollectionCard(collection: section.items[i], fill: true),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Велика картка відео: мініатюра 16:9, назва, дата.
class VideoCard extends StatelessWidget {
  const VideoCard({super.key, required this.video, this.compact = false});
  final VideoItem video;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => openVideo(context, video),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Stack(children: [
          AspectRatio(aspectRatio: 16 / 9, child: NetImage(video.thumbnail, radius: 14, icon: Icons.smart_display_outlined)),
          Positioned.fill(
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
                child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: compact ? 26 : 34),
              ),
            ),
          ),
          if (video.isService)
            Positioned(
              left: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: p.primary, borderRadius: BorderRadius.circular(999)),
                child: Text(tr('Богослужіння'), style: TextStyle(color: p.primaryForeground, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        Text(video.title,
            maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: compact ? 13.5 : 15.5, fontWeight: FontWeight.w500, height: 1.25)),
        if (video.published.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(humanDate(video.published), style: TextStyle(fontSize: 12, color: p.mutedForeground)),
          ),
      ]),
    );
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({required this.collection, this.fill = false});
  final VideoCollection collection;
  /// У сітці вкладки — на всю ширину клітинки.
  final bool fill;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: fill ? double.infinity : 220,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CollectionScreen(collection: collection))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AspectRatio(aspectRatio: 16 / 10, child: NetImage(collection.image, radius: 14, icon: Icons.video_library_outlined)),
            const SizedBox(height: 8),
            Text(collection.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: heading(context, size: 19)),
          ]),
        ),
      );
}

class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key, required this.collection});
  final VideoCollection collection;

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  late Future<CollectionVideos> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _future = context.read<Api>().collection(widget.collection.kind, widget.collection.slug);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text(widget.collection.title, style: const TextStyle(fontSize: 22))),
      body: FutureBuilder<CollectionVideos>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return ErrorView(message: '${snap.error}', onRetry: () => setState(_load));
          }
          final data = snap.data;
          if (data == null) return const LoadingView();
          final description = data.description.isNotEmpty ? data.description : widget.collection.description;
          return ListView(padding: const EdgeInsets.all(16), children: [
            if (description.isNotEmpty) ...[
              Text(description, style: TextStyle(color: p.mutedForeground, height: 1.5)),
              const SizedBox(height: 16),
            ],
            if (data.videos.isEmpty) EmptyView(icon: Icons.video_library_outlined, text: tr('Відео ще не додано')),
            for (final v in data.videos) Padding(padding: const EdgeInsets.only(bottom: 16), child: VideoCard(video: v)),
          ]);
        },
      ),
    );
  }
}
