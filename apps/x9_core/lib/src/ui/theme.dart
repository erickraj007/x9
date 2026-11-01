import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../session.dart';

/// X9 brand tokens (see the X9 brand spec). These are the colours that do NOT change between light
/// and dark, so they are `const` and safe to use anywhere (const widgets, default parameters).
///
/// Everything that depends on the theme (backgrounds, text, borders, tinted surfaces) lives in
/// [X9Palette], read with `context.x9`.
class X9Colors {
  X9Colors._();

  // Brand
  static const primary = Color(0xFFE61C24);
  static const primaryDark = Color(0xFFB8141A);
  static const primaryLight = Color(0xFFFFEBEC);
  static const onPrimary = Color(0xFFFFFFFF);

  // Status: feedback only, always paired with an icon or a text label.
  static const success = Color(0xFF34C759);
  static const warning = Color(0xFFFF9500);
  static const error = Color(0xFFFF3B30);
  static const info = Color(0xFF007AFF);

  // Light neutrals (default theme)
  static const lightBackground = Color(0xFFFFFFFF);
  static const lightSurface = Color(0xFFF8F9FA);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightText = Color(0xFF121212);
  static const lightTextMuted = Color(0xFF8E8E93);
  static const lightTextSecondary = Color(0xFF5F5F66);
  static const lightBorder = Color(0xFFE5E5EA);

  // Dark neutrals
  static const darkBackground = Color(0xFF0A0909);
  static const darkSurface = Color(0xFF151414);
  static const darkCard = Color(0xFF1C1B1B);
  static const darkText = Color(0xFFFFFFFF);
  static const darkTextMuted = Color(0xFFA0A0A0);
  static const darkTextSecondary = Color(0xFFB5B5BA);
  static const darkBorder = Color(0xFF2C2C2E);

  // Category chips
  static const categoryBackground = Color(0xFFFFF0F0);
  static const categoryBorder = Color(0xFFFFE2E2);
  static const darkCategoryBackground = Color(0x24E61C24); // rgba(230,28,36,.14)
  static const darkCategoryBorder = Color(0x59E61C24); // rgba(230,28,36,.35)
  static const darkCategoryText = Color(0xFFFF8A8F);
  static const darkPrimarySoft = Color(0x29E61C24); // rgba(230,28,36,.16)

