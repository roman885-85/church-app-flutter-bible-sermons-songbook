import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../i18n.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppState>().config;
    final p = context.palette;
    if (config == null) {
      return Scaffold(appBar: AppBar(title: Text(tr('Контакти'))), body: const LoadingView());
    }
    final phoneHref = 'tel:${config.phone.replaceAll(RegExp(r'[^\d+]'), '')}';

    return Scaffold(
      appBar: AppBar(title: Text(tr('Контакти'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('БОГОСЛУЖІННЯ'), style: TextStyle(fontSize: 11, letterSpacing: 2, color: p.accent, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('${config.serviceDay}, ${config.serviceTime}', style: heading(context, size: 30)),
              if (config.serviceNote.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(config.serviceNote, style: TextStyle(color: p.mutedForeground, height: 1.45)),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Column(children: [
            if (config.address.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.place_outlined),
                title: Text(config.address),
                subtitle: Text(tr('Прокласти маршрут')),
                onTap: config.mapsUrl.isEmpty ? null : () => openExternal(context, config.mapsUrl),
              ),
            if (config.phone.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.phone_outlined),
                title: Text(config.phone),
                subtitle: Text(tr('Подзвонити')),
                onTap: () => openExternal(context, phoneHref),
                trailing: IconButton(icon: const Icon(Icons.copy, size: 20), onPressed: () => copyText(context, config.phone)),
              ),
            if (config.email.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.mail_outline),
                title: Text(config.email),
                subtitle: Text(tr('Написати листа')),
                onTap: () => openExternal(context, 'mailto:${config.email}'),
                trailing: IconButton(icon: const Icon(Icons.copy, size: 20), onPressed: () => copyText(context, config.email)),
              ),
            ListTile(
              leading: const Icon(Icons.language),
              title: Text(config.siteUrl.replaceFirst(RegExp(r'^https?://'), '')),
              subtitle: Text(tr('Сайт церкви')),
              onTap: () => openExternal(context, config.siteUrl),
            ),
          ]),
        ),
      ]),
    );
  }
}
