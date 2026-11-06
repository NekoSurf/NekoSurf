import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

extension DarkMode on BuildContext {
  bool get isDark => CupertinoTheme.brightnessOf(this) == Brightness.dark;
}

mixin DashColors {
  static const accent = Color(0xFF6DD4EC);
  static const accent2 = Color(0xFFA78BFA);
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
