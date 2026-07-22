import 'package:flutter/material.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/pages/board/list_post.dart';

class BoardListView extends StatelessWidget {
  const BoardListView({Key? key, required this.board, required this.threads})
    : super(key: key);

  final String board;
  final List<Post> threads;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.only(top: 6, bottom: 16),
      sliver: SliverList.builder(
        itemCount: threads.length,
        itemBuilder: (context, index) => ListPost(
          key: ValueKey(threads[index].no),
          board: board,
          post: threads[index],
        ),
      ),
    );
  }
}
