import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';

import 'api/api.dart';
import 'screens/shell.dart';
import 'services/app_state.dart';
import 'services/library.dart';
import 'services/live.dart';
import 'services/live_alerts.dart';
import 'services/midi.dart';
import 'services/player.dart';
import 'services/songbook.dart';
import 'services/updater.dart';
import 'theme.dart';
import 'i18n.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Мова — першою: від неї залежать і назва каналу сповіщень, і всі тексти.
  await LangService.instance.load();
  WidgetsBinding.instance.addObserver(_LocaleWatcher());
  await JustAudioBackground.init(
    androidNotificationChannelId: 'ua.com.baptist.church.audio',
    androidNotificationChannelName: tr('Проповіді й аудіо-Біблія'),
    androidNotificationOngoing: true,
    androidNotificationIcon: 'drawable/ic_stat_audio',
  );
  for (final lang in appLangs) {
    await initializeDateFormatting(lang);
  }

  final api = Api();
  final library = LibraryService();
  await library.init();
  final player = PlayerService(library, api);
  await player.init();
  final midi = MidiService(player);
  await midi.init();
  final updater = UpdateService();
  unawaited(updater.init());
  final live = LiveService(api)..start();
  final alerts = LiveAlertsService();
  unawaited(alerts.init());
  final songbook = SongbookService(api);
  final state = AppState(api);
  state.addListener(() {
    final config = state.config;
    if (config != null) {
      live.attach(config.live);
      alerts.setEndpoint(config.live.endpoint);
    }
  });
  unawaited(state.start());
  // Інша мова — свіжі налаштування сайту цією мовою (назви, розклад, вірші).
  LangService.instance.addListener(() => unawaited(state.refresh()));

  runApp(MultiProvider(
    providers: [
      Provider<Api>.value(value: api),
      ChangeNotifierProvider<LibraryService>.value(value: library),
      ChangeNotifierProvider<PlayerService>.value(value: player),
      ChangeNotifierProvider<AppState>.value(value: state),
      ChangeNotifierProvider<LiveService>.value(value: live),
      ChangeNotifierProvider<LiveAlertsService>.value(value: alerts),
      ChangeNotifierProvider<UpdateService>.value(value: updater),
      ChangeNotifierProvider<SongbookService>.value(value: songbook),
      ChangeNotifierProvider<MidiService>.value(value: midi),
    ],
    child: const ChurchApp(),
  ));
}

/// Мова телефона змінилась — застосунок іде за нею, якщо людина не обрала свою.
class _LocaleWatcher with WidgetsBindingObserver {
  @override
  void didChangeLocales(List<Locale>? locales) => LangService.instance.systemLocaleChanged();
}

class ChurchApp extends StatelessWidget {
  const ChurchApp({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: LangService.instance,
        builder: (context, _) => _app(context, LangService.instance.lang),
      );

  Widget _app(BuildContext context, String lang) {
    final theme = context.select<LibraryService, String>((l) => l.theme);
    return MaterialApp(
      // Інша мова — дерево будується заново, і кожен tr() бере нові слова.
      key: ValueKey('app-$lang'),
      title: tr('Відродження'),
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: switch (theme) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      locale: Locale(lang),
      supportedLocales: const [Locale('uk'), Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const Shell(),
    );
  }
}
