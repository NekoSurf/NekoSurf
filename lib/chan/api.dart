import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_chan/chan/board.dart';
import 'package:flutter_chan/chan/http_client.dart';
import 'package:flutter_chan/chan/load_errors.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/chan/urls.dart' as urls;
import 'package:http/http.dart';

/// Every live thread on [board], in catalog order.
Future<List<Post>> fetchCatalog(String board) async {
  final Response response = await httpClient.get(urls.catalog(board));
  if (response.statusCode != 200) {
    throw ApiException(response.statusCode, 'catalog');
  }

  return compute(_parseCatalog, (body: response.body, board: board));
}

/// Every live thread on all [boards]. One failing board shouldn't hide the
/// rest, so failures are left out; null only when every board failed.
Future<List<Post>?> fetchCatalogs(List<String> boards) async {
  final List<List<Post>?> results = await Future.wait(
    boards.map(
      (board) => fetchCatalog(
        board,
      ).then<List<Post>?>((threads) => threads).catchError((_) => null),
    ),
  );

  final List<List<Post>> loaded = results.whereType<List<Post>>().toList();
  if (boards.isNotEmpty && loaded.isEmpty) {
    return null;
  }
  return loaded.expand((threads) => threads).toList();
}

/// Every post of [thread], oldest first.
Future<List<Post>> fetchThread(String board, int thread) async {
  final Response response = await httpClient.get(urls.thread(board, thread));

  if (response.statusCode == 200) {
    return compute(_parseThread, (body: response.body, board: board));
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
        ? await compute(_parseThread, (body: response.body, board: board))
        : null,
    lastModified: response.headers['last-modified'] ?? lastModified,
  );
}

/// One post of [thread]; null if it's gone from there.
Future<Post?> fetchPost(String board, int thread, int post) async {
  final List<Post> posts = await fetchThread(board, thread);
  return posts.where((p) => p.no == post).firstOrNull;
}

/// Numbers of every thread in [board]'s archive, newest first.
Future<List<int>> fetchArchive(String board) async {
  final Response response = await httpClient.get(urls.archive(board));
  if (response.statusCode != 200) {
    throw ApiException(response.statusCode, 'archive');
  }

  return (jsonDecode(response.body) as List).cast<int>().reversed.toList();
}

typedef _Fetched = ({String body, String board});

// Catalogs and big threads run to hundreds of KB of JSON; decoding them on
// the UI isolate dropped frames during the page transition.
List<Post> _parseCatalog(_Fetched fetched) {
  final List<Post> ops = <Post>[];
  // ignore: strict_raw_type
  for (final page in jsonDecode(fetched.body) as List) {
    // ignore: strict_raw_type
    for (final opInPage in page['threads'] as List) {
      ops.add(Post.fromJson(opInPage as Map<String, dynamic>, fetched.board));
    }
  }
  return ops;
}

List<Post> _parseThread(_Fetched fetched) {
  return (jsonDecode(fetched.body)['posts'] as List)
      .map(
        (model) => Post.fromJson(model as Map<String, dynamic>, fetched.board),
      )
      .toList();
}

// The board list practically never changes; fetch it once per app session.
Future<List<Board>>? _boardsCache;

Future<List<Board>> fetchAllBoards({bool refresh = false}) {
  if (refresh) {
    _boardsCache = null;
  }
  return _boardsCache ??= _fetchAllBoards()
    ..catchError((Object _) {
      _boardsCache = null;
      return <Board>[];
    });
}

Future<List<Board>> _fetchAllBoards() async {
  final Response response = await httpClient.get(urls.boards);

  if (response.statusCode == 200) {
    return (jsonDecode(response.body)['boards'] as List)
        .map((model) => Board.fromJson(model as Map<String, dynamic>))
        .toList();
  } else {
    throw ApiException(response.statusCode, 'board list');
  }
}
