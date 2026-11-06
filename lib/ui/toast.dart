import 'package:flutter/material.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_dialogs.dart';
import 'package:flutter_chan/ui/frosted.dart';

/// A short message at the bottom of the screen, gone after a moment or a tap.
Future<void> showToast(BuildContext context, String message) {
  return showDashDialog<void>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (context) => _Toast(message: message),
  );
}

class _Toast extends StatefulWidget {
  const _Toast({required this.message});

  final String message;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> {
  static const Duration _shown = Duration(milliseconds: 1800);

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(_shown, () {
      // A tap on the barrier may have closed it, and another toast be on top.
      final ModalRoute<void>? route = mounted ? ModalRoute.of(context) : null;
      if (route == null) {
        return;
      }
      if (route.isCurrent) {
        route.navigator?.pop();
      } else if (route.isActive) {
        route.navigator?.removeRoute(route);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;
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
          child: Frosted(
            fadesWithRoute: true,
            radius: 999,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            color: Frosted.panel(isDark),
            borderColor: DashColors.accent.withValues(alpha: 0.25),
            child: Text(
              widget.message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: DashColors.text(isDark),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
