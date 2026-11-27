import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_chan/ui/holidays.dart';

/// A holiday's snow, leaves or confetti drifting down over the app, lightly
/// and few at a time, fading out toward its bottom so what's below reads.
/// It takes no touches. Still, one frame of it, with reduced motion on.
///
/// One painter for all of them, repainting only itself: no widget per flake.
class HolidayFall extends StatefulWidget {
  const HolidayFall({super.key, required this.holiday});

  final Holiday holiday;

  /// How many are falling at once.
  static const int count = 26;

  @override
  State<HolidayFall> createState() => _HolidayFallState();
}

class _HolidayFallState extends State<HolidayFall>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final ValueNotifier<double> _seconds = ValueNotifier<double>(0);
  late List<_Flake> _flakes = _scatter(widget.holiday);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool still = MediaQuery.disableAnimationsOf(context);
    if (still && _ticker.isActive) {
      _ticker.stop();
    } else if (!still && !_ticker.isActive) {
      unawaited(_ticker.start());
    }
  }

  @override
  void didUpdateWidget(HolidayFall oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.holiday != widget.holiday) {
      _flakes = _scatter(widget.holiday);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _seconds.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    _seconds.value = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
  }

  static List<_Flake> _scatter(Holiday holiday) {
    // The same each time, so a page doesn't reshuffle as it's rebuilt.
    final Random random = Random(holiday.index);
    double between(double low, double high) =>
        low + random.nextDouble() * (high - low);
    return [
      for (int i = 0; i < HolidayFall.count; i++)
        _Flake(
          x: random.nextDouble(),
          start: random.nextDouble(),
          // Screen heights a second: about 12 to 25 seconds to cross it.
          speed: between(0.04, 0.08),
          size: between(3, 7),
          sway: between(8, 22),
          swaySpeed: between(0.4, 1.0),
          spin: between(-1.6, 1.6),
          color: random.nextInt(1 << 16),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: _FallPainter(
              flakes: _flakes,
              shape: widget.holiday.fall,
              colors: widget.holiday.colorsFor(
                CupertinoTheme.brightnessOf(context),
              ),
              seconds: _seconds,
            ),
          ),
        ),
      ),
    );
  }
}

class _Flake {
  const _Flake({
    required this.x,
    required this.start,
    required this.speed,
    required this.size,
    required this.sway,
    required this.swaySpeed,
    required this.spin,
    required this.color,
  });

  /// Across the page, 0 to 1, before swaying.
  final double x;

  /// Where on its way down it is at first, 0 to 1.
  final double start;
  final double speed;
  final double size;

  /// How far it sways either way, in points.
  final double sway;
  final double swaySpeed;

  /// Turns a second (leaves, confetti, petals tumble).
  final double spin;
  final int color;
}

class _FallPainter extends CustomPainter {
  _FallPainter({
    required this.flakes,
    required this.shape,
    required this.colors,
    required this.seconds,
  }) : super(repaint: seconds);

  final List<_Flake> flakes;
  final HolidayFallShape shape;
  final List<Color> colors;
  final ValueNotifier<double> seconds;

  // Above the page and below it, so flakes come in and leave out of view.
  static const double _margin = 0.08;

  @override
  void paint(Canvas canvas, Size size) {
    final double t = seconds.value;
    final Paint paint = Paint()..isAntiAlias = true;
    for (final _Flake flake in flakes) {
      final double way = (flake.start + t * flake.speed) % 1;
      final double y = (way * (1 + 2 * _margin) - _margin) * size.height;
      final double x =
          flake.x * size.width +
          sin(t * flake.swaySpeed + flake.start * 2 * pi) * flake.sway;
      // Full at the top, gone by three quarters of the way down.
      final double fade = (1 - (y / size.height) / 0.75).clamp(0, 1);
      if (fade <= 0) {
        continue;
      }
      paint.color = colors[flake.color % colors.length].withValues(
        alpha: 0.75 * fade,
      );
      canvas.save();
      canvas.translate(x, y);
      _draw(canvas, paint, flake, t);
      canvas.restore();
    }
  }

  void _draw(Canvas canvas, Paint paint, _Flake flake, double t) {
    final double s = flake.size;
    final double angle = flake.start * 2 * pi + t * flake.spin;
    switch (shape) {
      case HolidayFallShape.snow:
        canvas.drawCircle(Offset.zero, s * 0.55, paint);
      case HolidayFallShape.confetti:
        canvas.rotate(angle);
        // Turning over: narrows as its edge comes round.
        canvas.scale(cos(angle * 1.7).abs() * 0.8 + 0.2, 1);
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: s, height: s * 1.8),
          paint,
        );
      case HolidayFallShape.leaf || HolidayFallShape.petal:
        final bool leaf = shape == HolidayFallShape.leaf;
        canvas.rotate(angle);
        canvas.scale(cos(angle * 1.3).abs() * 0.7 + 0.3, 1);
        final double length = s * (leaf ? 2.4 : 1.7);
        final double width = s * (leaf ? 1.3 : 1.1);
        final Path path = Path()
          ..moveTo(0, -length / 2)
          ..quadraticBezierTo(width, 0, 0, length / 2)
          ..quadraticBezierTo(-width, 0, 0, -length / 2);
        canvas.drawPath(path, paint);
      case HolidayFallShape.heart:
        canvas.rotate(sin(angle) * 0.35);
        canvas.drawPath(_heart(s * 1.5), paint);
      case HolidayFallShape.clover:
        canvas.rotate(angle * 0.5);
        final double r = s * 0.48;
        for (int i = 0; i < 3; i++) {
          final double a = i * 2 * pi / 3 - pi / 2;
          canvas.drawCircle(Offset(cos(a), sin(a)) * r, r, paint);
        }
    }
  }

  static Path _heart(double size) {
    final double h = size / 2;
    return Path()
      ..moveTo(0, h * 0.9)
      ..cubicTo(-h * 1.6, -h * 0.1, -h * 0.6, -h * 1.3, 0, -h * 0.45)
      ..cubicTo(h * 0.6, -h * 1.3, h * 1.6, -h * 0.1, 0, h * 0.9)
      ..close();
  }

  @override
  bool shouldRepaint(_FallPainter oldDelegate) =>
      oldDelegate.flakes != flakes ||
      oldDelegate.shape != shape ||
      oldDelegate.colors != colors;
}
