import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_chan/board/grid_post.dart';
import 'package:flutter_chan/board/list_post.dart';
import 'package:flutter_chan/chan/post.dart';

/// How threads are laid out on a page, as a grid of tiles or a list of cards.
class ThreadsLayout extends StatelessWidget {
  const ThreadsLayout({
    super.key,
    required this.grid,
    required this.itemCount,
    required this.itemBuilder,
  });

  final bool grid;
  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    if (!grid) {
      return SliverPadding(
        padding: const EdgeInsets.only(top: 6, bottom: 16),
        sliver: SliverList.builder(
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        ),
      );
    }
    final int columns = (MediaQuery.sizeOf(context).width / 230).floor();
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 18),
      sliver: SliverGrid.builder(
        itemCount: itemCount,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: max(2, columns),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.82,
        ),
        itemBuilder: itemBuilder,
      ),
    );
  }
}

/// [threads], each on its tile or card. With [showBoard], those say their board.
class ThreadsView extends StatelessWidget {
  const ThreadsView({
    super.key,
    required this.threads,
    required this.grid,
    this.showBoard = false,
  });

  final List<Post> threads;
  final bool grid;
  final bool showBoard;

  @override
  Widget build(BuildContext context) {
    return ThreadsLayout(
      grid: grid,
      itemCount: threads.length,
      itemBuilder: (BuildContext context, int index) {
        final Post post = threads[index];
        final Key key = ValueKey('${post.board}-${post.no}');
        return grid
            ? GridPost(key: key, post: post, showBoard: showBoard)
            : ListPost(key: key, post: post, showBoard: showBoard);
      },
    );
  }
}
