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
    required this.scrollController,
  }) : super(key: key);

  final String board;
  final List<Post> threads;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final crossCount = (MediaQuery.sizeOf(context).width / 230).floor();

    return Scrollbar(
      controller: scrollController,
      child: GridView.builder(
        itemCount: threads.length,
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 18),
        controller: scrollController,
        shrinkWrap: true,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: max(2, crossCount),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.82,
        ),
        itemBuilder: (BuildContext context, int index) {
          return GridPost(board: board, post: threads[index]);
        },
      ),
    );
  }
}
