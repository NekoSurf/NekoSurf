import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';
import 'package:flutter_chan/pages/thread/thread_page_post.dart';
import 'package:flutter_chan/pages/thread/thread_rows.dart';
import 'package:flutter_chan/widgets/dash_header.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// A screen listing posts as [ThreadRow]s: how they look, how branches fold
/// without moving what's on screen, and how a jump shows where it landed.
///
/// List positions always mean a place in [rows].
mixin ThreadRowsList<T extends StatefulWidget> on State<T> {
  final ItemScrollController itemScrollController = ItemScrollController();
  final ItemPositionsListener itemPositionsListener =
      ItemPositionsListener.create();

  final Set<int> collapsedPosts = <int>{};
  List<ThreadRow> rows = const <ThreadRow>[];
  Map<int, int> rowByPost = const <int, int>{};

  // The order to swipe through media in, which leaves out what's folded away.
  List<Post> _listedPosts = const <Post>[];
  Timer? _highlightTimer;
  int? _highlightedPost;

  /// The rows to show, given [collapsedPosts].
  List<ThreadRow> buildRows();

  void rebuildRows() {
    rows = buildRows();
    rowByPost = <int, int>{
      for (int index = 0; index < rows.length; index++)
        if (rows[index].post.no != null) rows[index].post.no!: index,
    };
    _listedPosts = <Post>[
      for (final ThreadRow row in rows)
        if (!row.collapsed) row.post,
    ];
  }

  List<ItemPosition> visiblePositions() {
    return itemPositionsListener.itemPositions.value
        .where(
          (position) =>
              position.itemTrailingEdge > 0 && position.itemLeadingEdge < 1,
        )
        .toList();
  }

  ItemPosition? _topPosition() {
    final positions = visiblePositions();
    if (positions.isEmpty) {
      return null;
    }
    return positions.reduce(
      (a, b) => a.itemLeadingEdge <= b.itemLeadingEdge ? a : b,
    );
  }

  /// Where the top of the row of [post] is on screen; null if it's above the
  /// screen or under the floating header, where its one-line row wouldn't be
  /// seen once folded.
  double? _headerEdge(int post) {
    final int? row = rowByPost[post];
    for (final ItemPosition position in visiblePositions()) {
      if (position.index == row && position.itemLeadingEdge >= belowHeader) {
        return position.itemLeadingEdge;
      }
    }
    return null;
  }

  /// Puts the list back after [post] folded or unfolded.
  ///
  /// The list holds its place by position, so rows coming or going below could
  /// move what's on screen: this pins the row's header to where it was at
  /// [edge], or just below the floating header if it was out of sight.
  void _holdPlace(int post, double? edge) {
    final int? row = rowByPost[post];
    if (row == null || !itemScrollController.isAttached) {
      return;
    }
    final double alignment = edge ?? belowHeader;
    itemScrollController.jumpTo(index: row, alignment: alignment);
    _checkHeldPlace(post, alignment);
  }

  /// Puts the row back if it didn't stay put, which was seen once and couldn't
  /// be explained: losing the post just folded is worse than a small correction.
  /// Positions are only up to date two frames after the list was told to move.
  void _checkHeldPlace(int post, double alignment, {int frames = 2}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (frames > 1) {
        _checkHeldPlace(post, alignment, frames: frames - 1);
        return;
      }
      final int? row = rowByPost[post];
      if (row == null || !itemScrollController.isAttached) {
        return;
      }
      final bool heldPlace = visiblePositions().any(
        (ItemPosition position) =>
            position.index == row &&
            (position.itemLeadingEdge - alignment).abs() < 0.02,
      );
      if (!heldPlace) {
        itemScrollController.jumpTo(index: row, alignment: alignment);
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// Folds or unfolds [post] and its replies, from the post itself.
  void _toggleRow(int post) {
    final double? edge = _headerEdge(post);
    setState(() {
      if (!collapsedPosts.remove(post)) {
        collapsedPosts.add(post);
      }
      rebuildRows();
    });
    _holdPlace(post, edge);
    if (edge == null) {
      flashPost(post);
    }
  }

  /// Folds the replies under [post], from a bar further down its branch.
  /// The post may be far above by then, so go back to it if it's off screen.
  void _collapseBranch(int post) {
    final ItemPosition? top = _topPosition();
    setState(() {
      collapsedPosts.add(post);
      rebuildRows();
    });
    final int? row = rowByPost[post];
    if (row == null || !itemScrollController.isAttached) {
      return;
    }
    if (top != null && top.index < row) {
      itemScrollController.jumpTo(
        index: top.index,
        alignment: top.itemLeadingEdge,
      );
    } else {
      itemScrollController.jumpTo(index: row, alignment: belowHeader);
    }
    flashPost(post);
  }

  /// Alignment that puts a post just below the floating header rather than
  /// under it (the list runs behind the header).
  double get belowHeader {
    final double height = MediaQuery.sizeOf(context).height;
    if (height <= 0) {
      return 0;
    }
    return (MediaQuery.paddingOf(context).top + kDashHeaderHeight + 8) / height;
  }

  /// Briefly tints [post] so it's clear where a jump landed.
  void flashPost(int? post) {
    _highlightTimer?.cancel();
    setState(() => _highlightedPost = post);
    _highlightTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) {
        setState(() => _highlightedPost = null);
      }
    });
  }

  /// Scrolls to the post the media viewer ended on.
  void _showPost(int? post) {
    if (post == null || !itemScrollController.isAttached) {
      return;
    }
    final int target = rows.indexWhere(
      (row) => row.post.no == post || row.post.tim == post,
    );
    if (target < 0) {
      return;
    }
    itemScrollController.scrollTo(
      index: target,
      alignment: belowHeader,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOutCubic,
    );
  }

  Widget buildRowList(
    BuildContext context, {
    required String board,
    required int thread,
    required List<Post> allPosts,
    int? rootPost,
    Set<int> preloadVideos = const <int>{},
  }) {
    final bool isDark = Provider.of<ThemeChanger>(context).isDark;

    return ScrollablePositionedList.builder(
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + 8,
      ),
      shrinkWrap: false,
      itemCount: rows.length,
      itemScrollController: itemScrollController,
      itemPositionsListener: itemPositionsListener,
      itemBuilder: (context, index) {
        final ThreadRow row = rows[index];
        final Post post = row.post;
        final int? postId = post.no;

        return Padding(
          // Folding moves posts to other positions; don't let one take over
          // another's state.
          key: ValueKey<int?>(postId),
          padding: EdgeInsets.only(
            top: index == 0 ? MediaQuery.paddingOf(context).top + 8 : 0,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
            color: _highlightedPost != null && postId == _highlightedPost
                ? DashColors.accent.withValues(alpha: 0.16)
                : DashColors.accent.withValues(alpha: 0),
            child: ThreadBranch(
              ancestors: row.ancestors,
              previousDepth: index == 0
                  ? null
                  : rows[index - 1].ancestors.length,
              isDark: isDark,
              onTapBar: _collapseBranch,
              child: ThreadPagePost(
                board: board,
                thread: thread,
                post: post,
                allPosts: allPosts,
                replies: _listedPosts,
                number: row.postIndex,
                replyCount: row.replyCount,
                // The opening post's replies are the rest of the thread, not
                // a branch to fold: its count still opens them on their own.
                onToggleFold: row.postIndex != 0 && postId != null
                    ? () => _toggleRow(postId)
                    : null,
                folded: row.collapsed,
                // The top level answers the post the list is about.
                repliedTo: row.ancestors.isNotEmpty
                    ? row.ancestors.last
                    : rootPost ?? allPosts.firstOrNull?.no,
                preloadVideo: preloadVideos.contains(postId ?? post.tim),
                onDismiss: _showPost,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    super.dispose();
  }
}
