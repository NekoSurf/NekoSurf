import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// The iOS slide with a shorter duration; the stock Android transitions run
/// 450ms and block touches meanwhile, which delayed zooming in the media viewer.
class FastCupertinoTransitionsBuilder extends PageTransitionsBuilder {
  const FastCupertinoTransitionsBuilder();

  static const _delegate = CupertinoPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 250);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 220);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _delegate.buildTransitions<T>(
      route,
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}
