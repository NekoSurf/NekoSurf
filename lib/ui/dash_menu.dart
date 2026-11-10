import 'dart:math';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Lifts what's behind [context] off the page and opens the menu under it, as
/// holding something does on iPhone: [preview] builds the lifted copy, and the
/// page behind blurs. If nothing is chosen, the copy goes back into place.
///
/// Completes once it's all gone, for what was lifted to show again.
Future<void> showLiftedMenu(
  BuildContext context, {
  required List<DashMenuEntry> entries,
  required WidgetBuilder preview,
}) {
  final RenderBox box = context.findRenderObject()! as RenderBox;
  Rect? whereItIs() => context.mounted && box.attached && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : null;

  final _LiftedMenuRoute route = _LiftedMenuRoute(
    origin: whereItIs()!,
    whereItIs: whereItIs,
    preview: preview,
    entries: entries,
  );
  HapticFeedback.mediumImpact();
  Navigator.of(context).push(route);
  return route.completed;
}

class _LiftedMenuRoute extends PopupRoute<void> {
  _LiftedMenuRoute({
    required this.origin,
    required this.whereItIs,
    required this.preview,
    required this.entries,
  });

  /// Where what was lifted was, on screen.
  final Rect origin;

  /// Where it is now, to go back to; null if it's gone.
  final Rect? Function() whereItIs;
  final WidgetBuilder preview;
  final List<DashMenuEntry> entries;

  /// An entry was chosen: the copy fades where it is instead of going back,
  /// as what it's a copy of may be changing.
  bool chosen = false;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => 'Dismiss';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 320);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 240);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => _LiftedMenu(route: this);
}

class _LiftedMenu extends StatelessWidget {
  const _LiftedMenu({required this.route});

  final _LiftedMenuRoute route;

  /// The least room around the copy and the menu, from the screen's edges.
  static const double _margin = 12;

  /// Between the copy and the menu under it.
  static const double _gap = 8;

  /// The copy's sides from the screen's, lifted.
  static const double _inset = 8;

  static const double _radius = 22;

  /// Of a copy too tall to show all of, faded out at the bottom.
  static const double _fadeHeight = 40;

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;
    final Size screen = MediaQuery.sizeOf(context);
    final EdgeInsets safe = MediaQuery.paddingOf(context);
    final Rect origin = route.origin;
    final double menuHeight = _MenuPanel.heightOf(route.entries);

