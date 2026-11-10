import 'package:flutter/material.dart';
import 'package:flutter_chan/history/watched_posts_model.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:provider/provider.dart';

/// Builds with how many of [thread]'s [replies] are new.
///
/// Read positions change on every scroll in a thread; this only rebuilds when
/// this thread's own count changes.
class NewRepliesCount extends StatelessWidget {
  const NewRepliesCount({
    super.key,
    required this.thread,
    required this.replies,
    required this.builder,
  });

  final int thread;

  /// Null while they're unknown, which counts as none new.
  final int? replies;
  final Widget Function(BuildContext context, int newReplies) builder;

  @override
  Widget build(BuildContext context) {
    final int? known = replies;
    return Selector<WatchedPostsProvider, int>(
      selector: (_, watched) =>
          known == null ? 0 : watched.newReplies(thread, known) ?? 0,
      builder: (context, newReplies, _) => builder(context, newReplies),
    );
  }
}

class NewRepliesBadge extends StatelessWidget {
  const NewRepliesBadge({super.key, required this.count, this.short = false});

  final int count;

  /// Only the number, where there's little room.
  final bool short;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.accent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        short ? '+$count' : '+$count new',
        semanticsLabel: '$count new',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Colors.black,
        ),
      ),
    );
  }
}
