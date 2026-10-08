import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/pages/board/grid_post.dart';

class BoardGridView extends StatelessWidget {
  const BoardGridView({
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
    final crossCount = (MediaQuery.sizeOf(context).width / 230).floor();

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 18),
      sliver: SliverGrid.builder(
        itemCount: threads.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: max(2, crossCount),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.82,
        ),
        itemBuilder: (BuildContext context, int index) {
          final Post post = threads[index];
          final String postBoard = showBoard ? post.board ?? board : board;
          return GridPost(
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
