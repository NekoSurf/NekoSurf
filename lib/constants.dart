import 'package:flutter/material.dart';

class AppColors {
  static const kGreen = Color.fromRGBO(146, 189, 38, 1);
  static const kWhite = Colors.white;
  static const kBlack = Color.fromRGBO(68, 68, 68, 1);

  static const surfaceLight = Color(0xFFF4F5F7);
  static const surfaceDark = Color(0xFF0B0D11);

  static Color pageBackground(bool isDark) {
    return isDark ? surfaceDark : surfaceLight;
  }

  static Color navigationBackground(bool isDark) {
    return isDark
        ? surfaceDark.withValues(alpha: 0.92)
        : surfaceLight.withValues(alpha: 0.92);
  }
}
