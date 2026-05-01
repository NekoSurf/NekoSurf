import 'dart:ui';

import 'package:flutter/material.dart';

Widget buildBlurPill({
  required Widget child,
  BorderRadius? borderRadius,
  EdgeInsetsGeometry? padding,
}) {
  final radius = borderRadius ?? BorderRadius.circular(999);
  return ClipRRect(
    borderRadius: radius,
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.28),
          borderRadius: radius,
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: child,
      ),
    ),
  );
}
