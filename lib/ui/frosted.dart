import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/ui/colors.dart';

/// A surface that floats over the page: see-through, with what's behind it
/// blurred.
class Frosted extends StatelessWidget {
  const Frosted({
    super.key,
    required this.radius,
    required this.color,
    required this.child,
    this.borderColor,
    this.blur = 24,
    this.padding,
    this.fadesWithRoute = false,
    this.fade,
  });

  /// The tint of a popup, solid enough to read over anything.
  static Color panel(BuildContext context) =>
      DashColors.card(context).withValues(alpha: context.isDark ? 0.72 : 0.85);

  final double radius;
  final Color color;
  final Color? borderColor;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final Widget child;

  /// Comes and goes with the popup it's in. A blur can't see through a fade
  /// around it, so the page would show sharp until the fade ended: this fades
  /// the blur and the tint instead.
  final bool fadesWithRoute;

  /// Like [fadesWithRoute], for something that isn't a route: fades the blur
  /// and the tint along with this animation.
  final Animation<double>? fade;

  Widget _surface(double shown) {
    final Color? border = borderColor;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur * shown, sigmaY: blur * shown),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color.withValues(alpha: color.a * shown),
            borderRadius: BorderRadius.circular(radius),
            border: border == null
                ? null
                : Border.all(color: border.withValues(alpha: border.a * shown)),
          ),
          child: Opacity(opacity: shown, child: child),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Animation<double>? route =
        fade ?? (fadesWithRoute ? ModalRoute.of(context)?.animation : null);
    if (route == null) {
      return _surface(1);
    }

    return AnimatedBuilder(
      animation: route,
      builder: (BuildContext context, _) =>
          _surface(Curves.easeOutCubic.transform(route.value)),
    );
  }
}
