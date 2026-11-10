import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_header.dart';
import 'package:flutter_chan/ui/frosted.dart';

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
  );
}

/// Gives what [builder] builds a way to [open] the menu, anchored to it.
class DashMenuAnchor extends StatelessWidget {
  const DashMenuAnchor({
    super.key,
    required this.menuChildren,
    required this.builder,
  });

  final List<DashMenuEntry> menuChildren;
  final Widget Function(BuildContext context, VoidCallback open) builder;

  @override
  Widget build(BuildContext context) {
    return builder(context, () => showDashMenu(context, entries: menuChildren));
  }
}

class DashMenuButton extends StatelessWidget {
  const DashMenuButton({
    super.key,
    this.icon = CupertinoIcons.ellipsis_circle,
    this.label = 'More',
    required this.menuChildren,
  });

  final IconData icon;
  final String label;
  final List<DashMenuEntry> menuChildren;

  @override
  Widget build(BuildContext context) {
    return DashMenuAnchor(
      menuChildren: menuChildren,
      builder: (context, open) =>
          DashIconButton(label: label, icon: Icon(icon), onPressed: open),
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
    final bool isDark = context.isDark;
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
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Frosted(
                fadesWithRoute: true,
                radius: 22,
                padding: const EdgeInsets.all(6),
                color: Frosted.panel(isDark),
                borderColor: DashColors.border(isDark),
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
                          _MenuRow(entry: entry),
                    ],
                  ),
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
  const _MenuRow({required this.entry});

  final DashMenuEntry entry;

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;
    final Color tint = entry.isDestructive ? DashColors.danger : context.accent;

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
              ? context.accent.withValues(alpha: 0.12)
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
                      ? DashColors.danger
                      : DashColors.text(isDark),
                ),
              ),
            ),
            if (entry.isSelected)
              Icon(
                CupertinoIcons.checkmark_alt,
                size: 18,
                color: context.accent,
              ),
          ],
        ),
      ),
    );
  }
}
