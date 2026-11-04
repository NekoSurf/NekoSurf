import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';

/// One post in a list of nested posts.
class ThreadRow {
  const ThreadRow({
    required this.post,
    required this.postIndex,
    required this.seen,
    this.replyCount = 0,
    this.ancestors = const <int>[],
    this.collapsed = false,
  });

  final Post post;

  /// Where the post is in the thread, oldest first, whatever the row order.
  final int postIndex;

  /// How many posts come before this one with every branch open, so that
  /// reaching a row counts the replies folded away above it as read.
  final int seen;

  /// Replies below this post, counting the replies to those replies.
  final int replyCount;

  /// The posts this one hangs under, outermost first.
  final List<int> ancestors;

  /// It's folded down to its header, with its replies.
  final bool collapsed;
}

/// The thread with each reply under the post it answers, like comments.
///
/// [children] says which posts answer which (see `buildReplyChildrenIndex`).
/// Replies to the opening post stay at the top level: nearly every post in a
/// thread is one, and indenting them all would only waste width.
///
/// Posts not in [treePosts] go flat at the bottom, oldest first. That's how
/// posts arriving while reading stay out of the way: fitting them in between
/// the others would move the list under the reader.
///
/// [positions] says where posts are in the thread, for when [posts] is only a
/// part of it. How deep replies go is only limited by what people post.
List<ThreadRow> buildNestedRows(
  List<Post> posts, {
  required Map<int, List<Post>> children,
  Set<int> collapsed = const <int>{},
  Set<int>? treePosts,
  int opReplyCount = 0,
  Map<int, int>? positions,
}) {
  if (posts.isEmpty) {
    return const <ThreadRow>[];
  }

  final int? opId = posts.first.no;
  final Map<int, int> postIndex =
      positions ??
      <int, int>{
        for (int index = 0; index < posts.length; index++)
          if (posts[index].no != null) posts[index].no!: index,
      };

  List<Post> repliesTo(int? postId) => postId == null || postId == opId
      ? const <Post>[]
      : children[postId] ?? const <Post>[];

  final Set<int?> nested = <int?>{
    for (final MapEntry<int, List<Post>> entry in children.entries)
      if (entry.key != opId)
        for (final Post reply in entry.value) reply.no,
  }..remove(opId);

  final Map<int, int> replyCounts = <int, int>{};
  int countReplies(int? postId) {
    if (postId == null) {
      return 0;
    }
    return replyCounts[postId] ??= repliesTo(postId).fold<int>(
      0,
      (int total, Post reply) => total + 1 + countReplies(reply.no),
    );
  }

  final List<ThreadRow> rows = <ThreadRow>[];
  int seen = 0;

  void add(Post post, List<int> ancestors) {
    final int? id = post.no;
    final int replyCount = id == opId ? opReplyCount : countReplies(id);
    final bool isCollapsed = id != opId && collapsed.contains(id);

    rows.add(
      ThreadRow(
        post: post,
        postIndex: postIndex[id] ?? 0,
        seen: seen,
        replyCount: replyCount,
        ancestors: ancestors,
        collapsed: isCollapsed,
      ),
    );
    seen++;

    if (isCollapsed) {
      seen += replyCount;
      return;
    }
    final List<Post> replies = repliesTo(id);
    if (replies.isNotEmpty) {
      final List<int> below = <int>[...ancestors, id!];
      for (final Post reply in replies) {
        add(reply, below);
      }
    }
  }

  bool inTree(Post post) => treePosts == null || treePosts.contains(post.no);

  for (final Post post in posts) {
    if (inTree(post) && !nested.contains(post.no)) {
      add(post, const <int>[]);
    }
  }
  for (final Post post in posts) {
    if (!inTree(post)) {
      add(post, const <int>[]);
    }
  }

  return rows;
}

/// How a post is named in a thread of [allPosts]: `OP`, its place like `#38`,
/// or its number if it isn't in the thread.
String postLabel(int post, List<Post> allPosts) {
  final int index = allPosts.indexWhere((p) => p.no == post);
  if (index == 0) {
    return 'OP';
  }
  return index > 0 ? '#$index' : '$post';
}

/// A row of a nested thread, directly on the page's background. A reply is
/// indented for how deep it is, with a thin line down its side, alternating
/// between the app's two accent colours. Tapping the line folds the post it
/// answers.
/// A faint line in line with the text separates replies, and a slightly
/// stronger one with some room around it starts each new discussion.
class ThreadBranch extends StatelessWidget {
  const ThreadBranch({
    super.key,
    required this.ancestors,
    required this.previousDepth,
    required this.isDark,
    required this.onTapBar,
    required this.child,
  });

  static const double barWidth = 1.5;

  /// Room above a post that starts a new discussion.
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
  final bool isDark;
  final ValueChanged<int> onTapBar;
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
          // Wider than the line, which alone would be hard to hit.
          Positioned(
            left: 0,
            width: indent + barWidth + 6,
            top: 0,
            bottom: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => onTapBar(ancestors.last),
            ),
          ),
        ],
        if (previous != null)
          Positioned(
            // From the shallower of the two rows it separates.
            left:
                indentFor(min(previous, depth)) +
                (min(previous, depth) == 0 ? 0 : barWidth) +
                _textInset,
            right: _textInset,
            top: 0,
            height: 0.5,
            child: ColoredBox(
              color: DashColors.muted(
                isDark,
              ).withValues(alpha: startsDiscussion ? 0.4 : 0.18),
            ),
          ),
      ],
    );
  }
}
