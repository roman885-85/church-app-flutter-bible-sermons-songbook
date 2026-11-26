import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../services/app_state.dart';
import '../services/live.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/live_alerts_prompt.dart';
import 'video_screen.dart';
import 'videos_screen.dart';
import '../i18n.dart';

/// Прямий ефір — за тим самим принципом, що й на сайті: поки трансляції немає,
/// видно запрошення з розкладом; щойно вона почнеться, тут зʼявиться плеєр.
class LiveScreen extends StatelessWidget {
  const LiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final live = context.watch<LiveService>();
    final state = context.watch<AppState>();
    final config = state.config;
    final status = live.status;

    if (status != null && status.isLive) {
      return VideoScreen(key: ValueKey(status.videoId), videoId: status.videoId!, title: status.title ?? tr('Пряма трансляція'), live: true);
    }

    final p = context.palette;
    final settings = config?.live;
    final lastService = state.videos?.latest.where((v) => v.isService).firstOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(tr('Прямий ефір'))),
      body: RefreshIndicator(
        onRefresh: live.poll,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                NetImage(settings?.logo ?? config?.logo, width: 88, height: 88, radius: 44, fit: BoxFit.contain, icon: Icons.church_outlined),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(color: p.secondary, borderRadius: BorderRadius.circular(999)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.radio_button_checked, size: 14, color: p.mutedForeground),
                    const SizedBox(width: 6),
                    Text(settings?.badgeText.isNotEmpty ?? false ? settings!.badgeText : tr('Трансляція не ведеться'),
                        style: TextStyle(fontSize: 12.5, color: p.mutedForeground)),
                  ]),
                ),
                const SizedBox(height: 16),
                Text(
                  settings?.heading.isNotEmpty ?? false ? settings!.heading : tr('Приєднуйтеся до прямих трансляцій богослужінь'),
                  textAlign: TextAlign.center,
                  style: heading(context, size: 28),
                ),
                if (settings?.description.isNotEmpty ?? false) ...[
                  const SizedBox(height: 10),
                  Text(settings!.description, textAlign: TextAlign.center, style: TextStyle(color: p.mutedForeground, height: 1.5)),
                ],
                if (config != null && config.serviceDay.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('${config.serviceDay} · ${config.serviceTime}', style: heading(context, size: 24, color: p.primary)),
                ],
                const SizedBox(height: 18),
                Text(tr('Щойно ефір почнеться, відео зʼявиться тут саме.'),
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: p.mutedForeground)),
                const SizedBox(height: 14),
                const LiveAlertsButton(),
                if (settings?.channelUrl != null) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => openExternal(context, settings!.channelUrl!),
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: Text(tr('Підписатися на канал')),
                  ),
                ],
              ]),
            ),
          ),
          if (lastService != null) ...[
            const SizedBox(height: 8),
            SectionTitle(tr('Запис останнього богослужіння')),
            VideoCard(video: lastService),
          ],
        ]),
      ),
    );
  }
}

/// Червона картка «Зараз наживо» — на головній і у відео.
class LiveNowCard extends StatelessWidget {
  const LiveNowCard({super.key, required this.status});
  final LiveStatus status;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF8E1B14),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const LiveScreen())),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 110,
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: NetImage('https://i.ytimg.com/vi/${status.videoId}/hqdefault_live.jpg', radius: 0, icon: Icons.live_tv),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  LiveBadge(label: tr('ЗАРАЗ НАЖИВО')),
                  const SizedBox(height: 6),
                  Text(status.title ?? tr('Пряма трансляція богослужіння'),
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                ]),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ]),
          ),
        ),
      );
}
