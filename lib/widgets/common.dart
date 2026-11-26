import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import '../i18n.dart';

/// Картинка з сайту: з кешем на телефоні й спокійною заглушкою замість помилки.
class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.width, this.height, this.fit = BoxFit.cover, this.radius = 12, this.icon = Icons.image_outlined});

  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double radius;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final placeholder = Container(
      width: width,
      height: height,
      color: p.secondary,
      alignment: Alignment.center,
      child: Icon(icon, color: p.mutedForeground, size: (height ?? 48) > 80 ? 36 : 22),
    );
    final value = url?.trim() ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: value.isEmpty
          ? placeholder
          : CachedNetworkImage(
              imageUrl: value,
              width: width,
              height: height,
              fit: fit,
              fadeInDuration: const Duration(milliseconds: 200),
              placeholder: (_, _) => placeholder,
              errorWidget: (_, _, _) => placeholder,
            ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});
  final String? label;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(strokeWidth: 2.5),
            if (label != null) ...[
              const SizedBox(height: 16),
              Text(label!, style: TextStyle(color: context.palette.mutedForeground)),
            ],
          ]),
        ),
      );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off_outlined, size: 44, color: context.palette.mutedForeground),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: context.palette.mutedForeground, height: 1.4)),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text(tr('Спробувати ще раз'))),
            ],
          ]),
        ),
      );
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 44, color: context.palette.mutedForeground),
            const SizedBox(height: 14),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: context.palette.mutedForeground, height: 1.4)),
          ]),
        ),
      );
}

/// Заголовок розділу на кшталт сайту: дрібний надпис над великою назвою.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.eyebrow, this.onMore, this.moreLabel});

  final String title;
  final String? eyebrow;
  final VoidCallback? onMore;
  final String? moreLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 12, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (eyebrow != null)
              Text(eyebrow!.toUpperCase(),
                  style: TextStyle(fontSize: 11, letterSpacing: 2.2, color: p.accent, fontWeight: FontWeight.w600)),
            Text(title, style: heading(context, size: 28)),
          ]),
        ),
        if (onMore != null)
          TextButton(
            onPressed: onMore,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(moreLabel ?? tr('Усі'), style: TextStyle(color: p.primary)),
              Icon(Icons.chevron_right, size: 18, color: p.primary),
            ]),
          ),
      ]),
    );
  }
}

void showSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));
}

/// Відкрити адресу поза застосунком: YouTube, карти, дзвінок, пошта, браузер.
Future<void> openExternal(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  var ok = false;
  if (uri != null) {
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
  }
  if (!ok && context.mounted) showSnack(context, tr('Не вдалося відкрити посилання'));
}

Future<void> copyText(BuildContext context, String text, {String? done}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showSnack(context, done ?? tr('Скопійовано'));
}

/// Мітка «НАЖИВО» з пульсуючою крапкою.
class LiveBadge extends StatefulWidget {
  const LiveBadge({super.key, this.label});
  final String? label;

  @override
  State<LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<LiveBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: const Color(0xFFD93025), borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          FadeTransition(
            opacity: Tween(begin: 0.35, end: 1.0).animate(_pulse),
            child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
          ),
          const SizedBox(width: 6),
          Text(widget.label ?? tr('НАЖИВО'),
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        ]),
      );
}
