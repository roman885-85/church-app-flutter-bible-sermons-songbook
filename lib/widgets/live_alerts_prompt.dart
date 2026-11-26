import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/live_alerts.dart';
import '../theme.dart';
import '../i18n.dart';

/// Увімкнути сповіщення про ефір і сказати людині, що вийшло.
Future<void> enableLiveAlerts(BuildContext context) => enableAlerts(context, AlertKind.live);

/// Увімкнути сповіщення потрібного виду й сказати людині, що вийшло.
Future<void> enableAlerts(BuildContext context, AlertKind kind) async {
  final alerts = context.read<LiveAlertsService>();
  final messenger = ScaffoldMessenger.of(context);
  final result = await alerts.enable(kind);
  messenger.hideCurrentSnackBar();
  switch (result) {
    case AlertsResult.enabled:
      messenger.showSnackBar(SnackBar(
        content: Text(switch (kind) {
          AlertKind.live => tr('Готово: повідомимо, щойно почнеться трансляція'),
          AlertKind.news => tr('Готово: повідомимо про нові новини, статті й фото'),
          AlertKind.videos => tr('Готово: повідомимо про нові відео'),
          AlertKind.sermons => tr('Готово: повідомимо про нові проповіді'),
        }),
      ));
    case AlertsResult.denied:
      messenger.showSnackBar(SnackBar(content: Text(tr('Без дозволу на сповіщення повідомити не вийде'))));
    case AlertsResult.blocked:
      messenger.showSnackBar(SnackBar(
        content: Text(tr('Сповіщення для застосунку вимкнені в налаштуваннях телефона')),
        action: SnackBarAction(label: tr('Налаштування'), onPressed: alerts.openSettings),
        duration: const Duration(seconds: 6),
      ));
    case AlertsResult.failed:
      messenger.showSnackBar(SnackBar(content: Text(tr('Не вдалося увімкнути сповіщення'))));
  }
}

/// Дзвіночок у заголовку розділу: увімкнути чи вимкнути сповіщення про нове в ньому.
class AlertsBell extends StatelessWidget {
  const AlertsBell({super.key, required this.kind});
  final AlertKind kind;

  @override
  Widget build(BuildContext context) {
    final alerts = context.watch<LiveAlertsService>();
    if (!alerts.supported) return const SizedBox.shrink();
    final on = alerts.isEnabled(kind);
    return IconButton(
      tooltip: on ? tr('Вимкнути сповіщення: {a}', {'a': kind.label.toLowerCase()}) : tr('Сповіщати: {a}', {'a': kind.label.toLowerCase()}),
      icon: Icon(on ? Icons.notifications_active : Icons.notifications_none, color: on ? context.palette.primary : null),
      onPressed: () async {
        if (!on) {
          await enableAlerts(context, kind);
          return;
        }
        final messenger = ScaffoldMessenger.of(context);
        await alerts.disable(kind);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(tr('Сповіщення вимкнено: {a}', {'a': kind.label.toLowerCase()}))));
      },
    );
  }
}

/// Кнопка «Сповістити, коли почнеться» — для екрана ефіру.
class LiveAlertsButton extends StatelessWidget {
  const LiveAlertsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final alerts = context.watch<LiveAlertsService>();
    final p = context.palette;
    if (!alerts.supported) return const SizedBox.shrink();
    if (alerts.enabled) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.notifications_active, size: 18, color: p.primary),
        const SizedBox(width: 8),
        Flexible(
          child: Text(tr('Повідомимо, щойно почнеться трансляція'),
              style: TextStyle(color: p.primary, fontWeight: FontWeight.w500)),
        ),
      ]);
    }
    return FilledButton.icon(
      onPressed: () => enableLiveAlerts(context),
      icon: const Icon(Icons.notifications_none),
      label: Text(tr('Сповістити, коли почнеться')),
    );
  }
}

/// Пропозиція на головній: один раз, поки людина не ввімкне або не закриє.
class LiveAlertsSuggestion extends StatelessWidget {
  const LiveAlertsSuggestion({super.key});

  @override
  Widget build(BuildContext context) {
    final alerts = context.watch<LiveAlertsService>();
    if (!alerts.supported || alerts.enabled || alerts.suggestDismissed) return const SizedBox.shrink();
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(children: [
            Icon(Icons.notifications_active_outlined, color: p.primary, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('Повідомляти про початок трансляції?'), style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(tr('Сповіщення прийде, щойно почнеться богослужіння в прямому ефірі.'),
                    style: TextStyle(fontSize: 13, color: p.mutedForeground, height: 1.35)),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                    onPressed: () => enableLiveAlerts(context),
                    child: Text(tr('Увімкнути')),
                  ),
                ),
              ]),
            ),
            IconButton(
              tooltip: tr('Не треба'),
              onPressed: alerts.dismissSuggestion,
              icon: Icon(Icons.close, color: p.mutedForeground),
            ),
          ]),
        ),
      ),
    );
  }
}
