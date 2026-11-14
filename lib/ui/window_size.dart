import 'dart:math';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// How much room the app's window has across, in Material's size classes:
/// a phone is [compact]; an iPad, or a tablet, is [medium] upright and
/// [expanded] or [large] on its side, and anything down to [compact] in a
/// window beside another app. Layouts go by this, never by the device.
enum WindowSize {
  compact,
  medium,
  expanded,
  large;

  static WindowSize of(BuildContext context) =>
      fromWidth(MediaQuery.sizeOf(context).width);

  static WindowSize fromWidth(double width) => width < 600
      ? compact
      : width < 840
      ? medium
      : width < 1200
      ? expanded
      : large;

  bool isAtLeast(WindowSize other) => index >= other.index;
}

/// How wide a column of text and rows gets, however wide the window: past
/// it, lines get too long to read and rows put their ends far apart.
const double kReadableWidth = 720;

/// The sides that keep [width] of content, centered, in [available].
double readableInset(double available, {double width = kReadableWidth}) =>
    max(0, (available - width) / 2);

/// [sliver], at most [width] across, in the middle of the scroll view.
class ReadableSliver extends StatelessWidget {
  const ReadableSliver({
    super.key,
    required this.sliver,
    this.width = kReadableWidth,
  });

  final Widget sliver;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (BuildContext context, SliverConstraints constraints) {
        final double side = readableInset(
          constraints.crossAxisExtent,
          width: width,
        );
        if (side == 0) {
          return sliver;
        }
        return SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: side),
          sliver: sliver,
        );
      },
    );
  }
}

/// [child] laid out as if the window were the box it's given: a pane beside
/// another, or the room beside the sidebar. Pages there size their columns,
/// grids and images by [MediaQuery.sizeOf], as in a window that size.
class PaneSize extends StatelessWidget {
  const PaneSize({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final MediaQueryData media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            size: Size(constraints.maxWidth, constraints.maxHeight),
          ),
          child: child,
        );
      },
    );
  }
}
