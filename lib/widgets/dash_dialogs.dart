import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';

bool _isDark(BuildContext context) =>
    CupertinoTheme.brightnessOf(context) == Brightness.dark;

Future<T?> showDashDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'Dismiss',
    barrierColor: barrierColor ?? Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, _, _) => builder(ctx),
    transitionBuilder: (ctx, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          child: child,
        ),
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
    final bool isDark = _isDark(context);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
          margin: const EdgeInsets.symmetric(horizontal: 28),
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
          decoration: BoxDecoration(
            color: DashColors.card(isDark),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: DashColors.accent.withValues(alpha: 0.18),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
          ),
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
    final bool isDark = _isDark(context);

    final Color background = isDestructiveAction
        ? DashColors.nsfw.withValues(alpha: 0.16)
        : isDefaultAction
        ? DashColors.accent
        : DashColors.muted(isDark).withValues(alpha: 0.14);
    final Color foreground = isDestructiveAction
        ? DashColors.nsfw
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

class DashMenuEntry {
  const DashMenuEntry({
    this.title = '',
    this.icon,
    this.isSelected = false,
    this.isDestructive = false,
    this.onPressed,
    this.isDivider = false,
  });

  final String title;
  final IconData? icon;
  final bool isSelected;
  final bool isDestructive;
  final VoidCallback? onPressed;
  final bool isDivider;
}

class DashMenuDivider extends DashMenuEntry {
  const DashMenuDivider() : super(isDivider: true);
}

/// Dropdown card anchored to the widget behind [context].
Future<void> showDashMenu(
  BuildContext context, {
  required List<DashMenuEntry> entries,
  String? title,
}) {
  final box = context.findRenderObject()! as RenderBox;
  final Rect anchor = box.localToGlobal(Offset.zero) & box.size;

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black.withValues(alpha: 0.25),
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (ctx, _, _) =>
        _DashMenu(anchor: anchor, entries: entries, title: title),
    transitionBuilder: (ctx, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(opacity: curved, child: child);
    },
  );
}

class DashMenuAnchor extends StatelessWidget {
  const DashMenuAnchor({
    super.key,
    required this.menuChildren,
    required this.builder,
    this.title,
  });

  final List<DashMenuEntry> menuChildren;
  final Widget Function(BuildContext context, VoidCallback open) builder;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return builder(
      context,
      () => showDashMenu(context, entries: menuChildren, title: title),
    );
  }
}

class _DashMenu extends StatelessWidget {
  const _DashMenu({required this.anchor, required this.entries, this.title});

  final Rect anchor;
  final List<DashMenuEntry> entries;
  final String? title;

  static const double _width = 250;
  static const double _margin = 12;

  @override
  Widget build(BuildContext context) {
    final bool isDark = _isDark(context);
    final Size screen = MediaQuery.sizeOf(context);
    final EdgeInsets safe = MediaQuery.paddingOf(context);

    final bool alignRight = anchor.center.dx > screen.width / 2;
    final double left = (alignRight ? anchor.right - _width : anchor.left)
        .clamp(_margin, screen.width - _width - _margin);
    final double top = anchor.bottom + 8;
    final double maxHeight = screen.height - top - safe.bottom - _margin;

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: _width,
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: BoxConstraints(maxHeight: maxHeight),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: DashColors.card(isDark),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: DashColors.border(isDark)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (title != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                        child: Text(
                          title!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: DashColors.muted(isDark),
                          ),
                        ),
                      ),
                    for (final entry in entries)
                      if (entry.isDivider)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          child: Divider(
                            height: 1,
                            color: DashColors.border(isDark),
                          ),
                        )
                      else
                        _MenuRow(entry: entry, isDark: isDark),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.entry, required this.isDark});

  final DashMenuEntry entry;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final Color tint = entry.isDestructive
        ? DashColors.nsfw
        : DashColors.accent;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.of(context).pop();
        entry.onPressed?.call();
      },
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: entry.isSelected
              ? DashColors.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            if (entry.icon != null)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(entry.icon, size: 18, color: tint),
              ),
            Expanded(
              child: Text(
                entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: entry.isDestructive
                      ? DashColors.nsfw
                      : DashColors.text(isDark),
                ),
              ),
            ),
            if (entry.isSelected)
              const Icon(
                CupertinoIcons.checkmark_alt,
                size: 18,
                color: DashColors.accent,
              ),
          ],
        ),
      ),
    );
  }
}
