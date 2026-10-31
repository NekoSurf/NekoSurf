import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_chan/API/http_client.dart';
import 'package:flutter_chan/API/urls.dart' as urls;
import 'package:flutter_chan/Models/board.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:flutter_chan/services/string.dart';
import 'package:http/http.dart';
import 'package:url_launcher/url_launcher.dart';

Future<List<Post>> fetchAllThreadsFromBoard(
  Sort sorting,
  String board, {
  SortDirection direction = SortDirection.desc,
}) async {
  return sortThreads(await fetchCatalog(board), sorting, direction);
}

/// Every live thread on [board], in catalog order.
Future<List<Post>> fetchCatalog(String board) async {
  final Response response = await httpClient.get(urls.catalog(board));
  if (response.statusCode != 200) {
    throw ApiException(response.statusCode, 'catalog');
  }

  return compute(_parseCatalog, response.body);
}

/// Every live thread on all [boards], each tagged with its board. One failing
/// board shouldn't hide the rest, so failures are left out; null only when
/// every board failed.
Future<List<Post>?> fetchCatalogs(List<String> boards) async {
  final List<List<Post>?> results = await Future.wait(
    boards.map(
      (board) => fetchCatalog(board)
          .then<List<Post>?>((threads) {
            for (final Post thread in threads) {
              thread.board = board;
            }
            return threads;
          })
          .catchError((_) => null),
    ),
  );

  final List<List<Post>> loaded = results.whereType<List<Post>>().toList();
  if (boards.isNotEmpty && loaded.isEmpty) {
    return null;
  }
  return loaded.expand((threads) => threads).toList();
}

/// Sorts a copy of [threads], with sticky threads hoisted to the top in
/// their sorted order. Cheap enough to re-run on every sort change.
List<Post> sortThreads(
  List<Post> threads,
  Sort sorting,
  SortDirection direction,
) {
  int key(Post post) {
    switch (sorting) {
      case Sort.byBumpOrder:
        return post.lastModified ?? 0;
      case Sort.byReplyCount:
        return post.replies ?? 0;
      case Sort.byImagesCount:
        return post.images ?? 0;
      case Sort.byNewest:
      case Sort.byOldest:
        return post.time ?? 0;
    }
  }

  // Thread sorting — always sort ascending first, then reverse for desc
  List<Post> ops = List<Post>.of(threads)
    ..sort((a, b) => key(a).compareTo(key(b)));
  if (direction == SortDirection.desc) {
    ops = ops.reversed.toList();
  }

  // Always hoist sticky threads to the top, preserving their relative order
  return [
    ...ops.where((p) => (p.sticky ?? 0) == 1),
    ...ops.where((p) => (p.sticky ?? 0) != 1),
  ];
}

/// Threads whose subject, name and comment together contain every word of
/// [query], in any order and ignoring case, like find.4chan.org matches.
List<Post> filterThreads(List<Post> threads, String query) {
  final List<String> words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) {
    return threads;
  }

  return threads.where((post) {
    final String text = [
      post.sub ?? '',
      post.name ?? '',
      unescape(cleanTags(post.com ?? '')),
    ].join('\n').toLowerCase();
    return words.every(text.contains);
  }).toList();
}

/// 4chan answered with [statusCode] instead of the [what] asked for.
class ApiException implements Exception {
  const ApiException(this.statusCode, this.what);

  final int statusCode;
  final String what;

  /// 4chan's servers limit how often they're asked; this is them saying no.
  bool get isRateLimited => statusCode == 429;

  @override
  String toString() => "Couldn't load the $what (HTTP $statusCode).";
}

/// The thread was deleted or has dropped out of the archive.
class ThreadNotFound implements Exception {
  const ThreadNotFound();

  @override
  String toString() =>
      'The thread was deleted or has dropped out of the '
      'archive.';
}

Future<List<Post>> fetchAllPostsFromThread(String board, int thread) async {
  final Response response = await httpClient.get(urls.thread(board, thread));

  if (response.statusCode == 200) {
    return compute(_parseThread, response.body);
  } else if (response.statusCode == 404) {
    throw const ThreadNotFound();
  } else {
    throw ApiException(response.statusCode, 'thread');
  }
}

/// Re-downloads a thread only if it changed since [lastModified], the
/// Last-Modified header of the previous response, so polling an idle thread
/// costs a tiny 304. [posts] is null unless the thread changed (status 200).
Future<({int status, List<Post>? posts, String? lastModified})>
fetchThreadUpdate(String board, int thread, {String? lastModified}) async {
  final Response response = await httpClient.get(
    urls.thread(board, thread),
    headers: {'If-Modified-Since': ?lastModified},
  );

  return (
    status: response.statusCode,
    posts: response.statusCode == 200
        ? await compute(_parseThread, response.body)
        : null,
    lastModified: response.headers['last-modified'] ?? lastModified,
  );
}

