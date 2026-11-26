import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Кольори й шрифти сайту baptist.com.ua — світла й темна теми, переведені з
/// OKLCH сайту (app/globals.css і тема з адмінки) у звичайні кольори.
class Palette {
  const Palette({
    required this.background,
    required this.foreground,
    required this.card,
    required this.primary,
    required this.primaryForeground,
    required this.secondary,
    required this.mutedForeground,
    required this.accent,
    required this.border,
  });

  final Color background;
  final Color foreground;
  final Color card;
  final Color primary;
  final Color primaryForeground;
  final Color secondary;
  final Color mutedForeground;
  final Color accent;
  final Color border;

  static const light = Palette(
    background: Color(0xFFF9F4EC),
    foreground: Color(0xFF2F241E),
    card: Color(0xFFFDFAF4),
    primary: Color(0xFF6D402C),
    primaryForeground: Color(0xFFFDF8F0),
    secondary: Color(0xFFECE3D6),
    mutedForeground: Color(0xFF6F6056),
    accent: Color(0xFFCC8F5C),
    border: Color(0xFFDFD6C9),
  );

  static const dark = Palette(
    background: Color(0xFF0E0804),
    foreground: Color(0xFFF1EAE0),
    card: Color(0xFF17100B),
    primary: Color(0xFFD0975F),
    primaryForeground: Color(0xFF110904),
    secondary: Color(0xFF211912),
    mutedForeground: Color(0xFF918377),
    accent: Color(0xFF8A542D),
    border: Color(0x1FFFFFFF),
  );
}

extension PaletteOf on BuildContext {
  Palette get palette => Theme.of(this).brightness == Brightness.dark ? Palette.dark : Palette.light;
}

/// Заголовки — Cormorant Garamond, текст — Jost, як на сайті.
TextStyle heading(BuildContext context, {double size = 24, FontWeight weight = FontWeight.w600, Color? color}) =>
    GoogleFonts.cormorantGaramond(fontSize: size, fontWeight: weight, height: 1.15, color: color ?? context.palette.foreground);

ThemeData buildTheme(Brightness brightness) {
  final p = brightness == Brightness.dark ? Palette.dark : Palette.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.primary,
    onPrimary: p.primaryForeground,
    secondary: p.accent,
    onSecondary: p.primaryForeground,
    error: const Color(0xFFB3261E),
    onError: Colors.white,
    surface: p.background,
    onSurface: p.foreground,
    surfaceContainerLowest: p.card,
    surfaceContainerLow: p.card,
    surfaceContainer: p.card,
    surfaceContainerHigh: p.secondary,
    surfaceContainerHighest: p.secondary,
    onSurfaceVariant: p.mutedForeground,
    outline: p.border,
    outlineVariant: p.border,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: p.background);
  final text = GoogleFonts.jostTextTheme(base.textTheme).apply(bodyColor: p.foreground, displayColor: p.foreground);
  return base.copyWith(
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.foreground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      // Коли вміст пропливає під закріпленою шапкою — тонка тінь, щоб шапку було
      // видно окремо, а не як частину сторінки.
      scrolledUnderElevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      centerTitle: false,
      titleTextStyle: GoogleFonts.cormorantGaramond(fontSize: 26, fontWeight: FontWeight.w600, color: p.foreground),
    ),
    cardTheme: CardThemeData(
      color: p.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.border)),
    ),
    dividerTheme: DividerThemeData(color: p.border, space: 1),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: p.primary.withValues(alpha: 0.16),
      labelTextStyle: WidgetStatePropertyAll(GoogleFonts.jost(fontSize: 12, fontWeight: FontWeight.w500, color: p.foreground)),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(color: states.contains(WidgetState.selected) ? p.primary : p.mutedForeground),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.card,
      selectedColor: p.primary.withValues(alpha: 0.18),
      side: BorderSide(color: p.border),
      labelStyle: GoogleFonts.jost(fontSize: 13, color: p.foreground),
      shape: const StadiumBorder(),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.primary,
        foregroundColor: p.primaryForeground,
        shape: const StadiumBorder(),
        textStyle: GoogleFonts.jost(fontWeight: FontWeight.w500),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.foreground,
        side: BorderSide(color: p.border),
        shape: const StadiumBorder(),
        textStyle: GoogleFonts.jost(fontWeight: FontWeight.w500),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: p.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: p.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: p.primary)),
      hintStyle: GoogleFonts.jost(color: p.mutedForeground),
    ),
    // Вимкнений перемикач у кремовій темі зливався з тлом — повзунок і рамка темніші.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) || states.contains(WidgetState.disabled) ? null : p.mutedForeground,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) || states.contains(WidgetState.disabled) ? null : p.mutedForeground.withValues(alpha: 0.75),
      ),
    ),
    sliderTheme: SliderThemeData(activeTrackColor: p.primary, thumbColor: p.primary, inactiveTrackColor: p.secondary),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.primary),
    listTileTheme: ListTileThemeData(iconColor: p.mutedForeground, textColor: p.foreground),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: p.foreground, contentTextStyle: GoogleFonts.jost(color: p.background)),
  );
}
