import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../services/app_state.dart';
import '../services/live.dart';
import '../services/live_alerts.dart';
import '../widgets/mini_player.dart';
import '../widgets/update_prompt.dart';
import 'bible_screen.dart';
import 'home_screen.dart';
import 'live_screen.dart';
import 'news_screen.dart';
import 'search_screen.dart';
import 'sermon_screen.dart';
import 'video_screen.dart';
import 'sermons_screen.dart';
import 'songbook_screen.dart';
import 'videos_screen.dart';
import '../i18n.dart';

/// Пʼять головних розділів унизу; у кожного своя історія переходів, як у «Слові
/// благодаті». Решта — угорі на кожному розділі: «Ефір», пошук і повне меню
/// (widgets/top_actions.dart), а в самих розділах — вкладки вгорі.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  final _keys = List.generate(5, (_) => GlobalKey<NavigatorState>());
  final _visited = <int>{0};
  StreamSubscription<AlertOpen>? _openLive;

  @override
  void initState() {
    super.initState();
    // Людина торкнулась сповіщення «почалася трансляція».
    final alerts = context.read<LiveAlertsService>();
    _openLive = alerts.openRequests.listen(_openFromAlert);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final request = await alerts.takeLaunchAction();
      if (request != null) _openFromAlert(request);
    });
    // Оновлення — трохи згодом, щоб не заважати першому погляду на головну.
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) unawaited(checkForUpdate(context));
    });
  }

  @override
  void dispose() {
    _openLive?.cancel();
    super.dispose();
  }

  /// Натиск на сповіщення або ярлик на значку: ефір, конкретна
  /// проповідь/відео/новина, розділ чи пошук.
  Future<void> _openFromAlert(AlertOpen request) async {
    if (!mounted) return;
    final root = Navigator.of(context, rootNavigator: true);
    root.popUntil((route) => route.isFirst);
    final id = request.id ?? '';
    switch (request.target) {
      case 'live':
        _showLive();
      case 'tab:sermons':
        // Сповіщення «Нові проповіді» — одразу свіжий список, інакше їх там ще нема.
        unawaited(context.read<AppState>().refresh());
        _select(1);
      case 'tab:videos':
        unawaited(context.read<AppState>().refresh());
        _select(2);
      case 'tab:news':
        await _pushInTab(0, MaterialPageRoute(builder: (_) => const NewsScreen()));
      case 'tab:bible':
        _select(3);
      case 'tab:songbook':
        _select(4);
      case 'search':
        await _pushInTab(_tab, MaterialPageRoute(builder: (_) => SearchScreen(initialQuery: request.title)));
      case 'video' when id.isNotEmpty:
        final video = context.read<AppState>().videos?.latest.where((v) => v.id == id).firstOrNull;
        root.push(MaterialPageRoute(
          builder: (_) => VideoScreen(videoId: id, title: video?.title ?? request.title ?? '', video: video),
        ));
      case 'news' when id.isNotEmpty:
        final item = NewsItem(slug: id, title: request.title ?? '', excerpt: '', date: '', category: '');
        await _pushInTab(0, MaterialPageRoute(builder: (_) => ArticleScreen(item: item)));
      case 'sermon' when id.isNotEmpty:
        final state = context.read<AppState>();
        final api = context.read<Api>();
        Sermon? sermon = state.sermonById(int.tryParse(id) ?? -1);
        if (sermon == null) {
          try {
            sermon = (await api.sermon(int.parse(id))).sermon;
          } catch (_) {
            return;
          }
        }
        if (!mounted) return;
        final found = sermon;
        await _pushInTab(1, MaterialPageRoute(builder: (_) => SermonScreen(sermon: found)));
    }
  }

  /// Перейти на вкладку й відкрити в ній екран. Навігатор вкладки, якої ще не
  /// відкривали, зʼявляється лише в наступному кадрі — тому чекаємо на нього.
  Future<void> _pushInTab(int tab, Route<void> route) async {
    _select(tab);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    _keys[tab].currentState?.popUntil((r) => r.isFirst);
    _keys[tab].currentState?.push(route);
  }

  void _showLive() {
    if (!mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    navigator.popUntil((route) => route.isFirst);
    navigator.push(MaterialPageRoute(builder: (_) => const LiveScreen()));
  }


  void _select(int index) {
    // Перехід між розділами — нагода підтягнути свіже, якщо дані вже постояли.
    unawaited(context.read<AppState>().refreshIfStale());
    if (index == _tab) {
      _keys[index].currentState?.popUntil((route) => route.isFirst);
      return;
    }
    setState(() {
      _tab = index;
      _visited.add(index);
    });
  }

  Widget _root(int index) => switch (index) {
        0 => HomeScreen(openTab: _select),
        1 => const SermonsScreen(),
        2 => const VideosScreen(),
        3 => const BibleScreen(),
        _ => const SongbookScreen(),
      };

  @override
  Widget build(BuildContext context) {
    final live = context.watch<LiveService>();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final nav = _keys[_tab].currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
        } else if (_tab != 0) {
          setState(() => _tab = 0);
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _tab,
          children: [
            for (var i = 0; i < 5; i++)
              _visited.contains(i)
                  ? Navigator(
                      key: _keys[i],
                      onGenerateRoute: (settings) => MaterialPageRoute(settings: settings, builder: (_) => _root(i)),
                    )
                  : const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
          const MiniPlayer(),
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: _select,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: tr('Головна')),
              NavigationDestination(icon: Icon(Icons.headphones_outlined), selectedIcon: Icon(Icons.headphones), label: tr('Проповіді')),
              NavigationDestination(
                icon: Badge(isLabelVisible: live.isLive, backgroundColor: const Color(0xFFD93025), child: const Icon(Icons.smart_display_outlined)),
                selectedIcon: Badge(isLabelVisible: live.isLive, backgroundColor: const Color(0xFFD93025), child: const Icon(Icons.smart_display)),
                label: tr('Відео'),
              ),
              NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: tr('Біблія')),
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music),
                label: tr('Пісенник'),
              ),
            ],
          ),
        ]),
      ),
    );
  }
}
