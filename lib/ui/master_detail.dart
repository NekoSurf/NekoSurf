import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_chan/ui/back_swipe_route.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_header.dart';
import 'package:flutter_chan/ui/open.dart';
import 'package:flutter_chan/ui/window_size.dart';

/// A list of threads, with the thread opened from it beside it once there's
/// room for both, as on an iPad on its side or an iPhone Duo open. The list
/// takes the page until
/// a thread is chosen; then it narrows to a column on the left, and the
/// thread comes in beside it, where threads opened from the list take each
/// other's place. Going back from the thread gives the list the page again.
/// Narrower, threads open over the list as on a phone.
class MasterDetail extends StatefulWidget {
  const MasterDetail({super.key, required this.master});

  /// From this wide, the list gets a pane beside it: room for the list, in
  /// its narrower column, and a thread about as wide as a big phone's. An
  /// iPhone Duo open has it, 755 beside the tabs' sidebar and the room its
  /// camera takes, and so does an 11" iPad upright, beside a board; an iPad
  /// mini upright, 744, doesn't.
  static const double minWidth = 750;

  /// How wide the list is beside the pane.
  static const double masterWidth = 380;

  /// How wide it is in a window narrower than [roomyWidth], to leave the
  /// thread room.
  static const double narrowMasterWidth = 320;
  static const double roomyWidth = 1000;

  /// How wide the list is beside the pane, in [width].
  static double masterWidthIn(double width) =>
      width < roomyWidth ? narrowMasterWidth : masterWidth;

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

  /// What went over the list when the window got too narrow for the pane,
  /// to take back into it when there's room again, as when an iPhone Duo is
  /// folded shut and opened again.
  Route<void>? _movedOut;

  /// Taken back from over the list, for the pane to show once it's built.
  Destination? _takenBack;

  /// Too narrow for the pane now: what it showed opens over the list.
  void _movePaneOut(double width) {
    final Destination? shown = _takenBack ?? (_paneCanPop ? _shown : null);
    _takenBack = null;
    _shown = null;
    _paneCanPop = false;
    if (shown == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final DestinationPages? pages = DestinationPages.maybeOf(context);
      if (!mounted || pages == null) {
        return;
      }
      late final Route<void> route;
      route = BackSwipePageRoute<void>(
        settings: RouteSettings(name: Destination.routeName, arguments: shown),
        builder: (_) => _MovedOut(
          listWidth: width,
          onRoom: () => _takeBack(route, shown),
          child: pages.pageFor(shown),
        ),
      );
      _movedOut = route;
      Navigator.of(context).push(route);
    });
  }

  /// There's room for the pane again: what went over the list goes back
  /// into it, unless something's been opened over it since.
  void _takeBack(Route<void> route, Destination shown) {
    if (!mounted || route != _movedOut || !route.isCurrent) {
      return;
    }
    _movedOut = null;
    Navigator.of(context).removeRoute(route);
    setState(() => _takenBack = shown);
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
          _movePaneOut(width);
          return master;
        }
        _movedOut = null;
        if (_takenBack case final Destination shown) {
          _takenBack = null;
          // The pane is built in this frame.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _show(shown);
            }
          });
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
              final double masterWidth = MasterDetail.masterWidthIn(width);
              final double listWidth = lerpDouble(width, masterWidth, t)!;
              return Stack(
                children: [
                  Positioned(
                    left: masterWidth,
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

/// A page that went over the list as the window narrowed; it says when the
/// window's wide enough for the pane again. The list it covers isn't laid
/// out meanwhile, so it can't tell; this page's width less what the list
/// lacked of it then (a sidebar beside the list, say) stands in for the
/// list's.
class _MovedOut extends StatefulWidget {
  const _MovedOut({
    required this.listWidth,
    required this.onRoom,
    required this.child,
  });

  /// How wide the list was when this went over it.
  final double listWidth;
  final VoidCallback onRoom;
  final Widget child;

  @override
  State<_MovedOut> createState() => _MovedOutState();
}

class _MovedOutState extends State<_MovedOut> {
  double? _beyondList;
  bool _told = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final double beyondList = _beyondList ??= width - widget.listWidth;
        if (!_told && width - beyondList >= MasterDetail.minWidth) {
          _told = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => widget.onRoom());
        }
        return widget.child;
      },
    );
  }
}
