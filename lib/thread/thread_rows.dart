import 'dart:math';

import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/chan/post_text.dart';

class ThreadRow {
  const ThreadRow({
    required this.post,
    required this.path,
    required this.postIndex,
    this.replyCount = 0,
    this.ancestors = const <int>[],
    this.collapsed = false,
    this.isPreview = false,
    this.hidden = false,
    this.newReplies = 0,
    this.isContext = false,
    this.inFullAt,
  });

  final Post post;

  /// This place in the list, as a post can be listed in several.
  final String path;

  /// Where the post is in the thread, oldest first, whatever the row order.
  final int postIndex;

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

  /// The post is hidden: it's one line saying so, with its replies folded away
  /// below it.
  final bool hidden;

  /// How many unseen posts are hidden below it, while it's folded, hidden or a
  /// preview.
  final int newReplies;

  /// A preview of the post a reply answers, above the reply at the bottom,
  /// where a reply that came while the reader was away is listed: tapping it
  /// goes to that post in the thread, rather than bringing it here.
  final bool isContext;

  /// Where tapping this preview shows the post in full, if not under its
  /// [parent]: [bottom] for a reply that came while the reader was away.
  final int? inFullAt;

  int get parent => ancestors.isEmpty ? topLevel : ancestors.last;

  /// The [parent] of a post at the top level of the list.
  static const int topLevel = -1;

  /// Where a reply that came while the reader was away is shown in full, in
  /// `primaryParents`: at the bottom, rather than under a post.
  static const int bottom = -2;
}

