import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_chan/ui/colors.dart';

/// A row of a nested thread, directly on the page's background. A reply is
/// indented for how deep it is, with a thin line down its side, alternating
/// between the app's two accent colours.
/// A faint line in line with the text separates replies, and a slightly
/// stronger one with some room around it starts each new discussion.
class ThreadBranch extends StatelessWidget {
  const ThreadBranch({
    super.key,
    required this.ancestors,
    required this.previousDepth,
    required this.child,
  });

  static const double barWidth = 1.5;

  static const double discussionGap = 6;

  // The room a post leaves on its left, which the lines keep to.
  static const double _textInset = 14;

  /// Each level moves less than the one before, so that a long back-and-forth
  /// keeps a readable width however deep it goes.
  static double indentFor(int depth) =>
      depth == 0 ? 0 : 13 * pow(depth, 0.6).toDouble();

  static Color colorFor(int depth) =>
      (depth.isOdd ? DashColors.accent : DashColors.accent2).withValues(
        alpha: 0.55,
      );

  final List<int> ancestors;

  /// The depth of the row above, whose line this row draws; null for the first.
  final int? previousDepth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final int depth = ancestors.length;
    final double indent = indentFor(depth);
    final int? previous = previousDepth;
    final bool startsDiscussion = depth == 0 && previous != null;

    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: depth == 0 ? 0 : indent + barWidth,
            top: startsDiscussion ? discussionGap : 0,
          ),
          child: child,
        ),
        if (depth > 0) ...[
          Positioned(
            left: indent,
            width: barWidth,
            top: 0,
            bottom: 0,
            child: ColoredBox(color: colorFor(depth)),
          ),
        ],
        if (previous != null)
          Positioned(
            left:
                indentFor(min(previous, depth)) +
                (min(previous, depth) == 0 ? 0 : barWidth) +
                _textInset,
            right: _textInset,
            top: 0,
            height: 0.5,
            child: ColoredBox(
              color: DashColors.muted(
                context.isDark,
              ).withValues(alpha: startsDiscussion ? 0.4 : 0.18),
            ),
          ),
      ],
    );
  }
}
