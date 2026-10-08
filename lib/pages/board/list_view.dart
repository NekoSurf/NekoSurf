import 'package:flutter/material.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/pages/board/list_post.dart';

class BoardListView extends StatelessWidget {
  const BoardListView({
    Key? key,
    required this.board,
    required this.threads,
    this.showBoard = false,
  }) : super(key: key);

  final String board;
  final List<Post> threads;

  /// Uses each thread's own `board` and shows it on the tile.
  final bool showBoard;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.only(top: 6, bottom: 16),
      sliver: SliverList.builder(
        itemCount: threads.length,
        itemBuilder: (context, index) {
          final Post post = threads[index];
          final String postBoard = showBoard ? post.board ?? board : board;
          return ListPost(
            key: ValueKey('$postBoard-${post.no}'),
            board: postBoard,
            post: post,
            showBoard: showBoard,
          );
        },
      ),
    );
  }
}
