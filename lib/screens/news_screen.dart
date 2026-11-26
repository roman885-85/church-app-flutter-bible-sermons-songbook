import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../theme.dart';
import '../services/live_alerts.dart';
import '../widgets/common.dart';
import '../widgets/live_alerts_prompt.dart';
import 'video_screen.dart';
import '../i18n.dart';

/// Новини, статті, фото — розділи сайту.
class NewsScreen extends StatelessWidget {
  const NewsScreen({super.key, this.initialTab = 0});
  final int initialTab;

  static List<(String, String)> get sections => [('news', tr('Новини')), ('articles', tr('Статті')), ('photos', tr('Фото'))];

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: sections.length,
        initialIndex: initialTab,
        child: Scaffold(
          appBar: AppBar(
            title: Text(tr('Новини та статті')),
            actions: const [AlertsBell(kind: AlertKind.news)],
            bottom: TabBar(
              labelColor: context.palette.primary,
              indicatorColor: context.palette.primary,
              tabs: [for (final s in sections) Tab(text: s.$2)],
            ),
          ),
          body: TabBarView(children: [for (final s in sections) _NewsList(section: s.$1)]),
        ),
      );
}

class _NewsList extends StatefulWidget {
  const _NewsList({required this.section});
  final String section;

  @override
  State<_NewsList> createState() => _NewsListState();
}

class _NewsListState extends State<_NewsList> with AutomaticKeepAliveClientMixin {
  late Future<List<NewsItem>> _future;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _future = context.read<Api>().news(widget.section);
  }

  Future<void> _reload() async {
    final next = context.read<Api>().news(widget.section);
    setState(() => _future = next);
    await next.catchError((_) => <NewsItem>[]);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<NewsItem>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorView(message: '${snap.error}', onRetry: _reload);
        if (!snap.hasData) return const LoadingView();
        final items = snap.data!;
        if (items.isEmpty) return EmptyView(icon: Icons.article_outlined, text: tr('Поки що нічого немає'));
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 16),
            itemBuilder: (context, i) => NewsCard(item: items[i]),
          ),
        );
      },
    );
  }
}

class NewsCard extends StatelessWidget {
  const NewsCard({super.key, required this.item});
  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ArticleScreen(item: item))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (item.image != null) AspectRatio(aspectRatio: 16 / 9, child: NetImage(item.image, radius: 0)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                [if (item.category.isNotEmpty) item.category.toUpperCase(), if (item.date.isNotEmpty) item.date].join(' · '),
                style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: p.accent),
              ),
              const SizedBox(height: 6),
              Text(item.title, style: heading(context, size: 22)),
              if (item.excerpt.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(item.excerpt, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.mutedForeground, height: 1.45)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

class ArticleScreen extends StatefulWidget {
  const ArticleScreen({super.key, required this.item});
  final NewsItem item;

  @override
  State<ArticleScreen> createState() => _ArticleScreenState();
}

class _ArticleScreenState extends State<ArticleScreen> {
  late Future<NewsArticle> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<Api>().article(widget.item.slug);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final item = widget.item;
    return Scaffold(
      appBar: AppBar(actions: [
        if (item.url != null)
          IconButton(
            icon: const Icon(Icons.ios_share),
            onPressed: () => SharePlus.instance.share(ShareParams(text: '${item.title}\n${item.url}')),
          ),
      ]),
      body: FutureBuilder<NewsArticle>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return ErrorView(
              message: '${snap.error}',
              onRetry: () => setState(() => _future = context.read<Api>().article(item.slug)),
            );
          }
          final article = snap.data;
          // Зі сповіщення приходить лише адреса й назва — решту бере зі статті.
          final image = item.image ?? article?.item.image;
          final date = item.date.isNotEmpty ? item.date : (article?.item.date ?? '');
          final title = item.title.isNotEmpty ? item.title : (article?.item.title ?? '');
          return ListView(padding: const EdgeInsets.only(bottom: 40), children: [
            if (image != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AspectRatio(aspectRatio: 16 / 9, child: NetImage(image, radius: 16)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (date.isNotEmpty) Text(date, style: TextStyle(color: p.mutedForeground)),
                const SizedBox(height: 6),
                Text(title, style: heading(context, size: 30)),
              ]),
            ),
            if (article == null)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            else ...[
              if (article.videoId != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
                      builder: (_) => VideoScreen(videoId: article.videoId!, title: item.title),
                    )),
                    icon: const Icon(Icons.smart_display_outlined),
                    label: Text(tr('Дивитися відео')),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: HtmlWidget(
                  article.html,
                  baseUrl: Uri.parse(Api.siteUrl),
                  textStyle: TextStyle(fontSize: 16.5, height: 1.6, color: p.foreground),
                  onTapUrl: (url) {
                    openExternal(context, url.startsWith('/') ? '${Api.siteUrl}$url' : url);
                    return true;
                  },
                ),
              ),
              if (article.gallery.isNotEmpty) ...[
                SectionTitle(tr('Фото')),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 6, crossAxisSpacing: 6),
                    itemCount: article.gallery.length,
                    itemBuilder: (context, i) => GestureDetector(
                      onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
                        builder: (_) => PhotoViewer(photos: article.gallery, initial: i),
                      )),
                      child: NetImage(article.gallery[i].url, radius: 8),
                    ),
                  ),
                ),
              ],
              if (article.documentUrl != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: OutlinedButton.icon(
                    onPressed: () => openExternal(context, article.documentUrl!),
                    icon: const Icon(Icons.description_outlined),
                    label: Text(tr('Відкрити документ')),
                  ),
                ),
            ],
          ]);
        },
      ),
    );
  }
}

class PhotoViewer extends StatefulWidget {
  const PhotoViewer({super.key, required this.photos, required this.initial});
  final List<Photo> photos;
  final int initial;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final PageController _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1} / ${widget.photos.length}', style: const TextStyle(color: Colors.white, fontSize: 18)),
      ),
      body: Stack(children: [
        PageView.builder(
          controller: _pages,
          itemCount: widget.photos.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (context, i) => InteractiveViewer(
            maxScale: 4,
            child: Center(child: NetImage(widget.photos[i].url, fit: BoxFit.contain, radius: 0)),
          ),
        ),
        if (photo.caption.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              child: Text(photo.caption, style: const TextStyle(color: Colors.white)),
            ),
          ),
      ]),
    );
  }
}
