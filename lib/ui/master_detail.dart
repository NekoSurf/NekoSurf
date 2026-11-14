import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_chan/ui/back_swipe_route.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_header.dart';
import 'package:flutter_chan/ui/open.dart';
import 'package:flutter_chan/ui/window_size.dart';

/// A list of threads, with the thread opened from it beside it once there's
/// room for both, as on an iPad on its side. The list takes the page until
/// a thread is chosen; then it narrows to a column on the left, and the
/// thread comes in beside it, where threads opened from the list take each
/// other's place. Going back from the thread gives the list the page again.
/// Narrower, threads open over the list as on a phone.
class MasterDetail extends StatefulWidget {
  const MasterDetail({super.key, required this.master});

  /// From this wide, the list gets a pane beside it.
  static const double minWidth = 1000;

  /// How wide the list is beside the pane.
  static const double masterWidth = 380;

  final Widget master;

  @override
  State<MasterDetail> createState() => _MasterDetailState();
}

class _MasterDetailState extends State<MasterDetail> {
  final GlobalKey<NavigatorState> _pane = GlobalKey<NavigatorState>();

  /// The list, moved whole between the two layouts so it keeps its place.
  final GlobalKey _masterKey = GlobalKey();

  /// What the pane shows, from the list: when the window gets too narrow
  /// for the pane, it opens over the list instead.
  Destination? _shown;

  /// Whether the pane is open: a thread is there, over its empty first page,
  /// and going back closes it.
  bool _paneCanPop = false;

  /// The pane's navigator says when it can go back. That's kept here, not
  /// passed on: going on, it would tell the app it can't go back at all,
  /// though the page this is on can still be left.
  bool _onPaneNavigation(NavigationNotification notification) {
    final bool canPop = notification.canHandlePop;
    if (canPop != _paneCanPop) {
      // It can come while the pane is being built.
      if (SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _paneCanPop = canPop);
          }
        });
      } else {
        setState(() => _paneCanPop = canPop);
      }
    }
    return true;
  }

  void _show(Destination destination) {
    final NavigatorState? pane = _pane.currentState;
    if (pane == null) {
      return;
    }
    _shown = destination;
    // Over the pane's empty first page, so going back from the thread
    // closes the pane.
    pane.pushNamedAndRemoveUntil(
      Destination.routeName,
      (Route<dynamic> route) => route.isFirst,
      arguments: destination,
    );
  }

  /// Too narrow for the pane now: what it showed opens over the list.
  void _movePaneOut() {
    final Destination? shown = _paneCanPop ? _shown : null;
    _shown = null;
    _paneCanPop = false;
    if (shown == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(
          context,
        ).pushNamed(Destination.routeName, arguments: shown);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget master = KeyedSubtree(key: _masterKey, child: widget.master);
    // Without the app's pages (as in a test of just this page), there's
    // nothing to show in a pane.
    if (DestinationPages.maybeOf(context) == null) {
      return master;
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        if (width < MasterDetail.minWidth) {
          _movePaneOut();
          return master;
        }
        final bool open = _paneCanPop;
        // Back (Android's, or Esc) goes back in the pane first, then leaves
        // the page.
        return PopScope<Object?>(
          canPop: !open,
          onPopInvokedWithResult: (bool didPop, _) {
            if (!didPop) {
              _pane.currentState?.maybePop();
            }
          },
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: open ? 1 : 0),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            // The pane under the list, uncovered as the list narrows.
            child: MediaQuery.removePadding(
              context: context,
              removeLeft: true,
              child: PaneSize(
                // The list's scroll controller is the list's alone.
                child: PrimaryScrollController.none(
                  child: NotificationListener<NavigationNotification>(
                    onNotification: _onPaneNavigation,
                    child: Navigator(
                      key: _pane,
                      // The list keeps the keyboard until a thread comes.
                      requestFocus: false,
                      onGenerateInitialRoutes: (_, _) => [
                        PageRouteBuilder<void>(
                          pageBuilder: (context, _, _) =>
                              ColoredBox(color: DashColors.page(context)),
                        ),
                      ],
                      onGenerateRoute: (RouteSettings settings) {
                        final Object? destination = settings.arguments;
                        if (destination is! Destination) {
                          return null;
                        }
                        return BackSwipePageRoute<void>(
                          builder: (context) => DestinationPages.maybeOf(
                            context,
                          )!.pageFor(destination),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            builder: (BuildContext context, double t, Widget? pane) {
              final double listWidth = lerpDouble(
                width,
                MasterDetail.masterWidth,
                t,
              )!;
              return Stack(
                children: [
                  Positioned(
                    left: MasterDetail.masterWidth,
                    top: 0,
                    right: 0,
                    bottom: 0,
                    // A thread page's edge shadow, from the slide it came
                    // in with, stays in the pane rather than over the list.
                    child: ClipRect(child: pane),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: listWidth,
                    child: MediaQuery.removePadding(
                      context: context,
                      removeRight: t > 0,
                      child: PaneSize(
                        child: DetailPane(
                          show: _show,
                          // Its header's line, as the thread's header has,
                          // so the two read as one bar.
                          child: DashHeaderLine(always: open, child: master),
                        ),
                      ),
                    ),
                  ),
                  // A hairline between them, a pixel wide, like the one
                  // under the header.
                  if (t > 0)
                    Positioned(
                      left: listWidth,
                      top: 0,
                      bottom: 0,
                      width: 1 / MediaQuery.devicePixelRatioOf(context),
                      child: ColoredBox(
                        color: context.accent.withValues(alpha: 0.18 * t),
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
