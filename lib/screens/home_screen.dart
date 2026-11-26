import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../services/app_state.dart';
import '../services/library.dart';
import '../services/live.dart';
import '../services/player.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/live_alerts_prompt.dart';
import '../widgets/sermon_tile.dart';
import '../widgets/top_actions.dart';
import 'contacts_screen.dart';
import 'donation_screen.dart';
import 'live_screen.dart';
import 'news_screen.dart';
import 'sermon_screen.dart';
import 'videos_screen.dart';
import '../i18n.dart';

/// Головна: ефір, вірш, нові проповіді й відео, новини, пожертви.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.openTab});
  final void Function(int tab) openTab;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<NewsItem>> _news;
  DateTime? _newsFor;

  @override
  void initState() {
    super.initState();
    _news = context.read<Api>().news('news');
  }

  Future<void> _refresh() async {
    final state = context.read<AppState>();
    final live = context.read<LiveService>();
    setState(() => _news = context.read<Api>().news('news'));
    await Future.wait([state.refresh(), live.poll()]);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = context.watch<AppState>();
    final live = context.watch<LiveService>();
    final library = context.watch<LibraryService>();
    // Застосунок оновив списки (повернулись у нього, минуло 10 хв) — і новини теж.
    final stamp = state.lastRefresh;
    if (stamp != null && stamp != _newsFor) {
      if (_newsFor != null) _news = context.read<Api>().news('news');
      _newsFor = stamp;
    }
    final config = state.config;
    final sermons = state.catalogue?.sermons ?? const <Sermon>[];
    final latest = sermons.take(12).toList();
    final videos = state.videos?.latest.take(8).toList() ?? const <VideoItem>[];
    final unfinished = library.history.where((s) => library.progressOf(s) > 0).take(3).toList();

    Verse? verse;
    if (config != null && config.verses.isNotEmpty) {
      final day = DateTime.now().difference(DateTime(DateTime.now().year)).inDays;
      verse = config.verses[day % config.verses.length];
    }

    final tilesScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3);

    // Висота стрічок «Нові проповіді» й «Нові відео» росте разом зі шрифтом телефона: картинка + до двох
    // рядків назви + рядок підпису. Раніше висота була сталою (232 і 200), і при великому шрифті назва
    // вилазила за картку (на 200 % — на 32 і 49 точок). Не менше колишньої — при звичайному шрифті як було.
    final ts = MediaQuery.textScalerOf(context);
    final sermonsHeight = math.max(232.0, 156 + 8 + 2 * 1.25 * ts.scale(14) + 1.4 * ts.scale(12) + 8);
    final videosHeight = math.max(200.0, 250 * 9 / 16 + 8 + 2 * 1.25 * ts.scale(13.5) + 2 + 1.4 * ts.scale(12) + 8);

    // Шапка з кнопками (ефір, пошук, меню) закріплена: раніше вона була першим
    // рядком списку й від'їжджала разом зі сторінкою.
    final header = AppBar(
      toolbarHeight: 66,
      titleSpacing: 16,
      automaticallyImplyLeading: false,
      title: Row(children: [
        NetImage(config?.logo, width: 42, height: 42, radius: 21, fit: BoxFit.contain, icon: Icons.church_outlined),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(config?.shortName.isNotEmpty ?? false ? config!.shortName : tr('Відродження'),
                style: heading(context, size: 26), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(config?.name ?? tr('Церква «Відродження»'),
                style: TextStyle(color: p.mutedForeground, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
      actions: [...topActions(context), const SizedBox(width: 4)],
      // Плитки «Ефір · Новини · Пожертва · Контакти» — частина шапки, тож теж не
      // від'їжджають зі сторінкою. Висота — з запасом на збільшений шрифт (до 130 %).
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(66 + 16 * tilesScale),
        child: MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: const _QuickTiles()),
      ),
    );

    if (config == null && state.configError != null && sermons.isEmpty) {
      return Scaffold(appBar: header, body: ErrorView(message: state.configError!, onRetry: state.refresh));
    }

    return Scaffold(
      appBar: header,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(padding: EdgeInsets.zero, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: live.isLive ? LiveNowCard(status: live.status!) : _ServiceCard(config: config),
          ),
          if (config?.live.enabled ?? true) const LiveAlertsSuggestion(),
          if (verse != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                decoration: BoxDecoration(
                  color: p.secondary,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('ВІРШ ДНЯ'), style: TextStyle(fontSize: 11, letterSpacing: 2, color: p.accent, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text('«${verse.text}»', style: heading(context, size: 22, weight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Text(verse.reference, style: TextStyle(color: p.primary, fontWeight: FontWeight.w500)),
                ]),
              ),
            ),
          if (unfinished.isNotEmpty) ...[
            SectionTitle(tr('Продовжити слухати')),
            for (var i = 0; i < unfinished.length; i++) SermonTile(sermon: unfinished[i], list: unfinished, index: i),
          ],
          if (latest.isNotEmpty) ...[
            SectionTitle(tr('Нові проповіді'), eyebrow: tr('Аудіо'), onMore: () => widget.openTab(1)),
            SizedBox(
              height: sermonsHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: latest.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) => _SermonCard(sermon: latest[i], list: latest, index: i),
              ),
            ),
          ] else if (state.sermonsError == null)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
          if (videos.isNotEmpty) ...[
            SectionTitle(tr('Нові відео'), eyebrow: 'YouTube', onMore: () => widget.openTab(2)),
            SizedBox(
              height: videosHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: videos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) => SizedBox(width: 250, child: VideoCard(video: videos[i], compact: true)),
              ),
            ),
          ],
          FutureBuilder<List<NewsItem>>(
            future: _news,
            builder: (context, snap) {
              final items = snap.data ?? const <NewsItem>[];
              if (items.isEmpty) return const SizedBox.shrink();
              return Column(children: [
                SectionTitle(
                  tr('Новини'),
                  eyebrow: tr('Життя церкви'),
                  onMore: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewsScreen())),
                ),
                for (final item in items.take(3))
                  Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 14), child: NewsCard(item: item)),
              ]);
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Card(
              child: ListTile(
                contentPadding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
                leading: Icon(Icons.menu_book_outlined, color: p.primary, size: 30),
                title: Text(tr('Біблія'), style: heading(context, size: 22)),
                subtitle: Text(tr('Переклади, аудіо, коментарі й словники')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => widget.openTab(3),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            child: Card(
              child: ListTile(
                contentPadding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
                leading: Icon(Icons.volunteer_activism_outlined, color: p.primary, size: 30),
                title: Text(tr('Підтримати служіння'), style: heading(context, size: 22)),
                subtitle: Text(tr('Реквізити й пожертва онлайн')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DonationScreen())),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Чотири плитки під шапкою: ефір, новини, пожертва, контакти.
class _QuickTiles extends StatelessWidget {
  const _QuickTiles();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final live = context.watch<LiveService>().isLive;
    void push(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    final tiles = <(IconData, String, VoidCallback, bool)>[
      (
        Icons.live_tv_outlined,
        live ? tr('Наживо') : tr('Ефір'),
        () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const LiveScreen())),
        live,
      ),
      (Icons.article_outlined, tr('Новини'), () => push(const NewsScreen()), false),
      (Icons.volunteer_activism_outlined, tr('Пожертва'), () => push(const DonationScreen()), false),
      (Icons.place_outlined, tr('Контакти'), () => push(const ContactsScreen()), false),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(children: [
        for (final (icon, label, onTap, hot) in tiles)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Material(
                color: hot ? const Color(0xFFD93025) : p.secondary,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(icon, color: hot ? Colors.white : p.primary, size: 26),
                      const SizedBox(height: 6),
                      Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, height: 1.2, fontWeight: FontWeight.w600, color: hot ? Colors.white : p.foreground)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.config});
  final AppConfig? config;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = config;
    return Material(
      color: p.primary,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const LiveScreen())),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('ЗАПРОШУЄМО НА БОГОСЛУЖІННЯ'),
                    style: TextStyle(fontSize: 11, letterSpacing: 1.6, color: p.primaryForeground.withValues(alpha: 0.8))),
                const SizedBox(height: 6),
                Text(
                  c != null && c.serviceDay.isNotEmpty ? '${c.serviceDay} · ${c.serviceTime}' : tr('Неділя · 10:00'),
                  style: heading(context, size: 28, color: p.primaryForeground),
                ),
                const SizedBox(height: 4),
                Text(tr('Пряма трансляція в застосунку'), style: TextStyle(color: p.primaryForeground.withValues(alpha: 0.85))),
              ]),
            ),
            Icon(Icons.live_tv_outlined, color: p.primaryForeground, size: 34),
          ]),
        ),
      ),
    );
  }
}

class _SermonCard extends StatelessWidget {
  const _SermonCard({required this.sermon, required this.list, required this.index});
  final Sermon sermon;
  final List<Sermon> list;
  final int index;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      width: 156,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SermonScreen(sermon: sermon, list: list))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            NetImage(sermon.coverUrl, width: 156, height: 156, radius: 14, icon: Icons.mic_none),
            Positioned(
              right: 8,
              bottom: 8,
              child: Material(
                color: p.primary,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => context.read<PlayerService>().playSermons(list, index),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.play_arrow_rounded, color: p.primaryForeground, size: 24),
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text(sermon.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500, height: 1.25)),
          if (sermon.preacher.isNotEmpty)
            Text(sermon.preacher, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.mutedForeground)),
        ]),
      ),
    );
  }
}
