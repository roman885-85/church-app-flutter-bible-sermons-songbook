import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/updater.dart';
import '../theme.dart';
import '../i18n.dart';

/// Перевірити оновлення і, якщо є, запропонувати його.
/// [manual] — людина сама натиснула «Перевірити»: кажемо й тоді, коли оновлень немає.
Future<void> checkForUpdate(BuildContext context, {bool manual = false}) async {
  final updater = context.read<UpdateService>();
  UpdateInfo? info;
  try {
    info = await updater.check();
  } catch (_) {
    if (manual && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Не вдалося перевірити оновлення — немає звʼязку з сайтом'))));
    }
    return;
  }
  if (!context.mounted) return;
  if (info == null) {
    if (manual) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('У вас найновіша версія {a}', {'a': updater.currentVersion}))),
      );
    }
    return;
  }
  if (!manual && !await updater.shouldOffer(info)) return;
  if (!context.mounted) return;
  await showDialog<void>(context: context, barrierDismissible: false, builder: (_) => const UpdateDialog());
}

class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final updater = context.watch<UpdateService>();
    final info = updater.available;
    final p = context.palette;
    if (info == null) return const SizedBox.shrink();

    final size = info.size != null ? tr(' · {a} МБ', {'a': (info.size! / 1048576).toStringAsFixed(1)}) : '';
    final List<Widget> actions;
    final Widget content;

    switch (updater.phase) {
      case UpdatePhase.downloading:
        content = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Завантажуємо оновлення… {a}%', {'a': (updater.progress * 100).round()})),
          const SizedBox(height: 14),
          LinearProgressIndicator(value: updater.progress > 0 ? updater.progress : null, minHeight: 6),
        ]);
        actions = [TextButton(onPressed: updater.cancel, child: Text(tr('Скасувати')))];
      case UpdatePhase.installing:
        content = Text(
          tr('Android покаже вікно встановлення — натисніть «Оновити». Уперше він попросить дозволити встановлення з цього застосунку, а Google Play Protect може запропонувати перевірку — підійде і «Перевірити», і «Встановити без перевірки».'),
        );
        actions = [
          TextButton(onPressed: updater.install, child: Text(tr('Встановити ще раз'))),
          FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('Добре'))),
        ];
      case UpdatePhase.failed:
        content = Text(updater.error ?? tr('Оновлення не вдалося'));
        actions = [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Закрити'))),
          FilledButton(onPressed: updater.install, child: Text(tr('Спробувати ще раз'))),
        ];
      case UpdatePhase.idle:
        content = ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Встановлено {a}, доступна {b}{c}', {'a': updater.currentVersion, 'b': info.version, 'c': size}),
                  style: TextStyle(color: p.mutedForeground, fontSize: 13)),
              if (info.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(info.notes, style: const TextStyle(height: 1.45)),
              ],
              if (Platform.isIOS) ...[
                const SizedBox(height: 12),
                Text(tr('На iPhone нова версія встановлюється так само, як ця: через TestFlight або App Store.')),
              ],
            ]),
          ),
        );
        actions = [
          TextButton(
            onPressed: () {
              updater.postpone(info);
              Navigator.pop(context);
            },
            child: Text(tr('Пізніше')),
          ),
          if (updater.canInstall)
            FilledButton.icon(onPressed: updater.install, icon: const Icon(Icons.system_update), label: Text(tr('Оновити'))),
        ];
    }

    return AlertDialog(
      title: Text(tr('Нова версія застосунку'), style: heading(context, size: 24)),
      content: content,
      actions: actions,
    );
  }
}
