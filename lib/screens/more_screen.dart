import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/library.dart';
import '../services/live.dart';
import '../services/live_alerts.dart';
import '../services/updater.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/live_alerts_prompt.dart';
import '../widgets/update_prompt.dart';
import 'contacts_screen.dart';
import 'donation_screen.dart';
import 'library_screen.dart';
import 'live_screen.dart';
import 'news_screen.dart';
import 'notes_screen.dart';
import '../i18n.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final config = context.watch<AppState>().config;
    final library = context.watch<LibraryService>();
    final live = context.watch<LiveService>();
    final updater = context.watch<UpdateService>();
    final alerts = context.watch<LiveAlertsService>();

    void push(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

    return Scaffold(
      appBar: AppBar(title: Text(tr('Меню'))),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Row(children: [
            NetImage(config?.logo, width: 56, height: 56, radius: 28, fit: BoxFit.contain, icon: Icons.church_outlined),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(config?.name ?? tr('Церква «Відродження»'), style: heading(context, size: 22)),
                if (config != null && config.serviceDay.isNotEmpty)
                  Text(tr('Богослужіння: {a}, {b}', {'a': config.serviceDay.toLowerCase(), 'b': config.serviceTime}),
                      style: TextStyle(color: p.mutedForeground, fontSize: 13)),
              ]),
            ),
          ]),
        ),
        _Group(children: [
          ListTile(
            leading: Icon(Icons.live_tv_outlined, color: live.isLive ? const Color(0xFFD93025) : null),
            title: Text(tr('Прямий ефір')),
            trailing: live.isLive ? const LiveBadge() : const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const LiveScreen())),
          ),

          ListTile(
            leading: const Icon(Icons.queue_music_outlined),
            title: Text(tr('Ноти')),
            subtitle: Text(tr('Гімни з відкритих джерел: сторінки, запис, PDF')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => push(const NotesScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: Text(tr('Новини та статті')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => push(const NewsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(tr('Фото')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => push(const NewsScreen(initialTab: 2)),
          ),
          ListTile(
            leading: const Icon(Icons.volunteer_activism_outlined),
            title: Text(tr('Пожертвування')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => push(const DonationScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: Text(tr('Контакти й розклад')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => push(const ContactsScreen()),
          ),
        ]),
        // Чотири перемикачі сповіщень із поясненнями — на окремому екрані: при великому шрифті телефона вони
        // займали півтора екрана меню (власник 21.11.2026: «оптимизируй меню, если нужно»). Тут — один рядок
        // зі станом, щоб було видно, що ввімкнено, і куди натиснути.
        if (alerts.supported)
          _Group(title: tr('Сповіщення'), children: [
            Builder(builder: (context) {
              final kinds = [
                if (config?.live.enabled ?? true) AlertKind.live,
                AlertKind.news,
                AlertKind.videos,
                AlertKind.sermons,
              ];
              final on = kinds.where(alerts.isEnabled).length;
              return ListTile(
                leading: Icon(on > 0 ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
                    color: on > 0 ? context.palette.primary : null),
                title: Text(tr('Налаштувати сповіщення')),
                subtitle: Text(on == 0 ? tr('Усі вимкнено') : tr('Увімкнено: {a} з {b}', {'a': on, 'b': kinds.length})),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => push(const NotificationsScreen()),
              );
            }),
          ]),
        _Group(title: tr('Моя фонотека'), children: [
          ListTile(
            leading: const Icon(Icons.favorite_border),
            title: Text(tr('Обране')),
            trailing: Text('${library.favorites.length}', style: TextStyle(color: p.mutedForeground)),
            onTap: () => push(const LibraryScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: Text(tr('Збережене на телефоні')),
            trailing: Text('${library.downloads.length}', style: TextStyle(color: p.mutedForeground)),
            onTap: () => push(const LibraryScreen(initialTab: 1)),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(tr('Історія прослуховування')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => push(const LibraryScreen(initialTab: 2)),
          ),
        ]),
        _Group(title: tr('Оформлення'), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'system', label: Text(tr('Авто')), icon: Icon(Icons.brightness_auto_outlined)),
                ButtonSegment(value: 'light', label: Text(tr('Світла')), icon: Icon(Icons.light_mode_outlined)),
                ButtonSegment(value: 'dark', label: Text(tr('Темна')), icon: Icon(Icons.dark_mode_outlined)),
              ],
              selected: {library.theme},
              onSelectionChanged: (v) => library.setTheme(v.first),
            ),
          ),
        ]),
        // Мова — окремим рядком і двома мовами в назві: хто випадково обрав
        // незнайому, знайде, як повернути.
        _Group(title: LangService.instance.lang == 'en' ? 'Language' : '${tr('Мова')} · Language', children: [
          ListTile(
            leading: const Icon(Icons.translate),
            title: Text(LangService.instance.choice == null
                ? '${tr('Як у телефоні')} (${appLangNames[LangService.instance.lang]})'
                : appLangNames[LangService.instance.lang]!),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _chooseLanguage(context),
          ),
        ]),
        _Group(title: tr('Застосунок'), children: [
          ListTile(
            leading: const Icon(Icons.system_update_outlined),
            title: Text(tr('Перевірити оновлення')),
            subtitle: Text(updater.available != null
                ? tr('Доступна версія {a}', {'a': updater.available!.version})
                : tr('Версія {a}', {'a': updater.currentVersion.isEmpty ? '—' : updater.currentVersion})),
            trailing: updater.available != null ? Icon(Icons.fiber_new, color: p.primary) : null,
            onTap: () => checkForUpdate(context, manual: true),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: Text(tr('Відкритий код на GitHub')),
            subtitle: const Text(UpdateService.repo),
            onTap: () => openExternal(context, 'https://github.com/${UpdateService.repo}'),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(tr('Ліцензії відкритого коду')),
            onTap: () => showLicensePage(
              context: context,
              applicationName: tr('Відродження'),
              applicationVersion: updater.currentVersion,
            ),
          ),
          if (config != null)
            ListTile(
              leading: const Icon(Icons.language),
              title: Text(tr('Сайт церкви')),
              subtitle: Text(config.siteUrl.replaceFirst(RegExp(r'^https?://'), '')),
              onTap: () => openExternal(context, config.siteUrl),
            ),
        ]),
      ]),
    );
  }
}