double _estimatedTextHeight(Post post) {
  const int charactersPerLine = 50;
  const double lineHeight = 20;
  int lines = 0;
  for (final String line in (post.com ?? '').split('<br>')) {
    lines += 1 + plainText(line).length ~/ charactersPerLine;
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
/// in [collapsed]. [unseen] are the posts to count as new when hidden.
///
/// Posts in [hidden] are a line saying so, with their replies folded away; the
/// opening post never is.
///
/// Replies in [newAtOpen] to posts the reader had already seen, which came
/// while they were away, aren't fitted in among what they've read: they're at
/// the bottom with the new posts, oldest first, each under a preview of the
/// post it answers ([ThreadRow.isContext]), with their own replies below.
/// Under that post in the thread, each is a preview too, which shows it in
/// full there when tapped, as other previews do; the one at the bottom is a
/// preview then, until it's tapped ([ThreadRow.bottom] in [primaryParents]).
/// A folded post still counts them as new.
List<ThreadRow> buildNestedRows(
  List<Post> posts, {
  required Map<int, List<Post>> children,
  Set<String> collapsed = const <String>{},
  Set<int> hidden = const <int>{},
  Map<int, int> primaryParents = const <int, int>{},
  Set<int> unseen = const <int>{},
  Set<int> newAtOpen = const <int>{},
  Set<int>? treePosts,
  int opReplyCount = 0,
  Map<int, int>? positions,
}) {
  if (posts.isEmpty) {
    return const <ThreadRow>[];
  }

  final int opId = posts.first.no;
  final Map<int, int> postIndex =
      positions ??
      <int, int>{
        for (int index = 0; index < posts.length; index++)
          posts[index].no: index,
      };

  List<Post> repliesTo(int postId) =>
      postId == opId ? const <Post>[] : children[postId] ?? const <Post>[];

  bool inTree(Post post) => treePosts == null || treePosts.contains(post.no);

  // Only what's listed can have a reply under it: on a replies page, a reply
  // may also quote a post from outside the branch.
  final Set<int> listed = <int>{
    for (final Post post in posts)
      if (inTree(post)) post.no,
  };
  final Set<int> nested = <int>{
    for (final MapEntry<int, List<Post>> entry in children.entries)
      if (entry.key != opId && listed.contains(entry.key))
        for (final Post reply in entry.value) reply.no,
  }..remove(opId);

  final Set<int> answersOp = <int>{
    for (final Post reply in children[opId] ?? const <Post>[]) reply.no,
  };

  // The posts each listed reply answers, other than the opening post.
  final Map<int, List<int>> parentsOf = <int, List<int>>{};
  for (final MapEntry<int, List<Post>> entry in children.entries) {
    if (entry.key != opId && listed.contains(entry.key)) {
      for (final Post reply in entry.value) {
        (parentsOf[reply.no] ??= <int>[]).add(entry.key);
      }
    }
  }

  // Replies that came while the reader was away, to posts they'd seen: each
  // with the post it's listed under at the bottom, the oldest it answers.
  final Map<int, int> late = <int, int>{
    for (final int id in newAtOpen)
      if (listed.contains(id) &&
          !answersOp.contains(id) &&
          parentsOf[id] != null &&
          !parentsOf[id]!.any(newAtOpen.contains))
        id: parentsOf[id]!.reduce(
          (int a, int b) => (postIndex[a] ?? 0) <= (postIndex[b] ?? 0) ? a : b,
        ),
  };

  final Map<int, Set<int>> below = <int, Set<int>>{};
  Set<int> postsBelow(int postId) {
    return below[postId] ??= <int>{
      for (final Post reply in repliesTo(postId)) ...<int>[
        reply.no,
        ...postsBelow(reply.no),
      ],
    };
  }

  final Map<int, int> quoteCounts = <int, int>{};
  for (final MapEntry<int, List<Post>> entry in children.entries) {
    if (entry.key == opId || listed.contains(entry.key)) {
      for (final Post reply in entry.value) {
        quoteCounts[reply.no] = (quoteCounts[reply.no] ?? 0) + 1;
      }
    }
  }

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
  bool isPreviewUnder(int postId, int parent) {
    int? primary = primaryParents[postId];
    // From a visit it came during; it's in the thread like any other now.
    if (primary == ThreadRow.bottom && !late.containsKey(postId)) {
      primary = null;
    }
    primary ??= firstParents[postId];
    return primary != null && primary != parent;
  }

  /// A late reply shown in full at the bottom, as it is till it's tapped
  /// in the thread.
  bool atBottom(int postId) {
    final int? primary = primaryParents[postId];
    return late.containsKey(postId) &&
        (primary == null || primary == ThreadRow.bottom);
  }

  void findFirstParents(Post post, int parent) {
    final int id = post.no;
    if (isPreviewedWhenRepeated(post)) {
      firstParents.putIfAbsent(id, () => parent);
    }
    if (isPreviewUnder(id, parent)) {
      return;
    }
    for (final Post reply in repliesTo(id)) {
      if (!atBottom(reply.no)) {
        findFirstParents(reply, id);
      }
    }
  }

  final List<ThreadRow> rows = <ThreadRow>[];

  // [prefix] keeps the paths at the bottom apart from those in the thread.
  void add(
    Post post,
    List<int> ancestors, {
    bool inFull = false,
    bool asPreview = false,
    int? inFullAt,
    String prefix = '',
  }) {
    final int id = post.no;
    final String path = prefix + <int>[...ancestors, id].join('/');
    final bool isPreview =
        asPreview ||
        !inFull &&
            isPreviewUnder(
              id,
              ancestors.isEmpty ? ThreadRow.topLevel : ancestors.last,
            );
    final bool isHidden = id != opId && hidden.contains(id);
    final bool isCollapsed =
        !isPreview && !isHidden && id != opId && collapsed.contains(path);
    final bool showsReplies = !isCollapsed && !isPreview && !isHidden;

    rows.add(
      ThreadRow(
        post: post,
        path: path,
        postIndex: postIndex[id] ?? 0,
        replyCount: id == opId ? opReplyCount : postsBelow(id).length,
        ancestors: ancestors,
        collapsed: isCollapsed,
        isPreview: isPreview && !isHidden,
        hidden: isHidden,
        newReplies: showsReplies
            ? 0
            : postsBelow(id).where(unseen.contains).length,
        inFullAt: isPreview ? inFullAt : null,
      ),
    );

    if (!showsReplies) {
      return;
    }
    final List<int> belowThis = <int>[...ancestors, id];
    for (final Post reply in repliesTo(id)) {
      if (!atBottom(reply.no)) {
        add(reply, belowThis, prefix: prefix);
      } else if (!hidden.contains(reply.no)) {
        add(reply, belowThis, asPreview: true, prefix: prefix);
      }
    }
  }

  final Map<int, Post> byId = <int, Post>{
    for (final Post post in posts) post.no: post,
  };

  /// A late reply at the bottom, under a preview of the post it answers.
  void addLate(Post post) {
    final int parent = late[post.no]!;
    final Post? answered = byId[parent];
    if (answered != null) {
      rows.add(
        ThreadRow(
          post: answered,
          path: 'context:${post.no}',
          postIndex: postIndex[parent] ?? 0,
          replyCount: postsBelow(parent).length,
          isPreview: true,
          isContext: true,
        ),
      );
    }
    final List<int> under = answered == null ? const <int>[] : <int>[parent];
    if (atBottom(post.no)) {
      add(post, under, inFull: true, prefix: 'new:');
    } else {
      add(
        post,
        under,
        asPreview: true,
        inFullAt: ThreadRow.bottom,
        prefix: 'new:',
      );
    }
  }

  // In the order they were posted, the late replies among the new posts.
  final List<Post> topLevel = <Post>[
    for (final Post post in posts)
      if (inTree(post) &&
          (late.containsKey(post.no) ||
              !nested.contains(post.no) ||
              answersOp.contains(post.no)))
        post,
  ];
  for (final Post post in topLevel) {
    if (atBottom(post.no)) {
      for (final Post reply in repliesTo(post.no)) {
        findFirstParents(reply, post.no);
      }
    } else if (!late.containsKey(post.no)) {
      findFirstParents(post, ThreadRow.topLevel);
    }
  }
  for (final Post post in topLevel) {
    if (late.containsKey(post.no)) {
      addLate(post);
    } else {
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

/// The thread with every post in the order it was posted, for
/// [ThreadLayout.flat].
///
/// [replyCounts] says how many replies are below each post, wherever they're
/// listed, and [positions] where posts are in the thread, for when [posts] is
/// only a part of it. A post in [collapsed] folds on its own, as its replies
/// aren't below it here; the first one, the post the list is about, doesn't.
/// Neither is it [hidden], whatever the others are.
List<ThreadRow> buildFlatRows(
  List<Post> posts, {
  required Map<int, int> replyCounts,
  Set<String> collapsed = const <String>{},
  Set<int> hidden = const <int>{},
  Map<int, int>? positions,
}) {
  return <ThreadRow>[
    for (int index = 0; index < posts.length; index++)
      ThreadRow(
        post: posts[index],
        path: '${posts[index].no}',
        postIndex: positions?[posts[index].no] ?? index,
        replyCount: replyCounts[posts[index].no] ?? 0,
        collapsed:
            index > 0 &&
            !hidden.contains(posts[index].no) &&
            collapsed.contains('${posts[index].no}'),
        hidden: index > 0 && hidden.contains(posts[index].no),
      ),
  ];
}
