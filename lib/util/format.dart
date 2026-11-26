import 'package:intl/intl.dart';
import '../i18n.dart';

/// «42 хв», «1 год 05 хв».
String humanDuration(int seconds) {
  if (seconds <= 0) return '';
  final minutes = (seconds / 60).round();
  if (minutes < 60) return tr('{a} хв', {'a': minutes});
  final hours = minutes ~/ 60;
  return tr('{a} год {b} хв', {'a': hours, 'b': (minutes % 60).toString().padLeft(2, '0')});
}

/// «12:07» або «1:02:09» — для плеєра.
String clock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// «11 вересня 2026».
String humanDate(String iso) {
  final date = DateTime.tryParse(iso);
  if (date == null) return iso;
  return DateFormat('d MMMM y', dateLocale).format(date);
}

/// Порівняння без регістру й наголосів — для пошуку.
String fold(String text) => text
    .toLowerCase()
    .replaceAll('́', '')
    .replaceAll('ё', 'е')
    .replaceAll('ї', 'і')
    .replaceAll('’', "'")
    .replaceAll('ʼ', "'");
