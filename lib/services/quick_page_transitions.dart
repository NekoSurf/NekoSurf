import 'package:flutter/material.dart';

/// Android's default page transition lasts 450ms and blocks touches meanwhile,
/// which made zooming in the media viewer wait for the animation to finish.
class QuickPageTransitionsBuilder extends PageTransitionsBuilder {
  const QuickPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 180);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 150);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
