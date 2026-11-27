import 'dart:async';
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

/// Dropdown card anchored to the widget behind [context]. Completes once
/// it's closed.
///
/// It floats over the page rather than being a route of its own, so that, as
/// on iPhone, a touch outside it closes it and carries on to the page: a
/// list scrolls with the same swipe. (A route can't let it through: the
/// navigator cancels the touches on screen when a route goes.) Going back,
/// like Android's back gesture, closes it first.
Future<void> showDashMenu(
  BuildContext context, {
  required List<DashMenuEntry> entries,
  String? title,
}) {
  final box = context.findRenderObject()! as RenderBox;
  final Rect anchor = box.localToGlobal(Offset.zero) & box.size;
  final OverlayState overlay = Overlay.of(context, rootOverlay: true);
  final ModalRoute<Object?>? route = ModalRoute.of(context);
  final Completer<void> closed = Completer<void>();
  final GlobalKey<_DashMenuState> menu = GlobalKey<_DashMenuState>();
  final _ClosesOnBack back = _ClosesOnBack(() => menu.currentState?.close());
  route?.registerPopEntry(back);

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _DashMenu(
      key: menu,
      anchor: anchor,
      entries: entries,
      title: title,
      // At once, so a swipe back that starts outside the menu isn't held.
      onClosing: () => route?.unregisterPopEntry(back),
      onClosed: () {
        back.dispose();
        entry.remove();
        entry.dispose();
        closed.complete();
      },
    ),
  );
  overlay.insert(entry);
  return closed.future;
}

/// Holds the page's going back while a menu is open, closing the menu
/// instead.
class _ClosesOnBack extends PopEntry<Object?> {
  _ClosesOnBack(this.onBack);

  final VoidCallback onBack;

  @override
  final ValueNotifier<bool> canPopNotifier = ValueNotifier<bool>(false);

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (!didPop) {
      // Closing lets go of this, which the route is still going through.
      scheduleMicrotask(onBack);
    }
  }

  void dispose() => canPopNotifier.dispose();
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
  // Over the whole window, where the copy's place is measured, even from a
  // pane beside another.
  Navigator.of(context, rootNavigator: true).push(route);
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

class _DashMenu extends StatefulWidget {
  const _DashMenu({
    super.key,
    required this.anchor,
    required this.entries,
    required this.onClosing,
    required this.onClosed,
    this.title,
  });

  final Rect anchor;
  final List<DashMenuEntry> entries;
  final String? title;

  /// It's starting to close.
  final VoidCallback onClosing;

  /// It's gone from the screen.
  final VoidCallback onClosed;

  @override
  State<_DashMenu> createState() => _DashMenuState();
}