// Catalogs and big threads run to hundreds of KB of JSON; decoding them on
// the UI isolate dropped frames during the page transition.
List<Post> _parseCatalog(String body) {
  final List<Post> ops = <Post>[];
  // ignore: strict_raw_type
  for (final page in jsonDecode(body) as List) {
    // ignore: strict_raw_type
    for (final opInPage in page['threads'] as List) {
      ops.add(Post.fromJson(opInPage as Map<String?, dynamic>));
    }
  }
  return ops;
}

List<Post> _parseThread(String body) {
  return (jsonDecode(body)['posts'] as List)
      .map((model) => Post.fromJson(model as Map<String?, dynamic>))
      .toList();
}

Future<List<Post>> fetchAllRepliesToPost(
  int post,
  String board,
  int thread,
  List<Post> allPosts,
) async {
  return collectReplySubtree(rootPostId: post, allPosts: allPosts);
}

Map<int, List<Post>> buildReplyChildrenIndex(List<Post> allPosts) {
  final Map<int, Post> postsById = <int, Post>{
    for (final Post post in allPosts)
      if (post.no != null) post.no!: post,
  };
  final Map<int, int> postOrder = <int, int>{
    for (int index = 0; index < allPosts.length; index++)
      if (allPosts[index].no != null) allPosts[index].no!: index,
  };
  final Map<int, List<Post>> repliesByParent = <int, List<Post>>{};

  for (final Post post in allPosts) {
    final int? postId = post.no;

    if (postId == null) {
      continue;
    }

    final List<int> quotedPostIds = extractQuotedPostIds(post.com)
        .where((int quotedPostId) => postsById.containsKey(quotedPostId))
        .where(
          (int quotedPostId) =>
              (postOrder[quotedPostId] ?? -1) < (postOrder[postId] ?? 0),
        )
        .toList();

    if (quotedPostIds.isEmpty) {
      continue;
    }

    final int parentId = quotedPostIds.last;
    repliesByParent.putIfAbsent(parentId, () => <Post>[]).add(post);
  }

  for (final List<Post> replies in repliesByParent.values) {
    replies.sort(
      (Post a, Post b) =>
          (postOrder[a.no] ?? 0).compareTo(postOrder[b.no] ?? 0),
    );
  }

  return repliesByParent;
}

Map<int, int> buildReplyDescendantCountIndex(List<Post> allPosts) {
  final Map<int, List<Post>> repliesByParent = buildReplyChildrenIndex(
    allPosts,
  );
  final Map<int, int> descendantsByPostId = <int, int>{};

  int countDescendants(int postId) {
    final int? cached = descendantsByPostId[postId];
    if (cached != null) {
      return cached;
    }

    final List<Post> children = repliesByParent[postId] ?? const <Post>[];
    int descendants = 0;

    for (final Post child in children) {
      final int? childId = child.no;
      if (childId == null) {
        continue;
      }

      descendants += 1 + countDescendants(childId);
    }

    descendantsByPostId[postId] = descendants;
    return descendants;
  }

  for (final Post post in allPosts) {
    final int? postId = post.no;
    if (postId == null) {
      continue;
    }

    countDescendants(postId);
  }

  return descendantsByPostId;
}

List<Post> collectReplySubtree({
  required int rootPostId,
  required List<Post> allPosts,
}) {
  final Map<int, List<Post>> repliesByParent = buildReplyChildrenIndex(
    allPosts,
  );
  final List<Post> collectedReplies = <Post>[];
  final Set<int> visitedPostIds = <int>{rootPostId};

  void collectChildren(int parentId) {
    final List<Post> children = repliesByParent[parentId] ?? const <Post>[];

    for (final Post child in children) {
      final int? childId = child.no;

      if (childId == null || !visitedPostIds.add(childId)) {
        continue;
      }

      collectedReplies.add(child);
      collectChildren(childId);
    }
  }

  collectChildren(rootPostId);

  return collectedReplies;
}

// The board list practically never changes; fetch it once per app session.
Future<List<Board>>? _boardsCache;

Future<List<Board>> fetchAllBoards({bool refresh = false}) {
  if (refresh) {
    _boardsCache = null;
  }
  return _boardsCache ??= _fetchAllBoards()
    ..catchError((Object _) {
      // Don't cache a failure; the next call retries.
      _boardsCache = null;
      return <Board>[];
    });
}

Future<List<Board>> _fetchAllBoards() async {
  final Response response = await httpClient.get(urls.boards);

  if (response.statusCode == 200) {
    final List<Board> boards = (jsonDecode(response.body)['boards'] as List)
        .map((model) => Board.fromJson(model as Map<String, dynamic>))
        .toList();
    return boards;
  } else {
    throw ApiException(response.statusCode, 'board list');
  }
}

Future<Post?>? fetchPost(String board, int thread, int post) async {
  final List<Post> allPosts = await fetchAllPostsFromThread(board, thread);

  for (final Post postLoop in allPosts) {
    if (postLoop.no == post) {
      return postLoop;
    }
  }

  return null;
}

Future<void> launchURL(String url) async {
  final bool launched = await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.platformDefault,
  ).catchError((_) => false);
  if (!launched) {
    debugPrint('Could not launch $url');
  }
}
