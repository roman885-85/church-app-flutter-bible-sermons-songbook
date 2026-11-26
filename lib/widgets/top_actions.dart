import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/live_screen.dart';
import '../screens/more_screen.dart';
import '../screens/search_screen.dart';
import '../services/live.dart';
import 'common.dart';
import '../i18n.dart';

/// Верхня частина меню — як у «Слові благодаті»: унизу лишаються п'ять головних
/// розділів, а решта завжди під рукою вгорі на кожному з них: «Ефір» (коли йде
/// трансляція), пошук по всьому застосунку й повне меню.
List<Widget> topActions(BuildContext context, {List<Widget> before = const []}) => [
      const LivePill(),
      ...before,
      IconButton(
        tooltip: tr('Пошук'),
        icon: const Icon(Icons.search),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchScreen())),
      ),
      IconButton(
        tooltip: tr('Меню'),
        icon: const Icon(Icons.menu),
        onPressed: () => openMenu(context),
      ),
    ];

/// Повне меню (колишнє «Ще») — у тій самій вкладці, щоб нижня панель лишалась.
void openMenu(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MoreScreen()));

/// Червона мітка «ЕФІР» угорі, поки йде трансляція; натиск — одразу до ефіру.
class LivePill extends StatelessWidget {
  const LivePill({super.key});

  @override
  Widget build(BuildContext context) {
    final live = context.watch<LiveService>();
    if (!live.isLive) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const LiveScreen())),
        child: Center(child: LiveBadge(label: tr('ЕФІР'))),
      ),
    );
  }
}
