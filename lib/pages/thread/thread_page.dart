import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chan/API/api.dart';
import 'package:flutter_chan/API/urls.dart' as urls;
import 'package:flutter_chan/Models/bookmark.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/Models/thread_memory.dart';
import 'package:flutter_chan/blocs/history_model.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/blocs/watched_posts_model.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:flutter_chan/pages/bookmark_button.dart';
import 'package:flutter_chan/pages/thread/thread_gallery_page.dart';
import 'package:flutter_chan/pages/thread/thread_rows.dart';
import 'package:flutter_chan/pages/thread/thread_rows_list.dart';
import 'package:flutter_chan/services/back_swipe_route.dart';
import 'package:flutter_chan/services/image_cache.dart';
import 'package:flutter_chan/services/show_snackbar.dart';
import 'package:flutter_chan/services/string.dart';
import 'package:flutter_chan/widgets/cupertino_menu.dart';
import 'package:flutter_chan/widgets/dash_header.dart';
import 'package:flutter_chan/widgets/dash_scaffold.dart';
import 'package:flutter_chan/widgets/reload.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:share_plus/share_plus.dart';

class ThreadPage extends StatefulWidget {
  const ThreadPage({
    super.key,
    required this.board,
    required this.thread,
    required this.threadName,
    required this.post,
    this.initialPost,
  });

  final String board;
  final int thread;
  final String threadName;
  final Post post;

  /// Post to show once the thread loads, instead of resuming at the
  /// last-read one.
  final int? initialPost;

  @override
  ThreadPageState createState() => ThreadPageState();
}

