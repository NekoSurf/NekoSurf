import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_chan/board/grid_post.dart';
import 'package:flutter_chan/board/list_post.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/chan/thread_status.dart';

/// How threads are laid out on a page, as a grid of tiles or a list of cards.
class ThreadsLayout extends StatelessWidget {
  const ThreadsLayout({
    super.key,
    required this.grid,
    required this.itemCount,
    required this.itemBuilder,
  });

  static const double _gridSideInset = 10;
  static const double _gridSpacing = 10;

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
    final double pageWidth = MediaQuery.sizeOf(context).width;
    final int columns = max(2, (pageWidth / 230).floor());
    final double tileWidth =
        (pageWidth - 2 * _gridSideInset - (columns - 1) * _gridSpacing) /
        columns;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(_gridSideInset, 6, _gridSideInset, 18),
      sliver: SliverGrid.builder(
        itemCount: itemCount,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: _gridSpacing,
          mainAxisSpacing: _gridSpacing,
          // Only one row of pills under the image, however wide the tile.
          mainAxisExtent:
              tileWidth / 0.82 -
              (MediaQuery.textScalerOf(context).scale(25) + 8),
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
    this.statusOf,
  });

  final List<Post> threads;
  final bool grid;
  final bool showBoard;

  /// Whether each thread is still up, where that's been checked.
  final ThreadStatus Function(Post post)? statusOf;

  @override
  Widget build(BuildContext context) {
    return ThreadsLayout(
      grid: grid,
      itemCount: threads.length,
      itemBuilder: (BuildContext context, int index) {
        final Post post = threads[index];
        final Key key = ValueKey('${post.board}-${post.no}');
        final ThreadStatus status = statusOf?.call(post) ?? ThreadStatus.online;
        return grid
            ? GridPost(
                key: key,
                post: post,
                showBoard: showBoard,
                status: status,
              )
            : ListPost(
                key: key,
                post: post,
                showBoard: showBoard,
                status: status,
              );
      },
    );
  }
}