class _AlertSwitch extends StatelessWidget {
  const _AlertSwitch({required this.kind, required this.icon, required this.title, required this.subtitle});

  final AlertKind kind;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final alerts = context.watch<LiveAlertsService>();
    final on = alerts.isEnabled(kind);
    return SwitchListTile(
      secondary: Icon(icon, color: on ? context.palette.primary : null),
      title: Text(title),
      subtitle: Text(subtitle),
      value: on,
      onChanged: (value) => value ? enableAlerts(context, kind) : alerts.disable(kind),
    );
  }
}

/// Сповіщення на телефон — перемикачі, що раніше стояли просто в меню.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppState>().config;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Сповіщення'))),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        _Group(children: [
          if (config?.live.enabled ?? true)
            _AlertSwitch(
              kind: AlertKind.live,
              icon: Icons.live_tv_outlined,
              title: tr('Початок прямої трансляції'),
              subtitle: config != null && config.serviceDay.isNotEmpty
                  ? tr('Богослужіння: {a}, {b}', {'a': config.serviceDay.toLowerCase(), 'b': config.serviceTime})
                  : tr('Щойно почнеться ефір'),
            ),
          _AlertSwitch(
            kind: AlertKind.news,
            icon: Icons.article_outlined,
            title: tr('Нові новини, статті й фото'),
            subtitle: tr('Коли на сайті зʼявиться публікація'),
          ),
          _AlertSwitch(
            kind: AlertKind.videos,
            icon: Icons.smart_display_outlined,
            title: tr('Нові відео'),
            subtitle: tr('Коли на каналі YouTube зʼявиться відео'),
          ),
          _AlertSwitch(
            kind: AlertKind.sermons,
            icon: Icons.headphones_outlined,
            title: tr('Нові проповіді (аудіо)'),
            subtitle: tr('Коли у фонотеці зʼявиться запис'),
          ),
                  ]),
      ]),
    );
  }
}

Future<void> _chooseLanguage(BuildContext context) async {
  final p = context.palette;
  final lang = LangService.instance;
  // null — як у телефоні; порожній рядок — нічого не вибрали (закрили аркуш).
  final chosen = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(lang.lang == 'en' ? 'Language' : '${tr('Мова')} · Language', style: heading(context, size: 24)),
        ),
        for (final code in ['', ...appLangs])
          ListTile(
            leading: Icon(
              (code.isEmpty ? lang.choice == null : lang.choice == code) ? Icons.radio_button_checked : Icons.radio_button_off,
              color: (code.isEmpty ? lang.choice == null : lang.choice == code) ? p.primary : null,
            ),
            title: Text(code.isEmpty ? tr('Як у телефоні') : appLangNames[code]!),
            onTap: () => Navigator.pop(context, code.isEmpty ? 'system' : code),
          ),
      ]),
    ),
  );
  if (chosen == null) return;
  await lang.setChoice(chosen == 'system' ? null : chosen);
}

class _Group extends StatelessWidget {
  const _Group({this.title, required this.children});
  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Text(title!.toUpperCase(),
                  style: TextStyle(fontSize: 11, letterSpacing: 1.8, color: context.palette.accent, fontWeight: FontWeight.w600)),
            ),
          Card(child: Column(children: children)),
        ]),
      );
}
