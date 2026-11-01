import 'package:flutter/material.dart';

mixin DashColors {
  static const accent = Color(0xFF6DD4EC);
  static const accent2 = Color(0xFFA78BFA);
  static const nsfw = Color(0xFFFF5D6C);

  static Color card(bool isDark) =>
      isDark ? const Color(0xFF141520) : Colors.white;

  static Color border(bool isDark) => isDark
      ? Colors.white.withValues(alpha: 0.07)
      : Colors.black.withValues(alpha: 0.06);

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

Color boardColor(String board, {bool nsfw = false}) {
  if (nsfw) {
    return DashColors.nsfw;
  }
  final hash = board.codeUnits.fold<int>(0, (a, b) => a + b);
  return _boardPalette[hash % _boardPalette.length];
}

String timeAgo(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) {
    return 'just now';
  }
  if (diff.inHours < 1) {
    return '${diff.inMinutes}m ago';
  }
  if (diff.inDays < 1) {
    return '${diff.inHours}h ago';
  }
  return '${diff.inDays}d ago';
}
