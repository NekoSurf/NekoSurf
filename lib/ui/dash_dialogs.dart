import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/frosted.dart';

Future<T?> showDashDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? barrierColor,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: barrierColor ?? Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, _, _) => builder(ctx),
    transitionBuilder: (ctx, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
        child: child,
      );
    },
  );
}

class DashDialog extends StatelessWidget {
  const DashDialog({
    super.key,
    this.title,
    this.content,
    this.actions = const [],
  });

  final Widget? title;
  final Widget? content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
          margin: const EdgeInsets.symmetric(horizontal: 28),
          child: Frosted(
            fadesWithRoute: true,
            radius: 28,
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
            color: Frosted.panel(isDark),
            borderColor: DashColors.accent.withValues(alpha: 0.18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  DefaultTextStyle(
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: DashColors.text(isDark),
                    ),
                    child: title!,
                  ),
                if (content != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: DefaultTextStyle(
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.4,
                        color: DashColors.muted(isDark),
                      ),
                      child: content!,
                    ),
                  ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  if (actions.length <= 2)
                    Row(
                      children: [
                        for (int i = 0; i < actions.length; i++) ...[
                          if (i > 0) const SizedBox(width: 10),
                          Expanded(child: actions[i]),
                        ],
                      ],
                    )
                  else
                    for (int i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      actions[i],
                    ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DashDialogAction extends StatelessWidget {
  const DashDialogAction({
    super.key,
    required this.child,
    required this.onPressed,
    this.isDefaultAction = false,
    this.isDestructiveAction = false,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final bool isDefaultAction;
  final bool isDestructiveAction;

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;

    final Color background = isDestructiveAction
        ? DashColors.danger.withValues(alpha: 0.16)
        : isDefaultAction
        ? DashColors.accent
        : DashColors.muted(isDark).withValues(alpha: 0.14);
    final Color foreground = isDestructiveAction
        ? DashColors.danger
        : isDefaultAction
        ? Colors.black
        : DashColors.text(isDark);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: DefaultTextStyle(
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: foreground,
          ),
          textAlign: TextAlign.center,
          child: child,
        ),
      ),
    );
  }
}

class DashDialogField extends StatelessWidget {
  const DashDialogField({
    super.key,
    required this.controller,
    required this.placeholder,
    this.isCode = false,
  });

  final TextEditingController controller;
  final String placeholder;

  /// Typed as it's meant, without the keyboard's corrections and focused from
  /// the start.
  final bool isCode;

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;
    return CupertinoTextField(
      controller: controller,
      autofocus: isCode,
      autocorrect: !isCode,
      enableSuggestions: !isCode,
      smartDashesType: isCode ? SmartDashesType.disabled : null,
      smartQuotesType: isCode ? SmartQuotesType.disabled : null,
      placeholder: placeholder,
      padding: const EdgeInsets.all(14),
      style: TextStyle(color: DashColors.text(isDark)),
      decoration: BoxDecoration(
        color: DashColors.muted(isDark).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}