  /// Full-red hero / banner gradient (primary to primary-dark). Always used with white text on top.
  static const heroGradient = LinearGradient(
    colors: [primary, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Theme-dependent X9 tokens, installed as a [ThemeExtension] by [x9Theme].
/// Read with `context.x9` (or `Theme.of(context).extension<X9Palette>()`).
@immutable
class X9Palette extends ThemeExtension<X9Palette> {
  const X9Palette({
    required this.background,
    required this.surface,
    required this.card,
    required this.text,
    required this.textMuted,
    required this.textSecondary,
    required this.border,
    required this.categoryBackground,
    required this.categoryBorder,
    required this.categoryText,
    required this.primarySoft,
    required this.onPrimarySoft,
    required this.isDark,
  });

  final Color background;
  final Color surface;
  final Color card;

  /// Main text colour.
  final Color text;

  /// #8E8E93 / #A0A0A0: decoration and disabled only. Text people must read uses [textSecondary].
  final Color textMuted;

  /// Readable secondary text (captions, labels, hints).
  final Color textSecondary;
  final Color border;
  final Color categoryBackground;
  final Color categoryBorder;

  /// Text colour on category chips (primary-dark in light mode).
  final Color categoryText;

  /// Light-red tinted surface (primary-light in light mode, translucent red in dark mode).
  final Color primarySoft;

  /// Text / icon colour on [primarySoft] (primary-dark in light mode).
  final Color onPrimarySoft;
  final bool isDark;

  // Brand + status (identical in both themes), exposed here so call sites need one accessor.
  Color get primary => X9Colors.primary;
  Color get primaryDark => X9Colors.primaryDark;
  Color get success => X9Colors.success;
  Color get warning => X9Colors.warning;
  Color get error => X9Colors.error;
  Color get info => X9Colors.info;

  /// Tinted background for a status / accent colour (use with an icon or label).
  Color tint(Color c, [double alpha = 0.12]) => c.withValues(alpha: alpha);

  /// A status colour made legible as *text* on the current background (blended toward [text]).
  Color statusText(Color c) => Color.lerp(c, text, 0.35)!;

  /// Soft card shadow (none in dark mode).
  Color get shadow => isDark ? const Color(0x00000000) : const Color(0x14000000);

  static const light = X9Palette(
    background: X9Colors.lightBackground,
    surface: X9Colors.lightSurface,
    card: X9Colors.lightCard,
    text: X9Colors.lightText,
    textMuted: X9Colors.lightTextMuted,
    textSecondary: X9Colors.lightTextSecondary,
    border: X9Colors.lightBorder,
    categoryBackground: X9Colors.categoryBackground,
    categoryBorder: X9Colors.categoryBorder,
    categoryText: X9Colors.primaryDark,
    primarySoft: X9Colors.primaryLight,
    onPrimarySoft: X9Colors.primaryDark,
    isDark: false,
  );

  static const dark = X9Palette(
    background: X9Colors.darkBackground,
    surface: X9Colors.darkSurface,
    card: X9Colors.darkCard,
    text: X9Colors.darkText,
    textMuted: X9Colors.darkTextMuted,
    textSecondary: X9Colors.darkTextSecondary,
    border: X9Colors.darkBorder,
    categoryBackground: X9Colors.darkCategoryBackground,
    categoryBorder: X9Colors.darkCategoryBorder,
    categoryText: X9Colors.darkCategoryText,
    primarySoft: X9Colors.darkPrimarySoft,
    onPrimarySoft: X9Colors.darkCategoryText,
    isDark: true,
  );

  @override
  X9Palette copyWith({
    Color? background,
    Color? surface,
    Color? card,
    Color? text,
    Color? textMuted,
    Color? textSecondary,
    Color? border,
    Color? categoryBackground,
    Color? categoryBorder,
    Color? categoryText,
    Color? primarySoft,
    Color? onPrimarySoft,
    bool? isDark,
  }) =>
      X9Palette(
        background: background ?? this.background,
        surface: surface ?? this.surface,
        card: card ?? this.card,
        text: text ?? this.text,
        textMuted: textMuted ?? this.textMuted,
        textSecondary: textSecondary ?? this.textSecondary,
        border: border ?? this.border,
        categoryBackground: categoryBackground ?? this.categoryBackground,
        categoryBorder: categoryBorder ?? this.categoryBorder,
        categoryText: categoryText ?? this.categoryText,
        primarySoft: primarySoft ?? this.primarySoft,
        onPrimarySoft: onPrimarySoft ?? this.onPrimarySoft,
        isDark: isDark ?? this.isDark,
      );

  @override
  X9Palette lerp(ThemeExtension<X9Palette>? other, double t) {
    if (other is! X9Palette) return this;
    return X9Palette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      card: Color.lerp(card, other.card, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      border: Color.lerp(border, other.border, t)!,
      categoryBackground: Color.lerp(categoryBackground, other.categoryBackground, t)!,
      categoryBorder: Color.lerp(categoryBorder, other.categoryBorder, t)!,
      categoryText: Color.lerp(categoryText, other.categoryText, t)!,
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
      onPrimarySoft: Color.lerp(onPrimarySoft, other.onPrimarySoft, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

/// `context.x9.textSecondary`, `context.x9.border`, ...
extension X9ThemeContext on BuildContext {
  X9Palette get x9 {
    final t = Theme.of(this);
    return t.extension<X9Palette>() ?? (t.brightness == Brightness.dark ? X9Palette.dark : X9Palette.light);
  }
}

/// Typography helpers. Inter is not bundled, so the platform font (Roboto) is used with the spec's
/// weights: headings 500-600, body 400, -0.01em on large headings, tabular numbers for money.
class X9Text {
  X9Text._();

  /// Tabular (fixed-width) figures. Use for money: `style.copyWith(fontFeatures: X9Text.tabular)`.
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  /// Small uppercase red eyebrow label ("EVERYDAY EXPERIENCES. VIP BENEFITS.").
  /// Pass the text through `.toUpperCase()` or use the [Eyebrow] widget.
  static const TextStyle eyebrow = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.96, // .08em at 12px
    color: X9Colors.primary,
  );

  /// Money text style: theme title style with tabular figures.
  static TextStyle money(BuildContext context, {double? size, FontWeight weight = FontWeight.w600, Color? color}) {
    final b = Theme.of(context).textTheme.titleMedium ?? const TextStyle();
    return b.copyWith(fontSize: size, fontWeight: weight, color: color, fontFeatures: tabular);
  }
}

/// Red uppercase eyebrow label.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color, this.textAlign});
  final String text;
  final Color? color;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        textAlign: textAlign,
        style: color == null ? X9Text.eyebrow : X9Text.eyebrow.copyWith(color: color),
      );
}

/// Light-red tinted pill for categories ("Food", "VIP: 10% off"): #FFF0F0 bg, #FFE2E2 border,
/// primary-dark text (translucent red in dark mode).
class X9ChipBadge extends StatelessWidget {
  const X9ChipBadge(this.label, {super.key, this.icon, this.fontSize = 12});
  final String label;
  final IconData? icon;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final p = context.x9;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: p.categoryBackground,
        border: Border.all(color: p.categoryBorder),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: fontSize + 2, color: p.categoryText), const SizedBox(width: 4)],
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.categoryText, fontSize: fontSize, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

/// Light / Dark / System choice, persisted through [SessionStore] (same store as the app lock
/// settings; it survives sign-out). Defaults to LIGHT.
class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  static const _key = 'theme_mode';

  ThemeMode _mode = ThemeMode.light;
  ThemeMode get mode => _mode;

  /// Reads the saved choice. Call once in main() before runApp (safe to fail: stays light).
  Future<void> load() async {
    try {
      final v = await SessionStore.instance.read(_key);
      final m = v == 'dark'
          ? ThemeMode.dark
          : v == 'system'
              ? ThemeMode.system
              : ThemeMode.light;
      if (m != _mode) {
        _mode = m;
        notifyListeners();
      }
    } catch (_) {
      // Secure storage unreadable: keep the default (light).
    }
  }

  Future<void> setMode(ThemeMode m) async {
    if (m == _mode) return;
    _mode = m;
    notifyListeners();
    try {
      await SessionStore.instance.write(_key, m == ThemeMode.dark ? 'dark' : m == ThemeMode.system ? 'system' : 'light');
    } catch (_) {}
  }

  static String label(ThemeMode m) => m == ThemeMode.dark ? 'Dark' : m == ThemeMode.system ? 'System' : 'Light';
}

/// Light / Dark / System selector for profile / security screens. Rebuilds when the mode changes.
class ThemeModeSelector extends StatelessWidget {
  const ThemeModeSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final c = ThemeController.instance;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.palette_outlined, color: context.x9.textSecondary),
              const SizedBox(width: 12),
              Text('Appearance', style: Theme.of(context).textTheme.titleSmall),
            ]),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Dark')),
                  ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined), label: Text('System')),
                ],
                selected: {c.mode},
                onSelectionChanged: (s) => c.setMode(s.first),
              ),
            ),
          ]),
        );
      },
    );
  }
}