class _DashMenuState extends State<_DashMenu>
    with SingleTickerProviderStateMixin {
  static const double _width = _MenuPanel.width;
  static const double _margin = 12;

  /// Room below the anchor that's enough for most menus, so they open there.
  static const double _enoughBelow = 240;

  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    reverseDuration: const Duration(milliseconds: 180),
  )..forward();

  bool _closing = false;

  /// Shrinks it away, then it's gone. Once.
  Future<void> close() async {
    if (_closing) {
      return;
    }
    _closing = true;
    widget.onClosing();
    setState(() {});
    await _animation.reverse();
    widget.onClosed();
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Rect anchor = widget.anchor;
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
        // Under the menu, so only touches outside it reach this; they go on
        // to the page too (translucent), and close the menu.
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => close(),
          ),
        ),
        Positioned(
          left: left,
          top: opensAbove ? null : top,
          bottom: opensAbove ? bottom : null,
          width: _width,
          child: IgnorePointer(
            ignoring: _closing,
            child: _GrowsFromAnchor(
              animation: _animation,
              alignment: Alignment(alignRight ? 1 : -1, opensAbove ? 1 : -1),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: _MenuPanel(
                  entries: widget.entries,
                  title: widget.title,
                  fade: _animation,
                  onClose: close,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Grows the menu out of the corner nearest what opened it, with a little
/// overshoot, as iOS's menus spring out of their button; it shrinks back
/// into it as it fades when closed.
class _GrowsFromAnchor extends StatelessWidget {
  const _GrowsFromAnchor({
    required this.animation,
    required this.alignment,
    required this.child,
  });

  final Animation<double> animation;
  final Alignment alignment;
  final Widget child;

  /// Past 1 a little before settling, like a spring.
  static const Curve _spring = Cubic(0.2, 1.25, 0.35, 1);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (BuildContext context, Widget? child) {
        final bool closing = animation.status == AnimationStatus.reverse;
        final double scale = closing
            ? lerpDouble(0.85, 1, Curves.easeIn.transform(animation.value))!
            : lerpDouble(0.4, 1, _spring.transform(animation.value))!;
        return Transform.scale(
          scale: scale,
          alignment: alignment,
          child: child,
        );
      },
    );
  }
}

/// The card a menu's entries are on. Choosing one closes the menu and runs
/// it, after [onChoosing].
///
/// As on iOS, the row under the finger lights up as soon as it's touched,
/// and the finger can slide over the others, with a tick on each, to let go
/// on the one it wants. Scrolling a long menu chooses nothing.
class _MenuPanel extends StatefulWidget {
  const _MenuPanel({
    required this.entries,
    this.title,
    this.onChoosing,
    this.fade,
    this.onClose,
  });

  final List<DashMenuEntry> entries;
  final String? title;
  final VoidCallback? onChoosing;

  /// What it comes and goes with; its route's animation if null.
  final Animation<double>? fade;

  /// Closes it; pops its route if null.
  final VoidCallback? onClose;

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
  State<_MenuPanel> createState() => _MenuPanelState();
}

class _MenuPanelState extends State<_MenuPanel> {
  final ScrollController _scroll = ScrollController();
  late List<GlobalKey> _rowKeys = _keysFor(widget.entries);

  /// The row lit up under the finger.
  int? _pressed;
  int? _pointer;
  double _scrolledAtDown = 0;
  bool _scrolled = false;

  static List<GlobalKey> _keysFor(List<DashMenuEntry> entries) =>
      List<GlobalKey>.generate(entries.length, (_) => GlobalKey());

  @override
  void didUpdateWidget(covariant _MenuPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entries.length != widget.entries.length) {
      _rowKeys = _keysFor(widget.entries);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  double get _offset => _scroll.hasClients ? _scroll.offset : 0;

  /// The entry under [position], on screen; null over a divider or the edge.
  int? _rowAt(Offset position) {
    for (int i = 0; i < widget.entries.length; i++) {
      if (widget.entries[i].isDivider) {
        continue;
      }
      final RenderObject? box = _rowKeys[i].currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        final Offset local = box.globalToLocal(position);
        if (box.size.contains(local)) {
          return i;
        }
      }
    }
    return null;
  }

  void _press(int? row) {
    if (row != _pressed) {
      setState(() => _pressed = row);
    }
  }

  void _choose(DashMenuEntry entry) {
    widget.onChoosing?.call();
    final VoidCallback? close = widget.onClose;
    if (close != null) {
      close();
    } else {
      Navigator.of(context).pop();
    }
    entry.onPressed?.call();
  }

  void _onDown(PointerDownEvent event) {
    if (_pointer != null) {
      return;
    }
    _pointer = event.pointer;
    _scrolledAtDown = _offset;
    _scrolled = false;
    _press(_rowAt(event.position));
  }

  void _onMove(PointerMoveEvent event) {
    if (event.pointer != _pointer || _scrolled) {
      return;
    }
    if ((_offset - _scrolledAtDown).abs() > 1) {
      _scrolled = true;
      _press(null);
      return;
    }
    final int? row = _rowAt(event.position);
    if (row != null && row != _pressed) {
      HapticFeedback.selectionClick();
    }
    _press(row);
  }

  void _onUp(PointerUpEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    _pointer = null;
    final int? row = _scrolled ? null : _rowAt(event.position);
    _press(null);
    if (row != null) {
      _choose(widget.entries[row]);
    }
  }

  void _onCancel(PointerCancelEvent event) {
    if (event.pointer == _pointer) {
      _pointer = null;
      _press(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<DashMenuEntry> entries = widget.entries;
    final String? title = widget.title;

    return Material(
      color: Colors.transparent,
      child: Frosted(
        fadesWithRoute: widget.fade == null,
        fade: widget.fade,
        radius: 22,
        padding: const EdgeInsets.all(_MenuPanel._padding),
        color: Frosted.panel(context),
        borderColor: DashColors.border(context),
        child: Listener(
          onPointerDown: _onDown,
          onPointerMove: _onMove,
          onPointerUp: _onUp,
          onPointerCancel: _onCancel,
          child: SingleChildScrollView(
            controller: _scroll,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: DashColors.muted(context),
                      ),
                    ),
                  ),
                for (int i = 0; i < entries.length; i++)
                  if (entries[i].isDivider)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: (_MenuPanel._dividerHeight - 1) / 2,
                      ),
                      child: Divider(
                        height: 1,
                        color: DashColors.border(context),
                      ),
                    )
                  else
                    Semantics(
                      button: true,
                      selected: entries[i].isSelected,
                      onTap: () => _choose(entries[i]),
                      child: _MenuRow(
                        key: _rowKeys[i],
                        entry: entries[i],
                        pressed: _pressed == i,
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({super.key, required this.entry, required this.pressed});

  final DashMenuEntry entry;

  /// The finger is on it.
  final bool pressed;

  @override
  Widget build(BuildContext context) {
    final Color tint = entry.isDestructive ? DashColors.danger : context.accent;

    return Container(
      height: _MenuPanel._rowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: pressed
            ? DashColors.text(context).withValues(alpha: 0.1)
            : entry.isSelected
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
            Icon(CupertinoIcons.checkmark_alt, size: 18, color: context.accent),
        ],
      ),
    );
  }
}
