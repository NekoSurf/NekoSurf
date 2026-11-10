import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/chan/post_text.dart';

class ThreadPosts {
  ThreadPosts({required this.board, required this.number, required this.posts});

  final String board;
  final int number;

  /// Oldest first; empty until it's loaded.
  final List<Post> posts;

  /// Where each post is in the thread.
  late final Map<int, int> places = <int, int>{
    for (int index = 0; index < posts.length; index++) posts[index].no: index,
  };

  /// Which posts answer each post; see [buildReplyChildrenIndex].
  late final Map<int, List<Post>> replies = buildReplyChildrenIndex(posts);

  /// How many posts are below each post, counting a post that's there by several
  /// routes once.
  late final Map<int, int> replyCounts = _countBelow(posts, replies);

  /// The posts with something attached, oldest first.
  List<Post> get media => posts.where((Post post) => post.hasFile).toList();

  /// Each poster ID's posts, oldest first, on boards that give posters one.
  late final Map<String, List<Post>> postsById = () {
    final Map<String, List<Post>> byId = <String, List<Post>>{};
    for (final Post post in posts) {
      if (post.id case final String id) {
        byId.putIfAbsent(id, () => <Post>[]).add(post);
      }
    }
    return byId;
  }();

  Post? post(int no) {
    final int? place = places[no];
    return place == null ? null : posts[place];
  }

  /// How a post is named in the thread: `OP`, its place like `#38`, or its
  /// number if it isn't in the thread.
  String labelOf(int post) {
    final int? place = places[post];
    return place == null
        ? '$post'
        : place == 0
        ? 'OP'
        : '#$place';
  }

  List<Post> branchOf(Post root) {
    final Set<int> below = _subtree(root.no, replies).map((p) => p.no).toSet();
    return <Post>[
      root,
      for (final Post post in posts)
        if (below.contains(post.no)) post,
    ];
  }
}

/// Which posts answer each post, oldest first.
///
/// A reply hangs off the earlier posts it quotes, except one it's already below
/// through another of them: it'd show twice in the same branch otherwise. That
/// still leaves it below that post, so no reply is lost.
Map<int, List<Post>> buildReplyChildrenIndex(List<Post> allPosts) {
  final Map<int, int> postOrder = <int, int>{
    for (int index = 0; index < allPosts.length; index++)
      allPosts[index].no: index,
  };
  final Map<int, List<Post>> repliesByParent = <int, List<Post>>{};
  final Map<int, Set<int>> postsAbove = <int, Set<int>>{};

  for (final Post post in allPosts) {
    // A post quoted twice is still only one post.
    final Set<int> quoted = extractQuotedPostIds(post.com)
        .where(
          (int quoted) =>
              postOrder.containsKey(quoted) &&
              postOrder[quoted]! < postOrder[post.no]!,
        )
        .toSet();
    if (quoted.isEmpty) {
      continue;
    }

    final Set<int> above = postsAbove[post.no] = <int>{};
    for (final int parentId in quoted) {
      above
        ..add(parentId)
        ..addAll(postsAbove[parentId] ?? const <int>{});
      final bool isBelowAnother = quoted.any(
        (int other) => postsAbove[other]?.contains(parentId) ?? false,
      );
      if (!isBelowAnother) {
        repliesByParent.putIfAbsent(parentId, () => <Post>[]).add(post);
      }
    }
  }

  return repliesByParent;
}

Map<int, int> _countBelow(List<Post> posts, Map<int, List<Post>> replies) {
  final Map<int, Set<int>> below = <int, Set<int>>{};

  Set<int> postsBelow(int post) {
    return below[post] ??= <int>{
      for (final Post child in replies[post] ?? const <Post>[]) ...<int>[
        child.no,
        ...postsBelow(child.no),
      ],
    };
  }

  return <int, int>{
    for (final Post post in posts) post.no: postsBelow(post.no).length,
  };
}

List<Post> _subtree(int root, Map<int, List<Post>> replies) {
  final List<Post> collected = <Post>[];
  final Set<int> visited = <int>{root};

  void collectChildren(int parent) {
    for (final Post child in replies[parent] ?? const <Post>[]) {
      if (visited.add(child.no)) {
        collected.add(child);
        collectChildren(child.no);
      }
    }
  }

  collectChildren(root);
  return collected;
}