TextTheme _textTheme(Brightness brightness, Color text) {
  final base = ThemeData(useMaterial3: true, brightness: brightness).textTheme.apply(bodyColor: text, displayColor: text);
  TextStyle? s(TextStyle? t, FontWeight w, {bool tight = false}) =>
      t?.copyWith(fontWeight: w, letterSpacing: tight ? -0.01 * (t.fontSize ?? 14) : t.letterSpacing);
  return base.copyWith(
    displayLarge: s(base.displayLarge, FontWeight.w500, tight: true),
    displayMedium: s(base.displayMedium, FontWeight.w500, tight: true),
    displaySmall: s(base.displaySmall, FontWeight.w500, tight: true),
    headlineLarge: s(base.headlineLarge, FontWeight.w600, tight: true),
    headlineMedium: s(base.headlineMedium, FontWeight.w600, tight: true),
    headlineSmall: s(base.headlineSmall, FontWeight.w600, tight: true),
    titleLarge: s(base.titleLarge, FontWeight.w600, tight: true),
    titleMedium: s(base.titleMedium, FontWeight.w600),
    titleSmall: s(base.titleSmall, FontWeight.w500),
    bodyLarge: s(base.bodyLarge, FontWeight.w400),
    bodyMedium: s(base.bodyMedium, FontWeight.w400),
    bodySmall: s(base.bodySmall, FontWeight.w400),
    labelLarge: s(base.labelLarge, FontWeight.w600),
    labelMedium: s(base.labelMedium, FontWeight.w500),
    labelSmall: s(base.labelSmall, FontWeight.w500),
  );
}

