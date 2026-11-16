import 'package:flutter_chan/history/thread_memory.dart';
import 'package:flutter_chan/thread/thread_rows.dart';

/// Where to open a thread to carry on from where [memory] says the reader was:
/// a row, and how far down the screen it starts.
///
/// The thread is listed as it was left (see [ThreadMemory.batches]), so that's
/// the row remembered. Only once everything at the bottom has been read and
/// something new has come is it put in the thread with the rest: then the
/// reader opens at the first of the new posts, or the end if there are none to
/// show. A post that's gone, deleted or hidden, opens at the one nearest to
/// it.
///
/// Null when there's nothing to go back to: the thread starts at the top.
({int row, double alignment})? resumePlace(
  ThreadMemory? memory,
  List<ThreadRow> rows, {
  required double belowHeader,
}) {
  final String? path = memory?.topPath;
  final int? post = memory?.topPost;
  if (rows.isEmpty || path == null && post == null) {
    return null;
  }
  final double alignment = memory?.topAlignment ?? belowHeader;

  final int byPath = rows.indexWhere((ThreadRow row) => row.path == path);
  if (byPath >= 0) {
    return (row: byPath, alignment: alignment);
  }

  // What was at the bottom is in the thread now, and only what's new is
  // below it.
  final List<int> batches = memory?.batches ?? const <int>[];
  if (path != null && isLatePath(path) && batches.length <= 1) {
    final int read = batches.firstOrNull ?? post ?? 0;
    final int first = rows.indexWhere(
      (ThreadRow row) => !row.isPreview && !row.hidden && row.post.no > read,
    );
    if (first < 0) {
      // The list stops at its end, whatever's asked for.
      return (row: rows.length - 1, alignment: 0);
    }
    // With the post it answers, if that's shown above it.
    final bool withContext = first > 0 && rows[first - 1].isContext;
    return (row: withContext ? first - 1 : first, alignment: belowHeader);
  }

  // Posts are numbered in the order they came.
  int? before;
  int? after;
  for (int index = 0; index < rows.length; index++) {
    final ThreadRow row = rows[index];
    if (row.isPreview) {
      continue;
    }
    final int no = row.post.no;
    if (no == post) {
      return (row: index, alignment: alignment);
    }
    if (post == null) {
      continue;
    }
    if (no < post) {
      if (before == null || no > rows[before].post.no) {
        before = index;
      }
    } else if (after == null || no < rows[after].post.no) {
      after = index;
    }
  }
  final int? near = before ?? after;
  return near == null ? null : (row: near, alignment: belowHeader);
}
