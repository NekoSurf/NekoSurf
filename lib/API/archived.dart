import 'dart:convert';

import 'package:flutter_chan/API/api.dart';
import 'package:flutter_chan/API/http_client.dart';
import 'package:flutter_chan/Models/bookmark.dart';
import 'package:flutter_chan/Models/bookmark_status.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:http/http.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What one board's catalog and archive say about its threads.
class _BoardSnapshot {
  _BoardSnapshot(this.live, this.archived);

  final Map<int, Post> live;

  /// Null when the board has no archive (or it couldn't be loaded).
  final Set<int>? archived;
}

const Duration _snapshotTtl = Duration(minutes: 2);
final Map<String, (DateTime, Future<_BoardSnapshot>)> _snapshots = {};

/// One catalog (plus one archive list) per board answers the status of every
/// bookmarked or recently visited thread on it, instead of downloading each
/// thread's full JSON. Concurrent callers share the same request.
Future<_BoardSnapshot> _boardSnapshot(String board, {bool force = false}) {
  // A forced refresh still shares a request made moments ago, so the many
  // threads of one board checked together hit the network once.
  final cached = _snapshots[board];
  final Duration maxAge = force ? const Duration(seconds: 5) : _snapshotTtl;
  if (cached != null && DateTime.now().difference(cached.$1) < maxAge) {
    return cached.$2;
  }

  final Future<_BoardSnapshot> future = () async {
    final List<Post> catalog = await fetchCatalog(board);
    Set<int>? archived;
    try {
      final Response response = await httpClient.get(
        Uri.parse('https://a.4cdn.org/$board/archive.json'),
      );
      if (response.statusCode == 200) {
        archived = (jsonDecode(response.body) as List).cast<int>().toSet();
      }
    } catch (_) {}
    return _BoardSnapshot({
      for (final Post op in catalog)
        if (op.no != null) op.no!: op,
    }, archived);
  }();
  _snapshots[board] = (DateTime.now(), future);
  future.catchError((Object _) {
    // Don't keep a failed snapshot around.
    if (identical(_snapshots[board]?.$2, future)) {
      _snapshots.remove(board);
    }
    return _BoardSnapshot(const {}, null);
  });
  return future;
}

Future<BookmarkStatus> fetchBookmarkStatus(
  String? board,
  String? thread, {
  bool force = false,
}) async {
  final int? no = int.tryParse(thread ?? '');
  if (board != null && no != null) {
    try {
      final _BoardSnapshot snapshot = await _boardSnapshot(board, force: force);
      final Post? op = snapshot.live[no];
      if (op != null) {
        return BookmarkStatus()
          ..status = ThreadStatus.online
          ..replies = (ThreadReplyCount()
            ..replies = op.replies ?? 0
            ..images = op.images ?? 0);
      }
      // Not live: archived, deleted, or newer than the snapshot. The thread
      // itself settles it and has the final reply counts.
    } catch (_) {}
  }

  return _fetchBookmarkStatusFromThread(board, thread);
}

Future<BookmarkStatus> _fetchBookmarkStatusFromThread(
  String? board,
  String? thread,
) async {
  final BookmarkStatus bookmarkStatus = BookmarkStatus();

  final Response response = await httpClient.get(
    Uri.parse('https://a.4cdn.org/$board/thread/$thread.json'),
  );

  if (response.statusCode == 200) {
    final List<Post> posts = (jsonDecode(response.body)['posts'] as List)
        .map((model) => Post.fromJson(model as Map<String?, dynamic>))
        .toList();

    if (posts[0].archived == 1) {
      bookmarkStatus.status = ThreadStatus.archived;
    } else {
      bookmarkStatus.status = ThreadStatus.online;
    }

    final ThreadReplyCount list = ThreadReplyCount();

    list.replies = posts[0].replies ?? 0;
    list.images = posts[0].images ?? 0;

    bookmarkStatus.replies = list;
  } else {
    bookmarkStatus.status = ThreadStatus.deleted;
  }

  return bookmarkStatus;
}

/// Like [fetchBookmarkStatus], but only reports [ThreadStatus.deleted] when
/// 4chan is sure. Returns null when the status is unknown (network error).
Future<ThreadStatus?> fetchThreadStatus(
  String board,
  int thread, {
  bool force = false,
}) async {
  try {
    final _BoardSnapshot snapshot = await _boardSnapshot(board, force: force);
    if (snapshot.live.containsKey(thread)) {
      return ThreadStatus.online;
    }
    if (snapshot.archived?.contains(thread) ?? false) {
      return ThreadStatus.archived;
    }
  } catch (_) {
    return null;
  }

  // Deleted, newer than the snapshot, or archived after the archive list was
  // fetched: only the thread itself can tell, and this case is rare.
  try {
    final Response response = await httpClient.get(
      Uri.parse('https://a.4cdn.org/$board/thread/$thread.json'),
    );

    if (response.statusCode == 404) {
      return ThreadStatus.deleted;
    }
    if (response.statusCode != 200) {
      return null;
    }

    final posts = jsonDecode(response.body)['posts'] as List;
    final op = Post.fromJson(posts.first as Map<String?, dynamic>);
    return op.archived == 1 ? ThreadStatus.archived : ThreadStatus.online;
  } catch (_) {
    return null;
  }
}

Future<void> removeFavorite(Bookmark favorite) async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  final List<String>? favoriteThreadsPrefs = prefs.getStringList(
    'favoriteThreads',
  );

  favoriteThreadsPrefs?.remove(json.encode(favorite));

  prefs.setStringList('favoriteThreads', favoriteThreadsPrefs ?? []);
}

Future<void> clearBookmarks() async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  prefs.setStringList('favoriteThreads', []);
}
