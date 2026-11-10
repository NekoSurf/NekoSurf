import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

extension DarkMode on BuildContext {
  bool get isDark => CupertinoTheme.brightnessOf(this) == Brightness.dark;
}

/// The colors of the theme chosen in Settings.
extension ThemeColors on BuildContext {
  ThemeColor get themeColor => DashTheme.of(this);

  /// See [ThemeColor.accent].
  Color get accent => themeColor.accent;

  /// See [ThemeColor.accent2].
  Color get accent2 => themeColor.accent2;
}

/// A theme to choose in Settings: the colors the app highlights with.
///
/// Every [accent] is light enough for black text on it, like the selected
/// segment of a choice.
enum ThemeColor {
  cyan('Cyan', Color(0xFF6DD4EC), Color(0xFFA78BFA), Color(0xFF0E7C9B)),
  blue('Blue', Color(0xFF60A5FA), Color(0xFFC084FC), Color(0xFF1D4ED8)),
  indigo('Indigo', Color(0xFF818CF8), Color(0xFFE879F9), Color(0xFF4338CA)),
  violet('Violet', Color(0xFFA78BFA), Color(0xFFF472B6), Color(0xFF6D28D9)),
  purple('Purple', Color(0xFFC084FC), Color(0xFFFB7185), Color(0xFF7E22CE)),
  fuchsia('Fuchsia', Color(0xFFE879F9), Color(0xFF818CF8), Color(0xFFA21CAF)),
  pink('Pink', Color(0xFFF472B6), Color(0xFFA78BFA), Color(0xFFBE185D)),
  rose('Rose', Color(0xFFFB7185), Color(0xFFC084FC), Color(0xFFBE123C)),
  red('Red', Color(0xFFF87171), Color(0xFFFB923C), Color(0xFFB91C1C)),
  orange('Orange', Color(0xFFFB923C), Color(0xFFF472B6), Color(0xFFC2410C)),
  amber('Amber', Color(0xFFFBBF24), Color(0xFFFB7185), Color(0xFFB45309)),
  yellow('Yellow', Color(0xFFFACC15), Color(0xFF4ADE80), Color(0xFFA16207)),
  lime('Lime', Color(0xFFA3E635), Color(0xFF2DD4BF), Color(0xFF4D7C0F)),
  green('Green', Color(0xFF4ADE80), Color(0xFF60A5FA), Color(0xFF15803D)),
  emerald('Emerald', Color(0xFF34D399), Color(0xFF818CF8), Color(0xFF047857)),
  teal('Teal', Color(0xFF2DD4BF), Color(0xFFA78BFA), Color(0xFF0F766E));

  const ThemeColor(this.title, this.accent, this.accent2, this.ink);

  final String title;

  /// What's chosen, active or new.
  final Color accent;

  /// Set beside [accent], to tell two kinds of things apart (like images and
  /// videos) or blend into it.
  final Color accent2;

  /// [accent] dark enough to read as text on a light background.
  final Color ink;
}

/// Hands the chosen [ThemeColor] down to everything below it.
class DashTheme extends InheritedWidget {
  const DashTheme({super.key, required this.color, required super.child});

  final ThemeColor color;

  /// The first theme, for what's built without one, like in tests.
  static ThemeColor of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DashTheme>()?.color ??
      ThemeColor.cyan;

  @override
  bool updateShouldNotify(DashTheme oldWidget) => color != oldWidget.color;
}

mixin DashColors {
  static const danger = Color(0xFFFF5D6C);
  static const feed = Color(0xFFF472B6);

  static Color page(bool isDark) =>
      isDark ? const Color(0xFF0B0D11) : const Color(0xFFF4F5F7);

  static Color card(bool isDark) =>
      isDark ? const Color(0xFF141520) : Colors.white;

  static Color border(bool isDark) => isDark
      ? Colors.white.withValues(alpha: 0.07)
      : Colors.black.withValues(alpha: 0.06);

  /// What lifts a card off a light page.
  static List<BoxShadow> cardShadow(bool isDark) => isDark
      ? const <BoxShadow>[]
      : const <BoxShadow>[
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ];

  static Color muted(bool isDark) =>
      isDark ? const Color(0xFF8A8FA8) : const Color(0xFF6B7085);

  static Color text(bool isDark) =>
      isDark ? const Color(0xFFE8EAF0) : const Color(0xFF14161F);
}

const _boardPalette = [
  Color(0xFF6DD4EC),
  Color(0xFFA78BFA),
  Color(0xFF34D399),
  Color(0xFFFBBF24),
  Color(0xFFF472B6),
  Color(0xFF60A5FA),
  Color(0xFFFB923C),
];

Color boardColor(String board) {
  final hash = board.codeUnits.fold<int>(0, (a, b) => a + b);
  return _boardPalette[hash % _boardPalette.length];
}