/// Light theme (the default).
ThemeData x9LightTheme() => x9Theme(brightness: Brightness.light);

/// Dark theme.
ThemeData x9DarkTheme() => x9Theme(brightness: Brightness.dark);

ThemeData x9Theme({Brightness brightness = Brightness.light}) {
  final dark = brightness == Brightness.dark;
  final p = dark ? X9Palette.dark : X9Palette.light;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: X9Colors.primary,
    onPrimary: X9Colors.onPrimary,
    primaryContainer: p.primarySoft,
    onPrimaryContainer: p.onPrimarySoft,
    secondary: dark ? X9Colors.darkCategoryText : X9Colors.primaryDark,
    onSecondary: dark ? X9Colors.darkBackground : X9Colors.onPrimary,
    secondaryContainer: p.primarySoft,
    onSecondaryContainer: p.onPrimarySoft,
    tertiary: X9Colors.info,
    onTertiary: X9Colors.onPrimary,
    tertiaryContainer: X9Colors.info.withValues(alpha: 0.12),
    onTertiaryContainer: p.text,
    error: X9Colors.error,
    onError: X9Colors.onPrimary,
    errorContainer: X9Colors.error.withValues(alpha: 0.12),
    onErrorContainer: p.text,
    surface: p.background,
    onSurface: p.text,
    onSurfaceVariant: p.textSecondary,
    surfaceDim: p.background,
    surfaceBright: p.background,
    surfaceContainerLowest: p.card,
    surfaceContainerLow: p.card,
    surfaceContainer: p.card,
    surfaceContainerHigh: p.card,
    surfaceContainerHighest: p.surface,
    outline: p.border,
    outlineVariant: p.border,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: dark ? const Color(0xFFF2F2F7) : X9Colors.lightText,
    onInverseSurface: dark ? X9Colors.lightText : X9Colors.onPrimary,
    inversePrimary: dark ? X9Colors.primary : X9Colors.darkCategoryText,
    surfaceTint: Colors.transparent,
  );

  final textTheme = _textTheme(brightness, p.text);
  const pill = StadiumBorder();
  final cardShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: p.border));
  final accentText = dark ? X9Colors.darkCategoryText : X9Colors.primary;

  // Pressed / hovered primary buttons go to primary-dark.
  final filledBg = WidgetStateProperty.resolveWith<Color?>((states) {
    if (states.contains(WidgetState.disabled)) return p.border;
    if (states.contains(WidgetState.pressed) || states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) return X9Colors.primaryDark;
    return X9Colors.primary;
  });
  final filledFg = WidgetStateProperty.resolveWith<Color?>((states) => states.contains(WidgetState.disabled) ? p.textMuted : X9Colors.onPrimary);

  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
  return base.copyWith(
    extensions: <ThemeExtension<dynamic>>[p],
    scaffoldBackgroundColor: p.background,
    canvasColor: p.background,
    cardColor: p.card,
    dividerColor: p.border,
    textTheme: textTheme,
    dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge?.copyWith(fontSize: 19, color: p.text),
      systemOverlayStyle: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),
    cardTheme: CardThemeData(
      color: p.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: cardShape,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: filledBg,
        foregroundColor: filledFg,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52)),
        shape: const WidgetStatePropertyAll(pill),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
        textStyle: WidgetStatePropertyAll(textTheme.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: filledBg,
        foregroundColor: filledFg,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52)),
        shape: const WidgetStatePropertyAll(pill),
        textStyle: WidgetStatePropertyAll(textTheme.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.text,
        minimumSize: const Size.fromHeight(52),
        shape: pill,
        side: BorderSide(color: p.border, width: 1.2),
        textStyle: textTheme.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accentText,
        shape: pill,
        textStyle: textTheme.labelLarge,
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: X9Colors.primary,
      foregroundColor: X9Colors.onPrimary,
      elevation: 2,
      shape: pill,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(pill),
        side: WidgetStatePropertyAll(BorderSide(color: p.border)),
        backgroundColor: WidgetStateProperty.resolveWith<Color?>((s) => s.contains(WidgetState.selected) ? p.primarySoft : Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith<Color?>((s) => s.contains(WidgetState.selected) ? p.onPrimarySoft : p.textSecondary),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.categoryBackground,
      // Selected chips: a stronger red tint (primary @ 20%) so the category text colour stays readable.
      selectedColor: X9Colors.primary.withValues(alpha: 0.20),
      disabledColor: p.surface,
      checkmarkColor: p.categoryText,
      side: BorderSide(color: p.categoryBorder),
      shape: pill,
      labelStyle: textTheme.labelLarge?.copyWith(color: p.categoryText, fontWeight: FontWeight.w600),
      secondaryLabelStyle: textTheme.labelLarge?.copyWith(color: p.categoryText, fontWeight: FontWeight.w600),
      iconTheme: IconThemeData(color: p.categoryText, size: 18),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      showCheckmark: true,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      hintStyle: TextStyle(color: p.textMuted),
      labelStyle: TextStyle(color: p.textSecondary),
      helperStyle: TextStyle(color: p.textSecondary),
      prefixIconColor: p.textSecondary,
      suffixIconColor: p.textSecondary,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: p.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: p.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: X9Colors.primary, width: 1.6)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: X9Colors.error)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: X9Colors.error, width: 1.6)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: p.primarySoft,
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? X9Colors.primary : p.textSecondary)),
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? accentText : p.textSecondary,
          )),
    ),
    navigationDrawerTheme: NavigationDrawerThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: p.primarySoft,
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? X9Colors.primary : p.textSecondary)),
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((s) => TextStyle(
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? accentText : p.text,
          )),
    ),
    drawerTheme: DrawerThemeData(backgroundColor: p.card, surfaceTintColor: Colors.transparent),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: p.card,
      selectedItemColor: X9Colors.primary,
      unselectedItemColor: p.textSecondary,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: accentText,
      unselectedLabelColor: p.textSecondary,
      indicatorColor: X9Colors.primary,
      dividerColor: p.border,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: p.textSecondary,
      textColor: p.text,
      selectedColor: accentText,
      selectedTileColor: p.primarySoft,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color?>((s) => s.contains(WidgetState.selected) ? X9Colors.onPrimary : p.textMuted),
      trackColor: WidgetStateProperty.resolveWith<Color?>((s) => s.contains(WidgetState.selected) ? X9Colors.primary : p.surface),
      trackOutlineColor: WidgetStateProperty.resolveWith<Color?>((s) => s.contains(WidgetState.selected) ? X9Colors.primary : p.textMuted),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color?>((s) => s.contains(WidgetState.selected) ? X9Colors.primary : Colors.transparent),
      checkColor: const WidgetStatePropertyAll(X9Colors.onPrimary),
      side: BorderSide(color: p.textMuted, width: 1.5),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color?>((s) => s.contains(WidgetState.selected) ? X9Colors.primary : p.textMuted),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: X9Colors.primary),
    sliderTheme: SliderThemeData(activeTrackColor: X9Colors.primary, thumbColor: X9Colors.primary, inactiveTrackColor: p.border),
    badgeTheme: const BadgeThemeData(backgroundColor: X9Colors.primary, textColor: X9Colors.onPrimary),
    dialogTheme: DialogThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.border)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: p.border,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
  );
}
