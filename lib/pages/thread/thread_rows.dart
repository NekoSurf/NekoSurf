import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';
import 'package:flutter_chan/services/string.dart';

/// One post in a list of nested posts.
class ThreadRow {
  const ThreadRow({
    required this.post,
    required this.path,
    required this.postIndex,
    required this.seen,
    this.replyCount = 0,
    this.ancestors = const <int>[],
    this.collapsed = false,
    this.isPreview = false,
  });

  final Post post;

  /// This place in the list, as a post can be listed in several.
  final String path;

  /// Where the post is in the thread, oldest first, whatever the row order.
  final int postIndex;

  /// How many other posts come before this one with every branch open, so that
  /// reaching a row counts the replies folded away above it as read.
  final int seen;

  /// Replies below this post, counting the replies to those replies, and a
  /// post that's there by several routes once.
  final int replyCount;

  /// The posts this one hangs under, outermost first.
  final List<int> ancestors;

  /// It's folded down to its header, with its replies.
  final bool collapsed;

  /// The post is shown in full under another post it quotes, with its replies:
  /// this is a short preview of it, and tapping moves all that here.
  final bool isPreview;

  /// The post it's listed under, or [topLevel].
  int get parent => ancestors.isEmpty ? topLevel : ancestors.last;

  /// The [parent] of a post at the top level of the list.
  static const int topLevel = -1;
}

/// Roughly how tall a post's text is, to know if it's worth repeating in full.
double _estimatedTextHeight(Post post) {
  const int charactersPerLine = 50;
  const double lineHeight = 20;
  int lines = 0;
  for (final String line in (post.com ?? '').split('<br>')) {
    lines += 1 + cleanTags(line).length ~/ charactersPerLine;
  }
  return lines * lineHeight;
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
///
/// A reply is listed under each post in [children], and at the top level if one
/// of them is the opening post. If it's short, it's simply repeated. If it has
/// replies, an image or a lot of text, it's shown in full, with its replies,
/// under the first of them or the one in [primaryParents], and as a preview
/// ([ThreadRow.isPreview]) under the others. So there's always about one row
/// per quote, however the replies branch.
///
/// A post can have several rows: each folds on its own, by the [ThreadRow.path]
/// in [collapsed].
List<ThreadRow> buildNestedRows(
  List<Post> posts, {
  required Map<int, List<Post>> children,
  Set<String> collapsed = const <String>{},
  Map<int, int> primaryParents = const <int, int>{},
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

  bool inTree(Post post) => treePosts == null || treePosts.contains(post.no);

  // Only what's listed can have a reply under it: on a replies page, a reply
  // may also quote a post from outside the branch.
  final Set<int?> listed = <int?>{
    for (final Post post in posts)
      if (inTree(post)) post.no,
  };
  final Set<int?> nested = <int?>{
    for (final MapEntry<int, List<Post>> entry in children.entries)
      if (entry.key != opId && listed.contains(entry.key))
        for (final Post reply in entry.value) reply.no,
  }..remove(opId);

  final Map<int, Set<int>> below = <int, Set<int>>{};
  Set<int> postsBelow(int? postId) {
    if (postId == null) {
      return const <int>{};
    }
    return below[postId] ??= <int>{
      for (final Post reply in repliesTo(postId))
        if (reply.no != null) ...<int>[reply.no!, ...postsBelow(reply.no)],
    };
  }

  final Map<int?, int> quoteCounts = <int?, int>{};
  for (final MapEntry<int, List<Post>> entry in children.entries) {
    if (entry.key == opId || listed.contains(entry.key)) {
      for (final Post reply in entry.value) {
        quoteCounts[reply.no] = (quoteCounts[reply.no] ?? 0) + 1;
      }
    }
  }

  // Whether a post is too much to show in full each time it's quoted.
  bool isPreviewedWhenRepeated(Post post) {
    final int quotes = quoteCounts[post.no] ?? 0;
    return quotes > 1 &&
        (repliesTo(post.no).isNotEmpty ||
            post.hasFile ||
            _estimatedTextHeight(post) > 100 * max(quotes, 3));
  }

  // Where each post is shown in full: where the list first comes to it, whether
  // or not that's folded at the moment, so folding moves nothing elsewhere.
  final Map<int, int> firstParents = <int, int>{};
  bool isPreviewUnder(int? postId, int parent) {
    final int? primary = primaryParents[postId] ?? firstParents[postId];
    return primary != null && primary != parent;
  }

  void findFirstParents(Post post, int parent) {
    final int? id = post.no;
    if (id == null) {
      return;
    }
    if (isPreviewedWhenRepeated(post)) {
      firstParents.putIfAbsent(id, () => parent);
    }
    if (isPreviewUnder(id, parent)) {
      return;
    }
    for (final Post reply in repliesTo(id)) {
      findFirstParents(reply, id);
    }
  }

  final List<ThreadRow> rows = <ThreadRow>[];
  final Set<int> seenPosts = <int>{};

  void add(Post post, List<int> ancestors) {
    final int? id = post.no;
    final String path = <int>[...ancestors, ?id].join('/');
    final bool isPreview = isPreviewUnder(
      id,
      ancestors.isEmpty ? ThreadRow.topLevel : ancestors.last,
    );
    final bool isCollapsed =
        !isPreview && id != opId && collapsed.contains(path);

    rows.add(
      ThreadRow(
        post: post,
        path: path,
        postIndex: postIndex[id] ?? 0,
        seen: seenPosts.length - (seenPosts.contains(id) ? 1 : 0),
        replyCount: id == opId ? opReplyCount : postsBelow(id).length,
        ancestors: ancestors,
        collapsed: isCollapsed,
        isPreview: isPreview,
      ),
    );
    if (id != null) {
      seenPosts.add(id);
    }

    if (isCollapsed) {
      seenPosts.addAll(postsBelow(id));
      return;
    }
    if (isPreview || id == null) {
      return;
    }
    final List<int> belowThis = <int>[...ancestors, id];
    for (final Post reply in repliesTo(id)) {
      add(reply, belowThis);
    }
  }

  final Set<int?> answersOp = <int?>{
    for (final Post reply in children[opId] ?? const <Post>[]) reply.no,
  };
  final List<Post> topLevel = <Post>[
    for (final Post post in posts)
      if (inTree(post) &&
          (!nested.contains(post.no) || answersOp.contains(post.no)))
        post,
  ];
  for (final Post post in topLevel) {
    findFirstParents(post, ThreadRow.topLevel);
  }
  for (final Post post in topLevel) {
    add(post, const <int>[]);
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
/// between the app's two accent colours.
/// A faint line in line with the text separates replies, and a slightly
/// stronger one with some room around it starts each new discussion.
class ThreadBranch extends StatelessWidget {
  const ThreadBranch({
    super.key,
    required this.ancestors,
    required this.previousDepth,
    required this.isDark,
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
