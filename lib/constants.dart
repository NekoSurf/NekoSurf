import 'package:flutter/material.dart';

mixin AppColors {
  static const surfaceLight = Color(0xFFF4F5F7);
  static const surfaceDark = Color(0xFF0B0D11);

  static Color pageBackground(bool isDark) {
    return isDark ? surfaceDark : surfaceLight;
  }
}
