import 'package:flutter/widgets.dart';
import 'package:flutter_chan/saved/saved_attachment.dart';
import 'package:intl/intl.dart';

/// Saved files from one stretch of time, under its title, like "Today".
class SavedGroup {
  const SavedGroup(this.title, this.items);

  final String title;
  final List<SavedAttachment> items;
}

/// [items], in the order given, in runs of the same [savedGroupTitle].
List<SavedGroup> groupByDay(List<SavedAttachment> items, DateTime now) {
  final List<SavedGroup> groups = <SavedGroup>[];
  for (final SavedAttachment a in items) {
    final String title = savedGroupTitle(
      DateTime.fromMillisecondsSinceEpoch(a.sortTime),
      now,
    );
    if (groups.isNotEmpty && groups.last.title == title) {
      groups.last.items.add(a);
    } else {
      groups.add(SavedGroup(title, <SavedAttachment>[a]));
    }
  }
  return groups;
}

/// Which stretch [saved] is in, seen [now]: "Today", "Yesterday", "This
/// week" (the six days before), "This month", then the month, with its year
/// if it isn't this one.
String savedGroupTitle(DateTime saved, DateTime now) {
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime day = DateTime(saved.year, saved.month, saved.day);
  // Rounded, as a day around a clock change isn't 24 hours.
  final int daysAgo = (today.difference(day).inHours / 24).round();
  if (daysAgo <= 0) {
    return 'Today';
  }
  if (daysAgo == 1) {
    return 'Yesterday';
  }
  if (daysAgo < 7) {
    return 'This week';
  }
  if (saved.year == now.year && saved.month == now.month) {
    return 'This month';
  }
  return saved.year == now.year
      ? DateFormat.MMMM().format(saved)
      : DateFormat.yMMMM().format(saved);
}

/// [items] dealt into [count] columns, in order, each to the one that's
/// shortest so far, as a masonry grid does: by [ratio], width over height,
/// as the columns are all as wide.
List<List<SavedAttachment>> intoColumns(
  List<SavedAttachment> items,
  int count,
  double Function(SavedAttachment) ratio,
) {
  final List<List<SavedAttachment>> columns = [
    for (int i = 0; i < count; i++) <SavedAttachment>[],
  ];
  final List<double> heights = List<double>.filled(count, 0);
  for (final SavedAttachment a in items) {
    int shortest = 0;
    for (int i = 1; i < count; i++) {
      // Within a hair counts as level, so it goes left to right.
      if (heights[i] < heights[shortest] - 0.01) {
        shortest = i;
      }
    }
    columns[shortest].add(a);
    // And the gap below, as a share of the width: a column on a phone is
    // about 180 wide, the gap about 10.
    heights[shortest] += 1 / ratio(a) + 10 / 180;
  }
  return columns;
}

/// A stretch's files as columns side by side, each its own lazy list. Not a
/// SliverMasonryGrid: with more than one of those in a list, scrolling jumps
/// back once the first is out of sight, and the end can't be reached.
class SavedColumns extends StatelessWidget {
  const SavedColumns({
    super.key,
    required this.columns,
    required this.tile,
    required this.gap,
  });

  final List<List<SavedAttachment>> columns;
  final Widget Function(SavedAttachment) tile;

  /// Between the columns, and between the files in one.
  final double gap;

  @override
  Widget build(BuildContext context) {
    return SliverCrossAxisGroup(
      slivers: [
        for (int i = 0; i < columns.length; i++) ...[
          if (i > 0)
            SliverConstrainedCrossAxis(
              maxExtent: gap,
              sliver: const SliverToBoxAdapter(),
            ),
          SliverList.separated(
            itemCount: columns[i].length,
            separatorBuilder: (_, _) => SizedBox(height: gap),
            itemBuilder: (context, j) => tile(columns[i][j]),
          ),
        ],
      ],
    );
  }
}
