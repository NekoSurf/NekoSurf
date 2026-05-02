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
