import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/history/watched_posts_model.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/thread/thread_branch.dart';
import 'package:flutter_chan/thread/thread_page_post.dart';
import 'package:flutter_chan/thread/thread_posts.dart';
import 'package:flutter_chan/thread/thread_rows.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_header.dart';
import 'package:flutter_chan/ui/pull_to_refresh.dart';
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

  late final ThreadLayout _layout;

  /// How posts are listed: as chosen in Settings, unless a page knows better.
  ThreadLayout get layout => _layout;

  /// The folded rows, by [ThreadRow.path].
  final Set<String> collapsedRows = <String>{};

  /// Which parent each post was moved to show in full under, by tapping its
  /// preview there.
  final Map<int, int> primaryParents = <int, int>{};
  List<ThreadRow> rows = const <ThreadRow>[];

  int? rowOf({String? path, int? post}) => _rowByPath[path] ?? rowByPost[post];

  /// Where each post is first listed, as it can be listed several times.
  Map<int, int> rowByPost = const <int, int>{};
  Map<String, int> _rowByPath = const <String, int>{};

  // The order to swipe through media in: as listed, leaving out what's folded
  // away and previews, as those are shown in full elsewhere.
  List<Post> _listedPosts = const <Post>[];
  Timer? _highlightTimer;
  String? _highlightedRow;

  // Posts that were new at some point in this visit: they stay tinted until it
  // ends, so they can still be told apart on the way back up.
  final Set<int> _newThisVisit = <int>{};
  bool _isCheckingNewPosts = false;
  bool _isAutoScrolling = false;
  ({int row, double alignment, Duration duration, double? distance})? _aim;
  Timer? _autoScrollTimer;

  @override
  void initState() {
    super.initState();
    _layout = Provider.of<SettingsProvider>(
      context,
      listen: false,
    ).threadLayout.value;
    itemPositionsListener.itemPositions.addListener(_onPositionsChanged);
  }

  /// Whether the list is scrolling by itself: what passes by isn't being read.
  bool get isAutoScrolling => _isAutoScrolling;

  /// A scroll by itself has ended, leaving the list where the reader is now.
  void onAutoScrollEnded() {}

  /// Pulling past either end of the list asks for this.
  Future<void> onPulled() async {}

  /// What's folded, or where a post shows in full, has changed.
  void onFoldsChanged() {}

  ThreadPosts get thread;

  /// Whether what's on screen is where the reader is, rather than where the
  /// list starts on its way to where they left off; see [settleList].
  bool isListSettled = true;

  /// The posts in the thread that haven't been on screen since they were posted.
  Set<int> get unseenPosts => Provider.of<WatchedPostsProvider>(
    context,
    listen: false,
  ).unseenPosts(thread.number);

  /// The rows to show, given [collapsedRows] and [primaryParents].
  List<ThreadRow> buildRows();

  void rebuildRows() {
    _newThisVisit.addAll(unseenPosts);
    rows = buildRows();
    final Map<int, int> byPost = <int, int>{};
    final Map<String, int> byPath = <String, int>{};
    final Map<int, Post> listed = <int, Post>{};
    for (int index = 0; index < rows.length; index++) {
      final ThreadRow row = rows[index];
      byPath[row.path] = index;
      if (row.isPreview) {
        continue;
      }
      byPost.putIfAbsent(row.post.no, () => index);
      if (!row.collapsed) {
        listed.putIfAbsent(row.post.no, () => row.post);
      }
    }
    // A post only previewed here is at least there to go to.
    for (int index = 0; index < rows.length; index++) {
      byPost.putIfAbsent(rows[index].post.no, () => index);
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
  void _checkHeldPlace(String path, double alignment) {
    afterListMoved(() {
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
  }

  /// Runs [action] once the list has been laid out where it was told to go: the
  /// positions it reports are only up to date two frames later.
  void afterListMoved(VoidCallback action) {
    void afterFrames(int frames) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (frames > 1) {
          afterFrames(frames - 1);
        } else if (mounted) {
          action();
        }
      });
      WidgetsBinding.instance.scheduleFrame();
    }

    afterFrames(2);
  }

  void _toggleRow(String path) {
    final double? edge = _headerEdge(path);
    setState(() {
      if (!collapsedRows.remove(path)) {
        collapsedRows.add(path);
      }
      rebuildRows();
    });
    onFoldsChanged();
    _holdPlace(path, edge);
    if (edge == null) {
      flashRow(path);
    }
  }

  void _showInFullHere(ThreadRow row) {
    final double? edge = _headerEdge(row.path);
    setState(() {
      primaryParents[row.post.no] = row.parent;
      rebuildRows();
    });
    onFoldsChanged();
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
      if (row.post.no != post) {
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

  void _goToRow(ThreadRow target, double alignment) {
    final int? index = _rowByPath[target.path];
    if (index != null && !rows[index].collapsed) {
      scrollToRow(index, alignment: alignment);
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
    onFoldsChanged();
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

  void _onPositionsChanged() {
    if (_isCheckingNewPosts || _isAutoScrolling || !isListSettled) {
      return;
    }
    // Positions can update mid-layout; setState must wait for the frame.
    _isCheckingNewPosts = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isCheckingNewPosts = false;
      if (mounted) {
        _checkNewPosts();
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// The list has been told where it's staying, if anywhere else: what's on
  /// screen from then on is where the reader is.
  void settleList() {
    isListSettled = true;
    afterListMoved(_checkNewPosts);
  }

  /// A new post counts as seen once it's on screen, unless it's folded away or
  /// only a preview.
  void _checkNewPosts() {
    if (_isAutoScrolling || !isListSettled) {
      return;
    }
    final Set<int> unseen = unseenPosts;
    final Set<int> seen = <int>{
      if (unseen.isNotEmpty)
        for (final ItemPosition position in visiblePositions())
          if (position.index < rows.length &&
              !rows[position.index].collapsed &&
              !rows[position.index].isPreview &&
              unseen.contains(rows[position.index].post.no) &&
              position.itemTrailingEdge > belowHeader)
            rows[position.index].post.no,
    };
    if (seen.isNotEmpty) {
      Provider.of<WatchedPostsProvider>(
        context,
        listen: false,
      ).markPostsSeen(thread.number, seen);
      setState(rebuildRows);
    }
  }

  List<ThreadRow> _rowsWithoutFolds() {
    final Set<String> folded = Set<String>.of(collapsedRows);
    collapsedRows.clear();
    final List<ThreadRow> open = buildRows();
    collapsedRows.addAll(folded);
    return open;
  }

  /// Scrolls to [row] by itself, to [alignment] on the screen or as near as the
  /// ends of the list allow.
  ///
  /// A row near the end can't reach the top of the screen, and only the list
  /// knows, once it's on its way: see [_checkAim].
  void scrollToRow(int row, {required double alignment}) {
    const Duration duration = Duration(milliseconds: 200);
    if (!itemScrollController.isAttached || rows.isEmpty) {
      return;
    }
    final ItemPosition? shown = itemPositionsListener.itemPositions.value
        .where((ItemPosition position) => position.index == row)
        .firstOrNull;
    _aim = (
      row: row,
      alignment: alignment,
      duration: duration,
      distance: shown == null ? null : shown.itemLeadingEdge - alignment,
    );
    _driveTo(row, alignment, duration);
  }

  /// The list doesn't always say when a scroll ends, as the reader can stop it,
  /// so this goes by how long it should take.
  void _driveTo(int row, double alignment, Duration duration) {
    if (!itemScrollController.isAttached) {
      return;
    }
    _isAutoScrolling = true;
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer(duration + const Duration(milliseconds: 150), () {
      _isAutoScrolling = false;
      if (mounted) {
        _checkNewPosts();
        onAutoScrollEnded();
      }
    });
    itemScrollController.scrollTo(
      index: row,
      alignment: alignment,
      duration: duration,
      curve: Curves.easeInOut,
    );
  }

  /// Whether the scroll under way can get where it's going, now the list knows
  /// its ends, on its first step. If not, it starts over aiming for as far as it
  /// can go, to slow down into place instead of being cut off at speed. To a row
  /// that isn't laid out, the list fades to another list, not yet showing, which
  /// is at 0 with the row in place, and moving up to that.
  void _checkAim(ScrollMetrics position, double value) {
    final ({int row, double alignment, Duration duration, double? distance})?
    aim = _aim;
    if (aim == null) {
      return;
    }
    final double? distance = aim.distance;
    final double beyond;
    if (distance != null) {
      final double destination =
          position.pixels + distance * position.viewportDimension;
      beyond = destination > position.maxScrollExtent
          ? destination - position.maxScrollExtent
          : destination < position.minScrollExtent
          ? destination - position.minScrollExtent
          : 0;
    } else if (value > position.pixels &&
        position.pixels < position.maxScrollExtent &&
        position.maxScrollExtent < 0) {
      beyond = -position.maxScrollExtent;
    } else {
      return;
    }
    _aim = null;
    if (beyond == 0) {
      return;
    }
    final double alignment =
        aim.alignment + beyond / position.viewportDimension;
    // Not in the middle of the list's step.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _driveTo(aim.row, alignment, aim.duration);
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _showPost(int post) {
    final int target = _nearestRow(post);
    if (target < 0) {
      return;
    }
    scrollToRow(target, alignment: belowHeader);
  }

  /// The rows for [posts] in the chosen layout, with what's folded. [children],
  /// [treePosts] and [opReplyCount] are as in [buildNestedRows].
  List<ThreadRow> layOutRows(
    List<Post> posts, {
    required Map<int, List<Post>> children,
    Set<int>? treePosts,
    int opReplyCount = 0,
  }) => layout == ThreadLayout.flat
      ? buildFlatRows(
          posts,
          replyCounts: thread.replyCounts,
          collapsed: collapsedRows,
          positions: thread.places,
        )
      : buildNestedRows(
          posts,
          children: children,
          collapsed: collapsedRows,
          primaryParents: primaryParents,
          unseen: unseenPosts,
          treePosts: treePosts,
          opReplyCount: opReplyCount,
          positions: thread.places,
        );

  /// The list of [rows]. Replies at its top level answer [rootPost], the post
  /// the list is about; the opening post if not said.
  Widget buildRowList({int? rootPost, Set<int> preloadVideos = const <int>{}}) {
    final bool isFlat = layout == ThreadLayout.flat;

    return PullToRefresh(
      onRefresh: onPulled,
      fromBottom: true,
      child: ScrollablePositionedList.builder(
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom + 8,
        ),
        shrinkWrap: false,
        itemCount: rows.length,
        itemScrollController: itemScrollController,
        itemPositionsListener: itemPositionsListener,
        physics: _StopsAtEndsWhenDriven(
          // A thread shorter than the screen can still be pulled to refresh.
          parent: PullToRefresh.pullPhysics,
          isDriven: () => _isAutoScrolling,
          onDrivenStep: _checkAim,
        ),
        itemBuilder: (context, index) {
          final ThreadRow row = rows[index];
          final Post post = row.post;

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
                  ? context.accent.withValues(alpha: 0.16)
                  : context.accent.withValues(
                      alpha: _newThisVisit.contains(post.no) ? 0.07 : 0,
                    ),
              child: ThreadBranch(
                ancestors: row.ancestors,
                previousDepth: index == 0
                    ? null
                    : rows[index - 1].ancestors.length,
                child: ThreadPagePost(
                  thread: thread,
                  post: post,
                  mediaOrder: _listedPosts,
                  replyCount: row.replyCount,
                  // The opening post's replies are the rest of the thread, not
                  // a branch to fold: its count still opens them on their own.
                  onToggleFold: row.postIndex == 0
                      ? null
                      : row.isPreview
                      ? () => _showInFullHere(row)
                      : () => _toggleRow(row.path),
                  folded: row.collapsed,
                  isPreview: row.isPreview,
                  countOpensReplies: isFlat,
                  newReplies: row.newReplies,
                  onTapQuote: _showQuotedPost,
                  // The top level answers the post the list is about. Flat, no
                  // post is under another, so none of its quotes stands out.
                  repliedTo: isFlat
                      ? null
                      : row.ancestors.isNotEmpty
                      ? row.ancestors.last
                      : rootPost ?? thread.posts.firstOrNull?.no,
                  preloadVideo: preloadVideos.contains(post.no),
                  onViewerMovedTo: _showPost,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _autoScrollTimer?.cancel();
    itemPositionsListener.itemPositions.removeListener(_onPositionsChanged);
    super.dispose();
  }
}

/// Stops at the ends of the list while it scrolls by itself, in case it's still
/// told to go past them, and tells of each step. What the reader does still
/// bounces.
class _StopsAtEndsWhenDriven extends ScrollPhysics {
  const _StopsAtEndsWhenDriven({
    required this.isDriven,
    required this.onDrivenStep,
    super.parent,
  });

  final bool Function() isDriven;
  final void Function(ScrollMetrics position, double value) onDrivenStep;

  @override
  _StopsAtEndsWhenDriven applyTo(ScrollPhysics? ancestor) =>
      _StopsAtEndsWhenDriven(
        isDriven: isDriven,
        onDrivenStep: onDrivenStep,
        parent: buildParent(ancestor),
      );

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    if (!isDriven()) {
      return super.applyBoundaryConditions(position, value);
    }
    onDrivenStep(position, value);
    return const ClampingScrollPhysics().applyBoundaryConditions(
      position,
      value,
    );
  }
}
