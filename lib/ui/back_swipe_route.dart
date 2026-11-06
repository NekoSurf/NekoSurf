import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

/// A page that goes back when swiped to the right from anywhere on it, not
/// just from the screen's edge. It looks like the edge swipe, which still
/// works, and settles from the finger's speed when let go.
///
/// Drags that something on the page wants come first, so a video's scrubbing
/// keeps working. A page that needs sideways drags for itself, like the
/// fullscreen viewer, should stay a plain route.
class BackSwipePageRoute<T> extends MaterialPageRoute<T> {
  BackSwipePageRoute({required super.builder, super.settings});

  static const double _flingVelocity = 1; // Screen widths per second.

  // Let go, the page carries on at the finger's speed and eases to a stop. A
  // fixed curve ignores that speed, so the page jumps ahead on release.
  static final SpringDescription _settleSpring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 300);

  // Stops at under a point from the end, off screen by then, instead of
  // keeping the page around for a tail nobody can see.
  static const Tolerance _settleTolerance = Tolerance(
    distance: 0.002,
    velocity: 0.05,
  );

  /// The navigator told of the swipe; told again when it's settled. Kept, as
  /// the route forgets its navigator once it's gone.
  NavigatorState? _swipingOn;

  void _swipeStart() {
    final NavigatorState? navigator = this.navigator;
    if (_swipingOn != null || navigator == null || !isCurrent) {
      return;
    }
    _swipingOn = navigator..didStartUserGesture();
  }

  /// [delta] is the finger's movement as a fraction of the page's width.
  void _swipeUpdate(double delta) {
    if (_swipingOn != null && isCurrent) {
      controller!.value -= delta;
    }
  }

  /// [velocity] is in screen widths per second, to the right.
  void _swipeEnd(double velocity) {
    final NavigatorState? navigator = _swipingOn;
    if (navigator == null) {
      return;
    }
    final AnimationController controller = this.controller!;

    final bool stay;
    if (!isCurrent) {
      // Something else navigated meanwhile, which decides it.
      stay = isActive;
    } else if (velocity.abs() >= _flingVelocity) {
      stay = velocity < 0;
    } else {
      stay = controller.value > 0.5;
    }

    // The page moves right as the animation's value falls.
    SpringSimulation settleTo(double end) => SpringSimulation(
      _settleSpring,
      controller.value,
      end,
      -velocity,
      tolerance: _settleTolerance,
      snapToEnd: true,
    );

    if (stay) {
      controller.animateWith(settleTo(1));
    } else {
      if (isCurrent) {
        navigator.pop();
      }
      if (controller.isAnimating) {
        controller.animateBackWith(settleTo(0));
      }
    }

    // The transition follows the value directly until the navigator hears
    // it's over, so it must not take on a curve while settling.
    if (controller.isAnimating) {
      late final AnimationStatusListener listener;
      listener = (AnimationStatus status) {
        if (!status.isAnimating) {
          controller.removeStatusListener(listener);
          _swipeDone(navigator);
        }
      };
      controller.addStatusListener(listener);
    } else {
      _swipeDone(navigator);
    }
  }

  void _swipeDone(NavigatorState navigator) {
    if (_swipingOn == navigator) {
      _swipingOn = null;
      navigator.didStopUserGesture();
    }
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _BackSwipeDetector(
      route: this,
      child: super.buildTransitions(
        context,
        animation,
        secondaryAnimation,
        child,
      ),
    );
  }

  @override
  void dispose() {
    final NavigatorState? navigator = _swipingOn;
    if (navigator != null) {
      _swipeDone(navigator);
    }
    super.dispose();
  }
}

class _BackSwipeDetector extends StatefulWidget {
  const _BackSwipeDetector({required this.route, required this.child});

  final BackSwipePageRoute<dynamic> route;
  final Widget child;

  @override
  State<_BackSwipeDetector> createState() => _BackSwipeDetectorState();
}

class _BackSwipeDetectorState extends State<_BackSwipeDetector> {
  late final _RightwardDragRecognizer _recognizer;

  int? _addedFirst;

  double get _width => context.size!.width;

  void _addPointerFirst(PointerDownEvent event) {
    if (widget.route.popGestureEnabled) {
      _addedFirst = event.pointer;
      _recognizer.addPointer(event);
    }
  }

  @override
  void initState() {
    super.initState();
    _recognizer = _RightwardDragRecognizer(debugOwner: this)
      ..onStart = ((_) => widget.route._swipeStart())
      ..onUpdate = ((DragUpdateDetails details) {
        widget.route._swipeUpdate(details.primaryDelta! / _width);
      })
      ..onEnd = ((DragEndDetails details) {
        widget.route._swipeEnd((details.primaryVelocity ?? 0) / _width);
      })
      ..onCancel = (() => widget.route._swipeEnd(0));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _recognizer.gestureSettings = MediaQuery.maybeGestureSettingsOf(context);
  }

  @override
  void dispose() {
    _recognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Around the page rather than on top of it: pointers reach what's on the
    // page first, so a drag it can also use goes to it.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (PointerDownEvent event) {
        if (event.pointer != _addedFirst && widget.route.popGestureEnabled) {
          _recognizer.addPointer(event);
        }
      },
      child: widget.child,
    );
  }
}

/// Goes inside a [Slidable] row whose actions open to the left. Such a row
/// claims drags to the right too, doing nothing with them, which would stop
/// the back swipe on most of a list. While it's closed the back swipe goes
/// first, and only takes what goes right; open, a drag to the right closes it.
class SlidableBackSwipe extends StatelessWidget {
  const SlidableBackSwipe({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (PointerDownEvent event) {
        if ((Slidable.of(context)?.ratio ?? 0) == 0) {
          context
              .findAncestorStateOfType<_BackSwipeDetectorState>()
              ?._addPointerFirst(event);
        }
      },
      child: child,
    );
  }
}

class _RightwardDragRecognizer extends HorizontalDragGestureRecognizer {
  _RightwardDragRecognizer({super.debugOwner})
    : super(
        supportedDevices: const <PointerDeviceKind>{PointerDeviceKind.touch},
      );

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    return globalDistanceMoved >
        computeHitSlop(pointerDeviceKind, gestureSettings);
  }
}
