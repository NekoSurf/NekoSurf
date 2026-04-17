import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_chan/Models/bookmark.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/pages/board/list_post.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BoardListView extends StatelessWidget {
  const BoardListView({
    Key? key,
    required this.board,
    required this.threads,
    required this.scrollController,
  }) : super(key: key);

  final String board;
  final List<Post> threads;
  final ScrollController scrollController;

  Future<void> setFavorite(Bookmark favorite) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    List<String>? favoriteThreadsPrefs = prefs.getStringList('favoriteThreads');

    favoriteThreadsPrefs ??= [];

    if (favoriteThreadsPrefs.contains(json.encode(favorite))) {
      return;
    }

    final String favoriteString = json.encode(favorite);

    favoriteThreadsPrefs.add(favoriteString);

    prefs.setStringList('favoriteThreads', favoriteThreadsPrefs);
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: scrollController,
      child: ListView(
        padding: const EdgeInsets.only(top: 6, bottom: 16),
        controller: scrollController,
        shrinkWrap: true,
        children: [
          for (final Post post in threads) ListPost(board: board, post: post),
        ],
      ),
    );
  }
}
