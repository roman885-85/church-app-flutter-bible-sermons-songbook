import 'package:flutter/material.dart';

import '../theme.dart';

/// Кнопка вибору — однакова в усьому застосунку: Біблія (книга, розділ,
/// переклад), пісенник (збірник), фільтри проповідей.
///
/// Раніше про вибір підказував лише маленький трикутник біля назви — його
/// ніхто не помічав. Тепер це справжня кнопка: рамка, дрібний підпис «що це»,
/// обране значення і стрілка вниз.
class PickerButton extends StatelessWidget {
  const PickerButton({super.key, required this.caption, required this.value, required this.onPressed, this.icon, this.active = false});

  /// Що обирається: «Книга», «Розділ», «Переклад», «Збірник».
  final String caption;

  /// Що обрано зараз.
  final String value;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Вибрано фільтр (не «усі») — кнопка підсвічена.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onPressed != null;
    final button = Material(
      color: active ? p.primary.withValues(alpha: 0.12) : p.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: active ? p.primary : p.border, width: 1.2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 5, 6, 5),
            // Кнопка на всю ширину — стрілка біля правого краю; вузька — одразу за текстом.
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.hasTightWidth;
                return Row(
                  mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
                  children: [
                    if (icon != null) ...[Icon(icon, size: 20, color: p.primary), const SizedBox(width: 8)],
                    Flexible(
                      fit: wide ? FlexFit.tight : FlexFit.loose,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, height: 1.2, color: p.mutedForeground),
                          ),
                          Text(
                            value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                              color: enabled ? p.foreground : p.mutedForeground,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.expand_more_rounded, size: 24, color: enabled ? p.primary : p.mutedForeground),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    // Недоступний вибір (партію вимкнено) — блідий, щоб не кликав до себе.
    return enabled ? button : Opacity(opacity: 0.55, child: button);
  }
}
