import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chan/ui/colors.dart';

/// Refreshes when the list is pulled past its top, or past its bottom with
/// [fromBottom], the same on every screen: a ring fills as you pull, the phone
/// ticks when it's full, and releasing starts [onRefresh] with a spinner until
/// it's done.
///
/// The list inside must be able to overscroll, see [pullPhysics].
class PullToRefresh extends StatefulWidget {
  const PullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.fromBottom = false,
    this.topInset,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  /// Also refreshes from pulling up past the end, for a thread, where new
  /// posts come at the bottom.
  final bool fromBottom;

  /// Where the ring appears from the top, below a header. Defaults to the top
  /// padding the screen already leaves.
  final double? topInset;

  /// Lets a list be pulled past its ends on every platform, also when it's
  /// shorter than the screen.
  static const ScrollPhysics pullPhysics = AlwaysScrollableScrollPhysics(
    parent: BouncingScrollPhysics(),
  );

  @override
  State<PullToRefresh> createState() => _PullToRefreshState();
}

class _PullToRefreshState extends State<PullToRefresh> {
  // How far past an end fills the ring.
  static const double _distance = 80;
  // Shown at least this long, so a quick refresh still reads as one.
  static const Duration _minimumSpin = Duration(milliseconds: 600);

  double _progress = 0;
  bool _atBottom = false;
  bool _armed = false;
  bool _dragging = false;
  bool _refreshing = false;

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) {
      return false;
    }
    if (_refreshing) {
      return false;
    }
    final ScrollMetrics metrics = notification.metrics;
    if (notification is ScrollUpdateNotification) {
      if (notification.dragDetails == null) {
        // Only the spring back is moving the list: the finger came up.
        if (_dragging) {
          _dragging = false;
          if (_armed) {
            _start();
          }
        }
        if (!_refreshing && !_armed) {
          _setPull(_pastEnd(metrics).clamp(0.0, 1.0), atBottom: _atBottom);
        }
        return false;
      }
      _dragging = true;
      final double above = metrics.minScrollExtent - metrics.pixels;
      final double below = widget.fromBottom
          ? metrics.pixels - metrics.maxScrollExtent
          : 0;
      _setPull(
        (max(above, below) / _distance).clamp(0.0, 1.0),
        atBottom: below > above,
      );
    } else if (notification is ScrollEndNotification) {
      _dragging = false;
      if (!_armed) {
        _setPull(0);
      }
    }
    return false;
  }

  /// How far the list is past the end the pull started from, from 0 to 1.
  double _pastEnd(ScrollMetrics metrics) {
    final double past = _atBottom
        ? metrics.pixels - metrics.maxScrollExtent
        : metrics.minScrollExtent - metrics.pixels;
    return past / _distance;
  }

  void _setPull(double progress, {bool atBottom = false}) {
    if (progress >= 1 && !_armed) {
      _armed = true;
      HapticFeedback.lightImpact();
    } else if (progress < 1) {
      _armed = false;
    }
    if (progress == _progress && (progress == 0 || atBottom == _atBottom)) {
      return;
    }
    setState(() {
      _progress = progress;
      if (progress > 0) {
        _atBottom = atBottom;
      }
    });
  }

  Future<void> _start() async {
    _armed = false;
    HapticFeedback.mediumImpact();
    setState(() {
      _refreshing = true;
      _progress = 1;
    });
    final DateTime started = DateTime.now();
    try {
      await widget.onRefresh();
    } catch (_) {
      // Whatever went wrong is the screen's to say.
    }
    final Duration left = _minimumSpin - DateTime.now().difference(started);
    if (left > Duration.zero) {
      await Future<void>.delayed(left);
    }
    if (mounted) {
      setState(() {
        _refreshing = false;
        _progress = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final double top = widget.topInset ?? MediaQuery.paddingOf(context).top;
    final double bottom = MediaQuery.paddingOf(context).bottom;
    final bool isDark = context.isDark;

    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: widget.child,
        ),
        Positioned(
          top: _atBottom ? null : top + 8,
          bottom: _atBottom ? bottom + 16 : null,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: _Ring(
                progress: _progress,
                spinning: _refreshing,
                fromBottom: _atBottom,
                isDark: isDark,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({
    required this.progress,
    required this.spinning,
    required this.fromBottom,
    required this.isDark,
  });

  final double progress;
  final bool spinning;
  final bool fromBottom;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final double shown = Curves.easeOut.transform(progress);
    final double slide = (1 - shown) * 24 * (fromBottom ? 1 : -1);

    return Semantics(
      label: spinning ? 'Refreshing' : null,
      child: Opacity(
        opacity: shown,
        child: Transform.translate(
          offset: Offset(0, slide),
          child: Container(
            width: 40,
            height: 40,
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: DashColors.card(isDark),
              shape: BoxShape.circle,
              border: Border.all(color: DashColors.border(isDark)),
              boxShadow: DashColors.cardShadow(isDark),
            ),
            child: CircularProgressIndicator(
              value: spinning ? null : progress,
              strokeWidth: 3,
              strokeCap: StrokeCap.round,
              color: DashColors.accent,
              backgroundColor: DashColors.border(isDark),
            ),
          ),
        ),
      ),
    );
  }
}
