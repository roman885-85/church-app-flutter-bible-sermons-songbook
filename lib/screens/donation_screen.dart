import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../services/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../i18n.dart';

/// Пожертвування — ті самі реквізити, що на сайті. Оплата — на сторінці сайту
/// або в Приват24: застосунок платежів не приймає і даних картки не бачить.
class DonationScreen extends StatelessWidget {
  const DonationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppState>().config;
    final p = context.palette;
    if (config == null) {
      return Scaffold(appBar: AppBar(title: Text(tr('Пожертвування'))), body: const LoadingView());
    }
    final d = config.donation;

    return Scaffold(
      appBar: AppBar(title: Text(tr('Пожертвування'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(tr('Підтримати служіння'), style: heading(context, size: 30)),
        const SizedBox(height: 8),
        Text(
          tr('Ваші пожертви допомагають церкві нести Добру звістку, підтримувати служіння й тих, хто потребує допомоги. Дякуємо!'),
          style: TextStyle(color: p.mutedForeground, height: 1.5),
        ),
        const SizedBox(height: 20),
        if (d.qrUrl != null)
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: () => openExternal(context, d.qrUrl!),
            icon: const Icon(Icons.volunteer_activism_outlined),
            label: Text(d.qrLabel ?? tr('Пожертвувати через Приват24')),
          ),
        if (d.onlinePayment && d.pageUrl.isNotEmpty) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: () => openExternal(context, d.pageUrl),
            icon: const Icon(Icons.credit_card),
            label: Text(tr('Оплатити карткою на сайті')),
          ),
        ],
        const SizedBox(height: 24),
        if (d.cardNumber != null)
          _Requisites(title: tr('Картка'), rows: [
            (tr('Номер картки'), _groupCard(d.cardNumber!), d.cardNumber!),
            if (d.cardHolder != null) (tr('Отримувач'), d.cardHolder!, d.cardHolder!),
          ]),
        const SizedBox(height: 14),
        _Requisites(title: tr('Банківський переказ'), rows: _bank(d)),
      ]),
    );
  }

  static List<(String, String, String)> _bank(Donation d) => [
        if (d.recipient.isNotEmpty) (tr('Отримувач'), d.recipient, d.recipient),
        if (d.edrpou.isNotEmpty) (tr('ЄДРПОУ'), d.edrpou, d.edrpou),
        if (d.iban.isNotEmpty) ('IBAN', d.iban, d.iban.replaceAll(' ', '')),
        if (d.bank.isNotEmpty) (tr('Банк'), d.bank, d.bank),
        if (d.purpose.isNotEmpty) (tr('Призначення платежу'), d.purpose, d.purpose),
      ];

  static String _groupCard(String n) {
    final digits = n.replaceAll(RegExp(r'\D'), '');
    return [for (var i = 0; i < digits.length; i += 4) digits.substring(i, (i + 4).clamp(0, digits.length))].join(' ');
  }
}

class _Requisites extends StatelessWidget {
  const _Requisites({required this.title, required this.rows});
  final String title;
  final List<(String, String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (rows.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: heading(context, size: 22)),
          const SizedBox(height: 6),
          for (final (label, shown, copy) in rows)
            Row(children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, style: TextStyle(fontSize: 12, color: p.mutedForeground)),
                    SelectableText(shown, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500)),
                  ]),
                ),
              ),
              IconButton(
                tooltip: tr('Скопіювати'),
                icon: const Icon(Icons.copy, size: 20),
                onPressed: () => copyText(context, copy, done: tr('{a} скопійовано', {'a': label})),
              ),
            ]),
        ]),
      ),
    );
  }
}
