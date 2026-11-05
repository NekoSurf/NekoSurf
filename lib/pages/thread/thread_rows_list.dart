import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/enums/enums.dart';
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

  /// How the rows are laid out, as chosen in Settings.
  ThreadLayout threadLayout = ThreadLayout.nested;

  /// The folded rows, by [ThreadRow.path].
  final Set<String> collapsedRows = <String>{};

  /// Which parent each post was moved to show in full under, by tapping its
  /// preview there.
  final Map<int, int> primaryParents = <int, int>{};
  List<ThreadRow> rows = const <ThreadRow>[];

  /// Where each post is first listed, as it can be listed several times.
  Map<int, int> rowByPost = const <int, int>{};
  Map<String, int> _rowByPath = const <String, int>{};

  // The order to swipe through media in: as listed, leaving out what's folded
  // away and previews, as those are shown in full elsewhere.
  List<Post> _listedPosts = const <Post>[];
  Timer? _highlightTimer;
  String? _highlightedRow;

  @override
  void initState() {
    super.initState();
    threadLayout = Provider.of<SettingsProvider>(
      context,
      listen: false,
    ).getThreadLayout();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ThreadLayout chosen = Provider.of<SettingsProvider>(
      context,
    ).getThreadLayout();
    if (chosen != threadLayout) {
      _switchLayout(chosen);
    }
  }

  /// Lays the rows out anew, keeping the post at the top of the screen there.
  void _switchLayout(ThreadLayout chosen) {
    final ItemPosition? top = _topPosition();
    final int? post = top != null && top.index < rows.length
        ? rows[top.index].post.no
        : null;
    threadLayout = chosen;
    rebuildRows();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final int? row = rowByPost[post];
      if (mounted && row != null && itemScrollController.isAttached) {
        itemScrollController.jumpTo(
          index: row,
          alignment: top?.itemLeadingEdge ?? 0,
        );
      }
    });
  }

  /// The rows to show, given [collapsedRows] and [primaryParents].
  List<ThreadRow> buildRows();

  void rebuildRows() {
    rows = buildRows();
    final Map<int, int> byPost = <int, int>{};
    final Map<String, int> byPath = <String, int>{};
    final Map<int?, Post> listed = <int?, Post>{};
    for (int index = 0; index < rows.length; index++) {
      final ThreadRow row = rows[index];
      byPath[row.path] = index;
      if (row.isPreview) {
        continue;
      }
      if (row.post.no != null) {
        byPost.putIfAbsent(row.post.no!, () => index);
      }
      if (!row.collapsed) {
        listed.putIfAbsent(row.post.no, () => row.post);
      }
    }
    // A post only previewed here is at least there to go to.
    for (int index = 0; index < rows.length; index++) {
      if (rows[index].post.no != null) {
        byPost.putIfAbsent(rows[index].post.no!, () => index);
      }
    }
    rowByPost = byPost;
    _rowByPath = byPath;
    _listedPosts = listed.values.toList();
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

  /// Where the top of the row at [path] is on screen; null if it's above the
  /// screen or under the floating header, where its one-line row wouldn't be
  /// seen once folded.
  double? _headerEdge(String path) {
    final int? row = _rowByPath[path];
    for (final ItemPosition position in visiblePositions()) {
      if (position.index == row && position.itemLeadingEdge >= belowHeader) {
        return position.itemLeadingEdge;
      }
    }
    return null;
  }

  /// Puts the list back after the row at [path] folded or unfolded.
  ///
  /// The list holds its place by position, so rows coming or going below could
  /// move what's on screen: this pins the row's header to where it was at
  /// [edge], or just below the floating header if it was out of sight.
  void _holdPlace(String path, double? edge) {
    final int? row = _rowByPath[path];
    if (row == null || !itemScrollController.isAttached) {
      return;
    }
    final double alignment = edge ?? belowHeader;
    itemScrollController.jumpTo(index: row, alignment: alignment);
    _checkHeldPlace(path, alignment);
  }

  /// Puts the row back if it didn't stay put, which was seen once and couldn't
  /// be explained: losing the post just folded is worse than a small correction.
  /// Positions are only up to date two frames after the list was told to move.
  void _checkHeldPlace(String path, double alignment, {int frames = 2}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (frames > 1) {
        _checkHeldPlace(path, alignment, frames: frames - 1);
        return;
      }
      final int? row = _rowByPath[path];
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

  /// Folds or unfolds a row and its replies, from the row itself.
  void _toggleRow(String path) {
    final double? edge = _headerEdge(path);
    setState(() {
      if (!collapsedRows.remove(path)) {
        collapsedRows.add(path);
      }
      rebuildRows();
    });
    _holdPlace(path, edge);
    if (edge == null) {
      flashRow(path);
    }
  }

  /// Moves a post and its replies to the place of its preview, tapped here.
  void _showInFullHere(ThreadRow row) {
    final int? post = row.post.no;
    if (post == null) {
      return;
    }
    final double? edge = _headerEdge(row.path);
    setState(() {
      primaryParents[post] = row.parent;
      rebuildRows();
    });
    _holdPlace(row.path, edge);
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

  /// Briefly tints a row so it's clear where a jump landed.
  void flashRow(String path) {
    _highlightTimer?.cancel();
    setState(() => _highlightedRow = path);
    _highlightTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) {
        setState(() => _highlightedRow = null);
      }
    });
  }

  /// The row of [post] nearest to what's on screen, as it may be listed several
  /// times, and shown in full rather than a preview if it can be; -1 if it isn't
  /// listed.
  int _nearestRow(int post) {
    final int here = _topPosition()?.index ?? 0;
    int target = -1;
    for (int index = 0; index < rows.length; index++) {
      final ThreadRow row = rows[index];
      if (row.post.no != post && row.post.tim != post) {
        continue;
      }
      final bool isCloser =
          target < 0 || (index - here).abs() < (target - here).abs();
      final bool isBetter =
          target >= 0 && rows[target].isPreview && !row.isPreview;
      final bool isWorse =
          target >= 0 && !rows[target].isPreview && row.isPreview;
      if (isBetter || (isCloser && !isWorse)) {
        target = index;
      }
    }
    return target;
  }

  /// Goes to [target], unfolding what's in the way.
  void _goToRow(ThreadRow target, double alignment) {
    final int? index = _rowByPath[target.path];
    if (index != null && !rows[index].collapsed) {
      if (itemScrollController.isAttached) {
        itemScrollController.scrollTo(
          index: index,
          alignment: alignment,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOutCubic,
        );
      }
      flashRow(target.path);
      return;
    }

    setState(() {
      collapsedRows.remove(target.path);
      for (int depth = 1; depth <= target.ancestors.length; depth++) {
        collapsedRows.remove(target.ancestors.take(depth).join('/'));
      }
      rebuildRows();
    });
    // The list only knows of the rows that came back once it's built them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final int? index = _rowByPath[target.path];
      if (mounted && index != null && itemScrollController.isAttached) {
        itemScrollController.jumpTo(index: index, alignment: alignment);
        flashRow(target.path);
      }
    });
  }

  /// Goes to the post a quote names. Returns false if it isn't in this list at
  /// all.
  bool _showQuotedPost(int post) {
    final int row = _nearestRow(post);
    ThreadRow? target = row >= 0 ? rows[row] : null;
    if (target == null || target.isPreview) {
      // It's folded away: see where it'd be if open.
      target =
          _rowsWithoutFolds()
              .where((ThreadRow r) => r.post.no == post && !r.isPreview)
              .firstOrNull ??
          target;
    }
    if (target == null) {
      return false;
    }

    _goToRow(target, belowHeader);
    return true;
  }

  /// The rows there would be with nothing folded.
  List<ThreadRow> _rowsWithoutFolds() {
    final Set<String> folded = Set<String>.of(collapsedRows);
    collapsedRows.clear();
    final List<ThreadRow> open = buildRows();
    collapsedRows.addAll(folded);
    return open;
  }

  /// Scrolls to the post the media viewer ended on.
  void _showPost(int? post) {
    if (post == null || !itemScrollController.isAttached) {
      return;
    }
    final int target = _nearestRow(post);
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
    final bool isFlat = threadLayout == ThreadLayout.flat;

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
          key: ValueKey<String>(row.path),
          padding: EdgeInsets.only(
            top: index == 0 ? MediaQuery.paddingOf(context).top + 8 : 0,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
            color: row.path == _highlightedRow
                ? DashColors.accent.withValues(alpha: 0.16)
                : DashColors.accent.withValues(alpha: 0),
            child: ThreadBranch(
              ancestors: row.ancestors,
              previousDepth: index == 0
                  ? null
                  : rows[index - 1].ancestors.length,
              isDark: isDark,
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
                onToggleFold: row.postIndex == 0 || postId == null
                    ? null
                    : row.isPreview
                    ? () => _showInFullHere(row)
                    : () => _toggleRow(row.path),
                folded: row.collapsed,
                isPreview: row.isPreview,
                countOpensReplies: isFlat,
                onTapQuote: _showQuotedPost,
                // The top level answers the post the list is about. Flat, no
                // post is under another, so none of its quotes stands out.
                repliedTo: isFlat
                    ? null
                    : row.ancestors.isNotEmpty
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