class ThreadPageState extends State<ThreadPage>
    with ThreadRowsList<ThreadPage> {
  static const int _preloadVideosEachSide = 3;

  late Future<List<Post>> _fetchAllPostsFromThread;
  List<Post> allPosts = [];
  Map<int, int> _replyDescendantCountByPost = const <int, int>{};

  // Posts in the tree, which is built once; see [_indexReplyTree].
  Map<int, List<Post>> _replyChildren = const <int, List<Post>>{};
  Set<int>? _treePosts;

  Set<int> _preloadVideoPostIds = const <int>{};
  bool _didRestorePlace = false;
  bool _isListSettled = false;
  bool _isListShown = false;
  bool _recordedHistory = false;
  bool _didStartPreloading = false;
  Timer? _preloadDebounce;
  final Set<int> _preloadedThumbnailIds = <int>{};

  // Live updates. 4chan's API rules ask for at least 10s between requests
  // for a thread; idle threads back off to a minute.
  static const Duration _liveMinInterval = Duration(seconds: 15);
  static const Duration _liveMaxInterval = Duration(seconds: 60);
  Timer? _liveTimer;
  Duration _liveInterval = _liveMinInterval;
  String? _lastModified;
  bool _liveStopped = false;
  bool _isGone = false;
  bool _isRefreshing = false;
  bool _isVisible = true;

  late Bookmark favorite;

  /// Remembers what's at the top of the screen, to come back to it.
  void _rememberPlace() {
    if (rows.isEmpty) {
      return;
    }

    // What's on screen on the way to somewhere else isn't being read.
    if (isListSettled && !isAutoScrolling) {
      // Rows behind the floating header aren't on screen.
      ItemPosition? top;
      for (final ItemPosition position in visiblePositions()) {
        if (position.index < rows.length &&
            position.itemTrailingEdge > belowHeader &&
            (top == null || position.index < top.index)) {
          top = position;
        }
      }
      final int? topPost = top == null ? null : rows[top.index].post.no;
      if (top != null && topPost != null) {
        Provider.of<WatchedPostsProvider>(context, listen: false).rememberPlace(
          widget.thread,
          post: topPost,
          path: rows[top.index].path,
          alignment: top.itemLeadingEdge,
        );
      }
    }

    _schedulePreloadRefresh();
  }

  @override
  void initState() {
    super.initState();

    loadThread();

    favorite = Bookmark(
      no: widget.post.no,
      sub: widget.post.sub,
      com: widget.post.com,
      imageUrl: widget.post.thumbnailName,
      board: widget.board,
    );

    itemPositionsListener.itemPositions.addListener(_rememberPlace);
  }

  /// Records the thread in history from its loaded opening post, since
  /// [ThreadPage.post] can be a bare placeholder (e.g. a reply from search).
  void _recordHistory(Post op) {
    if (_recordedHistory ||
        !mounted ||
        !Provider.of<SettingsProvider>(
          context,
          listen: false,
        ).getTrackHistory()) {
      return;
    }
    _recordedHistory = true;

    final String subject = unescape(cleanTags(op.sub ?? '')).trim();
    Provider.of<HistoryProvider>(context, listen: false).recordThread(
      board: widget.board,
      no: widget.thread,
      title: subject.isNotEmpty ? subject : widget.threadName,
      imageUrl: op.thumbnailName,
      com: op.com,
    );

    // A placeholder makes an imageless bookmark too.
    if (widget.post.tim == null &&
        widget.post.sub == null &&
        widget.post.com == null) {
      // The header's bookmark button is outside the FutureBuilder.
      setState(() {
        favorite = Bookmark(
          no: op.no,
          sub: op.sub,
          com: op.com,
          imageUrl: op.thumbnailName,
          board: widget.board,
        );
      });
    }
  }

  @override
  void dispose() {
    itemPositionsListener.itemPositions.removeListener(_rememberPlace);
    _preloadDebounce?.cancel();
    _preloadDebounce = null;
    _liveTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Covered by the media viewer or gallery: no need to poll meanwhile.
    _isVisible = TickerMode.valuesOf(context).enabled;
  }

  @override
  int get threadNumber => widget.thread;

  @override
  bool get isListSettled => _isListSettled;

  /// The list has been told where it's staying, if anywhere else. Once it's been
  /// laid out there, two frames later, it can be shown.
  void _settleList() {
    _isListSettled = true;
    onListSettled();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _rememberPlace();
          setState(() => _isListShown = true);
        }
      });
      WidgetsBinding.instance.scheduleFrame();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void onAutoScrollEnded() => _rememberPlace();

  @override
  void onFoldsChanged() {
    Provider.of<WatchedPostsProvider>(context, listen: false).rememberFolds(
      widget.thread,
      folded: collapsedRows,
      primaryParents: primaryParents,
    );
  }

  void _setPosts(List<Post> posts) {
    allPosts = posts;
    Provider.of<WatchedPostsProvider>(context, listen: false).noteThreadPosts(
      widget.thread,
      <int>[
        for (final Post post in posts)
          if (post.no != null) post.no!,
      ],
    );
    _replyDescendantCountByPost = buildReplyDescendantCountIndex(posts);
    _indexReplyTree();
    rebuildRows();
  }

  /// The tree is made of the posts there are the first time it's built;
  /// later ones stay out of it until the thread is opened again.
  void _indexReplyTree() {
    if (allPosts.isEmpty) {
      return;
    }
    final Set<int> treePosts = _treePosts ??= <int>{
      for (final Post post in allPosts)
        if (post.no != null) post.no!,
    };
    final List<Post> inTree = <Post>[
      for (final Post post in allPosts)
        if (treePosts.contains(post.no)) post,
    ];
    _replyChildren = buildReplyChildrenIndex(inTree);
  }

  @override
  List<ThreadRow> buildRows() => threadLayout == ThreadLayout.flat
      ? buildFlatRows(
          allPosts,
          replyCounts: _replyDescendantCountByPost,
          collapsed: collapsedRows,
        )
      : buildNestedRows(
          allPosts,
          children: _replyChildren,
          collapsed: collapsedRows,
          primaryParents: primaryParents,
          unseen: unseenPosts,
          treePosts: _treePosts,
          opReplyCount: allPosts.isEmpty
              ? 0
              : _replyDescendantCountByPost[allPosts.first.no] ?? 0,
        );

  void loadThread() {
    _liveTimer?.cancel();
    _liveStopped = false;
    _isGone = false;
    _liveInterval = _liveMinInterval;
    _lastModified = null;
    forgetNewThisVisit();
    _treePosts = null;
    final ThreadMemory? memory = Provider.of<WatchedPostsProvider>(
      context,
      listen: false,
    ).threadMemory(widget.thread);
    collapsedRows
      ..clear()
      ..addAll(memory?.folded ?? const <String>{});
    primaryParents
      ..clear()
      ..addAll(memory?.primaryParents ?? const <int, int>{});
    _didRestorePlace = false;
    _isListSettled = false;
    _isListShown = false;
    _didStartPreloading = false;
    _preloadDebounce?.cancel();
    _preloadDebounce = null;
    _preloadedThumbnailIds.clear();
    _preloadVideoPostIds = const <int>{};
    setState(() {
      _fetchAllPostsFromThread =
          fetchAllPostsFromThread(widget.board, widget.thread).then((posts) {
            if (!mounted) {
              return posts;
            }
            // The header, outside the FutureBuilder, says if it's archived.
            setState(() => _setPosts(posts));
            if (posts.isNotEmpty) {
              _recordHistory(posts.first);
            }
            if (_isLive(posts)) {
              _scheduleLiveUpdate();
            }
            return posts;
          });
    });
  }

  /// Archived and closed threads can't get new posts.
  bool _isLive(List<Post> posts) =>
      posts.isNotEmpty &&
      (posts.first.archived ?? 0) != 1 &&
      (posts.first.closed ?? 0) != 1;

  void _scheduleLiveUpdate() {
    _liveTimer?.cancel();
    if (_liveStopped || !mounted) {
      return;
    }
    _liveTimer = Timer(_liveInterval, _pollThread);
  }

  void _backOff() {
    _liveInterval = Duration(
      seconds: min(_liveInterval.inSeconds * 2, _liveMaxInterval.inSeconds),
    );
  }

  Future<void> _pollThread() async {
    if (!mounted || _liveStopped) {
      return;
    }
    final bool foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (!_isVisible || !foreground) {
      _scheduleLiveUpdate();
      return;
    }

    await _update();
    _scheduleLiveUpdate();
  }

  /// Asks 4chan what's changed. Returns how many posts arrived; null if it
  /// couldn't tell.
  Future<int?> _update() async {
    try {
      final update = await fetchThreadUpdate(
        widget.board,
        widget.thread,
        lastModified: _lastModified,
      );
      if (!mounted) {
        return null;
      }
      _lastModified = update.lastModified;

      if (update.status == 404) {
        setState(() => _isGone = true);
        _liveStopped = true;
        return 0;
      }

      final List<Post>? posts = update.posts;
      if (posts == null || posts.isEmpty) {
        _backOff();
        return update.status == 304 ? 0 : null;
      }
      final int added = _applyUpdate(posts);
      _liveStopped = !_isLive(posts);
      return added;
    } catch (_) {
      _backOff();
      return null;
    }
  }

  /// Updates the thread now, and says what that found.
  Future<void> _refresh() async {
    if (_isRefreshing || allPosts.isEmpty) {
      return;
    }
    _isRefreshing = true;
    _liveTimer?.cancel();
    final int? added = await _update();
    _isRefreshing = false;
    if (!mounted) {
      return;
    }
    _scheduleLiveUpdate();
    showCupertinoSnackbar(
      const Duration(milliseconds: 1800),
      true,
      context,
      added == null
          ? "Couldn't refresh"
          : _isGone
          ? 'The thread is gone'
          : added == 0
          ? 'No new posts'
          : added == 1
          ? '1 new post'
          : '$added new posts',
    );
  }

  @override
  void onPulledPastEnd() => _refresh();

  /// Opened by its number alone, like from a link, it's named once it's loaded.
  String get _title {
    final Post? op = allPosts.firstOrNull;
    final bool isPlaceholder =
        widget.post.tim == null &&
        widget.post.sub == null &&
        widget.post.com == null;
    if (op != null && isPlaceholder) {
      final String name = unescape(cleanTags(op.sub ?? op.com ?? '')).trim();
      if (name.isNotEmpty) {
        return name;
      }
    }
    return unescape(cleanTags(widget.threadName));
  }

  /// What's become of the thread, if it isn't live any more.
  String? get _threadStatus {
    final Post? op = allPosts.firstOrNull;
    return _isGone
        ? 'Deleted'
        : op?.archived == 1
        ? 'Archived'
        : op?.closed == 1
        ? 'Closed'
        : null;
  }

  /// Swaps in the refreshed posts. New ones are appended below, so the list
  /// doesn't move.
  int _applyUpdate(List<Post> posts) {
    final Set<int?> known = allPosts.map((p) => p.no).toSet();
    final int added = posts.where((p) => !known.contains(p.no)).length;

    if (added == 0) {
      _backOff();
    } else {
      _liveInterval = _liveMinInterval;
    }
    if (added == 0 && posts.length == allPosts.length) {
      return 0;
    }

    setState(() {
      _setPosts(posts);
    });
    _schedulePreloadRefresh();
    return added;
  }

  /// The nearest videos above and below what's on screen.
  ({Set<int> ids, List<Post> posts}) _collectPreloadWindow() {
    final Set<int> ids = <int>{};
    final List<Post> posts = <Post>[];
    if (rows.isEmpty) {
      return (ids: ids, posts: posts);
    }

    void collect(Iterable<int> indexes) {
      int collected = 0;
      for (final int index in indexes) {
        final Post post = rows[index].post;
        final int? postId = post.no ?? post.tim;
        if (post.isVideo &&
            !rows[index].collapsed &&
            postId != null &&
            ids.add(postId)) {
          posts.add(post);
          if (++collected == _preloadVideosEachSide) {
            return;
          }
        }
      }
    }

    final List<int> shown = <int>[
      for (final ItemPosition position in visiblePositions())
        position.index.clamp(0, rows.length - 1),
    ];
    final int top = shown.isEmpty ? 0 : shown.reduce(min);
    final int bottom = shown.isEmpty ? 0 : shown.reduce(max);
    collect(Iterable<int>.generate(top, (int i) => top - 1 - i));
    collect(
      Iterable<int>.generate(
        rows.length - bottom - 1,
        (int i) => bottom + 1 + i,
      ),
    );

    return (ids: ids, posts: posts);
  }

  Future<void> _preloadThumbnails(List<Post> posts) async {
    for (final Post post in posts) {
      final int? tim = post.tim;
      if (tim == null || !_preloadedThumbnailIds.add(tim)) {
        continue;
      }

      final ImageProvider<Object> thumbnailProvider = thumbnailImage(
        urls.thumbnail(widget.board, tim),
      );

      try {
        await precacheImage(thumbnailProvider, context);
      } catch (_) {}
    }
  }

  void _refreshPreloadWindow() {
    if (!mounted || allPosts.isEmpty) {
      return;
    }

    final preloadWindow = _collectPreloadWindow();

    if (!setEquals(_preloadVideoPostIds, preloadWindow.ids)) {
      setState(() {
        _preloadVideoPostIds = preloadWindow.ids;
      });
    }

    unawaited(_preloadThumbnails(preloadWindow.posts));
  }

  void _schedulePreloadRefresh() {
    if (allPosts.isEmpty || !mounted) {
      return;
    }

    _preloadDebounce?.cancel();
    _preloadDebounce = Timer(const Duration(milliseconds: 140), () {
      _refreshPreloadWindow();
    });
  }

  void _startPreloadingIfNeeded() {
    if (_didStartPreloading || allPosts.isEmpty) {
      return;
    }

    _didStartPreloading = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _schedulePreloadRefresh();
    });
  }

  /// Puts the list back where the thread was left, while it's still hidden.
  void _restorePlace() {
    // Opened at a specific post (e.g. from search): never resume instead,
    // even if that post has since been deleted.
    if (widget.initialPost != null) {
      final int? row = rowByPost[widget.initialPost];
      if (row != null && row > 0) {
        _jumpWhenAttached(row, alignment: belowHeader, flash: true);
      } else {
        _settleList();
      }
      return;
    }

    if (!Provider.of<SettingsProvider>(
      context,
      listen: false,
    ).getAutoScrollToLastSeen()) {
      _settleList();
      return;
    }

    final ThreadMemory? memory = Provider.of<WatchedPostsProvider>(
      context,
      listen: false,
    ).threadMemory(widget.thread);
    final int? row = rowOf(path: memory?.topPath, post: memory?.topPost);
    final double alignment = memory?.topAlignment ?? belowHeader;

    // Still at the very top: the list starts there anyway.
    if (row == null || (row == 0 && alignment >= 0)) {
      _settleList();
    } else {
      _jumpWhenAttached(row, alignment: alignment);
    }
  }

  /// The list may not be laid out yet on the first frame; try a few more.
  void _jumpWhenAttached(
    int index, {
    required double alignment,
    bool flash = false,
    int attempts = 10,
  }) {
    if (!mounted) {
      return;
    }
    if (itemScrollController.isAttached) {
      itemScrollController.jumpTo(index: index, alignment: alignment);
      if (flash) {
        flashRow(rows[index].path);
      }
      _settleList();
    } else if (attempts > 1) {
      Future.delayed(
        const Duration(milliseconds: 50),
        () => _jumpWhenAttached(
          index,
          alignment: alignment,
          flash: flash,
          attempts: attempts - 1,
        ),
      );
    } else {
      _settleList();
    }
  }

  void _openGallery() {
    Navigator.of(context).push(
      BackSwipePageRoute<void>(
        builder: (_) => ThreadGalleryPage(
          board: widget.board,
          thread: widget.thread,
          mediaPosts: allPosts
              .where((p) => p.tim != null && p.ext != null)
              .toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DashBarScaffold(
      title: _title,
      subtitle: _threadStatus,
      actions: [
        DashIconButton(
          icon: const Icon(CupertinoIcons.square_grid_3x2),
          onPressed: _openGallery,
        ),
        BookmarkButton(favorite: favorite),
        CupertinoMenuButton(
          menuChildren: [
            buildMenuItem(
              title: 'Share',
              icon: CupertinoIcons.share,
              onPressed: () {
                SharePlus.instance.share(
                  ShareParams(
                    uri: Uri.parse(
                      urls.threadPage(widget.board, widget.thread),
                    ),
                  ),
                );
              },
            ),
            buildMenuItem(
              title: 'Open in Browser',
              icon: CupertinoIcons.globe,
              onPressed: () {
                launchURL(urls.threadPage(widget.board, widget.thread));
              },
            ),
            buildMenuItem(
              title: 'Refresh',
              icon: CupertinoIcons.arrow_clockwise,
              onPressed: _refresh,
            ),
            buildMenuItem(
              title: 'Scroll to Top',
              icon: CupertinoIcons.arrow_up,
              onPressed: () {
                scrollToRow(0, alignment: 0);
              },
            ),
            buildMenuItem(
              title: 'Scroll to Bottom',
              icon: CupertinoIcons.arrow_down,
              onPressed: () {
                scrollToRow(rows.length - 1, alignment: 0);
              },
            ),
          ],
        ),
      ],
      body: FutureBuilder(
        future: _fetchAllPostsFromThread,
        builder: (BuildContext context, AsyncSnapshot<List<Post>> snapshot) {
          switch (snapshot.connectionState) {
            case ConnectionState.waiting:
              return const Center(child: CupertinoActivityIndicator());
            default:
              if (snapshot.error is ThreadNotFound) {
                return ReloadWidget(
                  onReload: () => loadThread(),
                  icon: CupertinoIcons.trash,
                  title: 'Thread not found',
                  message: 'It was deleted or has dropped out of the archive.',
                  secondaryLabel: 'Open on 4chan',
                  onSecondary: () =>
                      launchURL(urls.threadPage(widget.board, widget.thread)),
                );
              }
              if (snapshot.hasError) {
                return ReloadWidget.forError(
                  snapshot.error,
                  onReload: () => loadThread(),
                );
              } else {
                _startPreloadingIfNeeded();

                if (!_didRestorePlace) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _restorePlace();
                    _didRestorePlace = true;
                  });
                }

                // Hidden until it's back in place, so it doesn't show the top of
                // the thread on its way. Always there, as adding it later would
                // start the list over.
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    IgnorePointer(
                      ignoring: !_isListShown,
                      child: Opacity(
                        opacity: _isListShown ? 1 : 0,
                        child: buildRowList(
                          context,
                          board: widget.board,
                          thread: widget.thread,
                          allPosts: allPosts,
                          preloadVideos: _preloadVideoPostIds,
                        ),
                      ),
                    ),
                    if (!_isListShown)
                      const Center(child: CupertinoActivityIndicator()),
                  ],
                );
              }
          }
        },
      ),
    );
  }
}
