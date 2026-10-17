import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';
import 'package:flutter_chan/widgets/dash_dialogs.dart';

Future<dynamic> showCupertinoSnackbar(
  Duration? duration,
  bool dismissable,
  BuildContext context,
  String message,
) {
  return showDashDialog<bool>(
    context: context,
    barrierColor: Colors.transparent,
    barrierDismissible: dismissable,
    builder: (context) {
      final bool isDark =
          CupertinoTheme.brightnessOf(context) == Brightness.dark;
      if (duration != null) {
        Future.delayed(duration, () {
          if (context.mounted) {
            Navigator.of(context).pop(true);
          }
        });
      }
      return Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 96,
              left: 24,
              right: 24,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: DashColors.card(isDark),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: DashColors.accent.withValues(alpha: 0.25),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: DashColors.text(isDark),
              ),
            ),
          ),
        ),
      );
    },
  );
}
