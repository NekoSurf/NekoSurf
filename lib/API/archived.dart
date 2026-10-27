import 'dart:convert';

import 'package:flutter_chan/Models/bookmark.dart';
import 'package:flutter_chan/Models/bookmark_status.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:http/http.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<BookmarkStatus> fetchBookmarkStatus(
  String? board,
  String? thread,
) async {
  final BookmarkStatus bookmarkStatus = BookmarkStatus();

  final Response response = await get(
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
  } else if (response.statusCode == 404) {
    bookmarkStatus.status = ThreadStatus.deleted;
  } else {
    bookmarkStatus.status = ThreadStatus.deleted;
  }

  return bookmarkStatus;
}

/// Like [fetchBookmarkStatus], but only reports [ThreadStatus.deleted] on a
/// real 404. Returns null when the status is unknown (network error, 5xx).
Future<ThreadStatus?> fetchThreadStatus(String board, int thread) async {
  try {
    final Response response = await get(
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
