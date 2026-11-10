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

/// A theme to choose in Settings: the colors the app highlights with, and the
/// [palette] of the pages, cards and text they're on.
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

  /// The pages, cards and text, light or dark: tinted with [accent]'s hue,
  /// except Cyan's, which are the app's colors from before there were themes.
  DashPalette palette(Brightness brightness) => _palettes.putIfAbsent(
    (this, brightness),
    () => this == ThemeColor.cyan
        ? DashPalette.classic(brightness)
        : DashPalette.tinted(HSLColor.fromColor(accent).hue, brightness),
  );
}

final Map<(ThemeColor, Brightness), DashPalette> _palettes =
    <(ThemeColor, Brightness), DashPalette>{};

/// What everything in a theme sits on: the page, cards on it, lines between
/// things, and text.
@immutable
class DashPalette {
  const DashPalette({
    required this.page,
    required this.card,
    required this.border,
    required this.muted,
    required this.text,
  });

  /// The app's colors from before there were themes.
  factory DashPalette.classic(Brightness brightness) =>
      brightness == Brightness.dark
      ? DashPalette(
          page: const Color(0xFF0B0D11),
          card: const Color(0xFF141520),
          border: Colors.white.withValues(alpha: 0.07),
          muted: const Color(0xFF8A8FA8),
          text: const Color(0xFFE8EAF0),
        )
      : DashPalette(
          page: const Color(0xFFF4F5F7),
          card: Colors.white,
          border: Colors.black.withValues(alpha: 0.06),
          muted: const Color(0xFF6B7085),
          text: const Color(0xFF14161F),
        );

  /// Colors of [hue]: dark ones deep and tinted, light ones pale. Text is
  /// near black or white, and [muted] still reads on the page and cards.
  factory DashPalette.tinted(double hue, Brightness brightness) {
    Color hsl(double saturation, double lightness, [double alpha = 1]) =>
        HSLColor.fromAHSL(alpha, hue, saturation, lightness).toColor();
    return brightness == Brightness.dark
        ? DashPalette(
            page: hsl(0.32, 0.06),
            card: hsl(0.28, 0.115),
            border: hsl(0.5, 0.85, 0.08),
            muted: hsl(0.16, 0.64),
            text: hsl(0.30, 0.93),
          )
        : DashPalette(
            page: hsl(0.45, 0.95),
            card: hsl(0.70, 0.995),
            border: hsl(0.4, 0.25, 0.08),
            muted: hsl(0.16, 0.38),
            text: hsl(0.35, 0.10),
          );
  }

  final Color page;
  final Color card;
  final Color border;

  /// Text that matters less, like when something was posted.
  final Color muted;
  final Color text;
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

/// The theme's colors where [context] is, light or dark as it is there.
mixin DashColors {
  static const danger = Color(0xFFFF5D6C);
  static const feed = Color(0xFFF472B6);

  static DashPalette palette(BuildContext context) =>
      DashTheme.of(context).palette(CupertinoTheme.brightnessOf(context));

  static Color page(BuildContext context) => palette(context).page;

  static Color card(BuildContext context) => palette(context).card;

  static Color border(BuildContext context) => palette(context).border;

  /// See [DashPalette.muted].
  static Color muted(BuildContext context) => palette(context).muted;

  static Color text(BuildContext context) => palette(context).text;

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
