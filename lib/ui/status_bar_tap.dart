import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Takes [scroll]'s list to its top, as tapping the tab shown or the status
/// bar does.
void scrollToTop(ScrollController? scroll) {
  if (scroll == null || !scroll.hasClients) {
    return;
  }
  if (scroll.positions.every(
    (ScrollPosition position) => position.pixels <= 0,
  )) {
    return;
  }
  scroll.animateTo(
    0,
    duration: const Duration(milliseconds: 450),
    curve: Curves.easeOutCubic,
  );
}

/// Calls [onTap] when the status bar is tapped on iPhone and iPad, to take
/// the page in [child] to its top, as in other iOS apps.
///
/// iOS says only that the status bar was tapped, not where, and every page
/// kept alive hears it: the pages under the one on screen, and the tabs not
/// shown. So only a page whose top is on screen, and not covered by another
/// page or a dialog, answers.
class StatusBarTap extends StatefulWidget {
  const StatusBarTap({super.key, required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<StatusBarTap> createState() => _StatusBarTapState();
}

class _StatusBarTapState extends State<StatusBarTap>
    with WidgetsBindingObserver {
  /// The strip under the status bar, which only a page on top can be hit in.
  final GlobalKey _strip = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void activate() {
    super.activate();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void deactivate() {
    WidgetsBinding.instance.removeObserver(this);
    super.deactivate();
  }

  @override
  void handleStatusBarTap() {
    if (_onTop()) {
      widget.onTap();
    }
  }

  /// Whether a tap in the middle of the strip would reach it. Where a list
  /// has a thread beside it, both are on top, and both go up.
  bool _onTop() {
    final BuildContext? strip = _strip.currentContext;
    final RenderObject? box = strip?.findRenderObject();
    if (strip == null || box is! RenderBox || !box.attached || !box.hasSize) {
      return false;
    }
    final Offset middle = box.localToGlobal(box.size.center(Offset.zero));
    final HitTestResult result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      middle,
      View.of(strip).viewId,
    );
    return result.path.any((HitTestEntry entry) => entry.target == box);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          // A line at least, to hit, where there's no status bar.
          height: math.max(MediaQuery.paddingOf(context).top, 1),
          // Lets taps through to what's under it.
          child: MetaData(
            key: _strip,
            behavior: HitTestBehavior.translucent,
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}