    // Lifted, it's a card with room on both sides, never bigger than it was,
    // and as much of it as fits above the menu.
    final double scale = min(1, (screen.width - 2 * _inset) / origin.width);
    final double width = origin.width * scale;
    final double fullHeight = origin.height * scale;
    final double height = min(
      fullHeight,
      max(
        _fadeHeight * 2,
        screen.height - safe.vertical - 2 * _margin - _gap - menuHeight,
      ),
    );
    final double highest = safe.top + _margin;
    final double lowest =
        screen.height - safe.bottom - _margin - menuHeight - _gap - height;
    final Rect lifted = Rect.fromLTWH(
      scale < 1 ? (screen.width - width) / 2 : origin.left,
      max(highest, min(origin.top, lowest)),
      width,
      height,
    );
    // Lined up with the copy, as far as it fits.
    final double menuLeft = lifted.left.clamp(
      _inset,
      max(_inset, screen.width - _MenuPanel.width - _inset),
    );
    final bool isClipped = height < fullHeight;
    final Animation<double> animation = route.animation!;

    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, _) {
        final double t = Curves.easeOutCubic.transform(animation.value);
        final double menuShown = const Interval(
          0.3,
          1,
          curve: Curves.easeOutCubic,
        ).transform(animation.value);
        // Going back to where it is now: the list may have moved under it.
        final Rect? from = animation.status == AnimationStatus.reverse
            ? (route.chosen ? null : route.whereItIs())
            : origin;
        final bool fades = from == null;
        final Rect rect = fades ? lifted : Rect.lerp(from, lifted, t)!;
        final double copyScale = fades ? scale : lerpDouble(1, scale, t)!;

        Widget copy = OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: origin.width,
          maxWidth: origin.width,
          maxHeight: double.infinity,
          child: Transform.scale(
            scale: copyScale,
            alignment: Alignment.topLeft,
            child: IgnorePointer(
              child: Material(
                type: MaterialType.transparency,
                child: route.preview(context),
              ),
            ),
          ),
        );
        if (isClipped) {
          copy = ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (Rect bounds) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [1 - _fadeHeight / bounds.height, 1],
              colors: [
                Colors.black,
                Colors.black.withValues(alpha: 1 - t),
              ],
            ).createShader(bounds),
            child: copy,
          );
        }

        return Stack(
          children: [
            // Taps go through to the barrier below, which closes the menu.
            Positioned.fill(
              child: IgnorePointer(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12 * t, sigmaY: 12 * t),
                  child: ColoredBox(
                    color: Colors.black.withValues(
                      alpha: (isDark ? 0.35 : 0.2) * t,
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fromRect(
              rect: rect,
              child: Opacity(
                opacity: fades ? t : 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: DashColors.card(context).withValues(alpha: t),
                    borderRadius: BorderRadius.circular(_radius * t),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22 * t),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_radius * t),
                    child: copy,
                  ),
                ),
              ),
            ),
            Positioned(
              left: menuLeft,
              top: lifted.bottom + _gap,
              width: _MenuPanel.width,
              child: Opacity(
                opacity: menuShown,
                child: Transform.scale(
                  scale: lerpDouble(0.9, 1, menuShown),
                  alignment: Alignment.topLeft,
                  child: _MenuPanel(
                    entries: route.entries,
                    onChoosing: () => route.chosen = true,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
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

  static const double _width = _MenuPanel.width;
  static const double _margin = 12;

  /// Room below the anchor that's enough for most menus, so they open there.
  static const double _enoughBelow = 240;

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    final EdgeInsets safe = MediaQuery.paddingOf(context);

    final bool alignRight = anchor.center.dx > screen.width / 2;
    final double left = (alignRight ? anchor.right - _width : anchor.left)
        .clamp(_margin, screen.width - _width - _margin);
    final double top = anchor.bottom + 8;
    final double roomBelow = screen.height - top - safe.bottom - _margin;
    final double bottom = screen.height - anchor.top + 8;
    final double roomAbove = screen.height - bottom - safe.top - _margin;
    // Anchored low on the screen, like a post near the bottom, it opens above.
    final bool opensAbove = roomBelow < _enoughBelow && roomAbove > roomBelow;
    final double maxHeight = max(0, opensAbove ? roomAbove : roomBelow);

    return Stack(
      children: [
        Positioned(
          left: left,
          top: opensAbove ? null : top,
          bottom: opensAbove ? bottom : null,
          width: _width,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: _MenuPanel(entries: entries, title: title),
          ),
        ),
      ],
    );
  }
}

/// The card a menu's entries are on. Choosing one closes the menu and runs
/// it, after [onChoosing].
class _MenuPanel extends StatelessWidget {
  const _MenuPanel({required this.entries, this.title, this.onChoosing});

  final List<DashMenuEntry> entries;
  final String? title;
  final VoidCallback? onChoosing;

  static const double width = 250;
  static const double _padding = 6;
  static const double _rowHeight = 44;
  static const double _dividerHeight = 9;

  /// How tall it is without a title, to make room for it.
  static double heightOf(List<DashMenuEntry> entries) =>
      2 * _padding +
      entries.fold<double>(
        0,
        (double height, DashMenuEntry entry) =>
            height + (entry.isDivider ? _dividerHeight : _rowHeight),
      );

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Frosted(
        fadesWithRoute: true,
        radius: 22,
        padding: const EdgeInsets.all(_padding),
        color: Frosted.panel(context),
        borderColor: DashColors.border(context),
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
                      color: DashColors.muted(context),
                    ),
                  ),
                ),
              for (final entry in entries)
                if (entry.isDivider)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: (_dividerHeight - 1) / 2,
                    ),
                    child: Divider(
                      height: 1,
                      color: DashColors.border(context),
                    ),
                  )
                else
                  _MenuRow(
                    entry: entry,
                    onTap: () {
                      onChoosing?.call();
                      Navigator.of(context).pop();
                      entry.onPressed?.call();
                    },
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.entry, required this.onTap});

  final DashMenuEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color tint = entry.isDestructive ? DashColors.danger : context.accent;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: _MenuPanel._rowHeight,
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
                      : DashColors.text(context),
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
