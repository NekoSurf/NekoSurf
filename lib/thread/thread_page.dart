import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chan/bookmarks/bookmark.dart';
import 'package:flutter_chan/bookmarks/bookmark_button.dart';
import 'package:flutter_chan/chan/api.dart';
import 'package:flutter_chan/chan/load_errors.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/chan/urls.dart' as urls;
import 'package:flutter_chan/history/history_model.dart';
import 'package:flutter_chan/history/thread_memory.dart';
import 'package:flutter_chan/history/watched_posts_model.dart';
import 'package:flutter_chan/media/image_cache.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/thread/thread_gallery_page.dart';
import 'package:flutter_chan/thread/thread_posts.dart';
import 'package:flutter_chan/thread/thread_rows.dart';
import 'package:flutter_chan/thread/thread_rows_list.dart';
import 'package:flutter_chan/ui/back_swipe_route.dart';
import 'package:flutter_chan/ui/dash_header.dart';
import 'package:flutter_chan/ui/dash_menu.dart';
import 'package:flutter_chan/ui/dash_scaffold.dart';
import 'package:flutter_chan/ui/open_url.dart';
import 'package:flutter_chan/ui/reload.dart';
import 'package:flutter_chan/ui/toast.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:share_plus/share_plus.dart';

class ThreadPage extends StatefulWidget {
  const ThreadPage({super.key, required this.post, this.initialPost});

  /// What's known of the thread's opening post; just its board and number if
  /// it's opened by its number, like from a link.
  final Post post;

  String get board => post.board;
  int get thread => post.no;

  /// Post to show once the thread loads, instead of resuming at the
  /// last-read one.
  final int? initialPost;

  @override
  State<ThreadPage> createState() => _ThreadPageState();
}

class _ThreadPageState extends State<ThreadPage>
    with ThreadRowsList<ThreadPage> {
  static const int _preloadVideosEachSide = 3;

  late Future<List<Post>> _loaded;

  @override
  late ThreadPosts thread = ThreadPosts(
    board: widget.board,
    number: widget.thread,
    posts: const <Post>[],
  );

  // Posts in the tree, which is built once; see [_indexReplyTree].
  Map<int, List<Post>> _replyChildren = const <int, List<Post>>{};
  Set<int>? _treePosts;
  Set<int> _unseenAtOpen = const <int>{};

  Set<int> _preloadVideoPostIds = const <int>{};
  bool _didRestorePlace = false;
  bool _isListShown = false;
  bool _recordedHistory = false;
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
      if (top != null) {
        Provider.of<WatchedPostsProvider>(context, listen: false).rememberPlace(
          widget.thread,
          post: rows[top.index].post.no,
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

    isListSettled = false;
    final ThreadMemory? memory = Provider.of<WatchedPostsProvider>(
      context,
      listen: false,
    ).threadMemory(widget.thread);
    collapsedRows.addAll(memory?.folded ?? const <String>{});
    primaryParents.addAll(memory?.primaryParents ?? const <int, int>{});

    loadThread();

    itemPositionsListener.itemPositions.addListener(_rememberPlace);
  }

  /// Once per visit, from the loaded opening post: [ThreadPage.post] can be
  /// just a number (e.g. a reply from search).
  void _recordHistory(Post op) {
    if (_recordedHistory || !mounted) {
      return;
    }
    _recordedHistory = true;
    Provider.of<HistoryProvider>(context, listen: false).recordThread(op);
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

  void _settleList() {
    settleList();
    afterListMoved(() {
      _rememberPlace();
      setState(() => _isListShown = true);
    });
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
    thread = ThreadPosts(
      board: widget.board,
      number: widget.thread,
      posts: posts,
    );
    Provider.of<WatchedPostsProvider>(context, listen: false).noteThreadPosts(
      widget.thread,
      <int>[for (final Post post in posts) post.no],
    );
    _indexReplyTree();
    rebuildRows();
  }

  /// The tree is made of the posts there are the first time it's built;
  /// later ones stay out of it until the thread is opened again. What hadn't
  /// been seen then is kept for the visit, so replies that came while the
  /// reader was away stay at the bottom once they've been read.
  void _indexReplyTree() {
    if (thread.posts.isEmpty) {
      return;
    }
    if (_treePosts == null) {
      _unseenAtOpen = Set<int>.of(unseenPosts);
    }
    final Set<int> treePosts = _treePosts ??= thread.places.keys.toSet();
    final List<Post> inTree = <Post>[
      for (final Post post in thread.posts)
        if (treePosts.contains(post.no)) post,
    ];
    _replyChildren = buildReplyChildrenIndex(inTree);
  }

  @override
  List<ThreadRow> buildRows() => layOutRows(
    thread.posts,
    children: _replyChildren,
    treePosts: _treePosts,
    unseenAtOpen: _unseenAtOpen,
    opReplyCount: thread.replyCounts[widget.thread] ?? 0,
  );

  void loadThread() {
    setState(() {
      _loaded = fetchThread(widget.board, widget.thread).then((posts) {
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

  Future<void> _refresh() async {
    if (_isRefreshing || thread.posts.isEmpty) {
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
    showToast(
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
  Future<void> onPulled() => _refresh();

  /// Opened by its number alone, like from a link, it's named once it's loaded.
  Post get _opening => thread.posts.firstOrNull ?? widget.post;

  String get _title {
    final String name = _opening.title;
    return name.isNotEmpty ? name : '/${widget.board}/ No.${widget.thread}';
  }

  /// What's become of the thread, if it isn't live any more.
  String? get _threadStatus {
    final Post? op = thread.posts.firstOrNull;
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
    final int added = posts
        .where((p) => !thread.places.containsKey(p.no))
        .length;

    if (added == 0) {
      _backOff();
    } else {
      _liveInterval = _liveMinInterval;
    }
    if (added == 0 && posts.length == thread.posts.length) {
      return 0;
    }

    setState(() {
      _setPosts(posts);
    });
    _schedulePreloadRefresh();
    return added;
  }

  ({Set<int> ids, List<Post> posts}) _collectPreloadWindow() {
    final Set<int> ids = <int>{};
    final List<Post> posts = <Post>[];
    if (rows.isEmpty ||
        Provider.of<SettingsProvider>(context, listen: false).dataSaver.value) {
      return (ids: ids, posts: posts);
    }

    void collect(Iterable<int> indexes) {
      int collected = 0;
      for (final int index in indexes) {
        final Post post = rows[index].post;
        if (post.isVideo && !rows[index].collapsed && ids.add(post.no)) {
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

      await precacheImage(
        thumbnailImage(post.thumbnailUrl),
        context,
        onError: (_, _) {},
      );
    }
  }

  void _refreshPreloadWindow() {
    if (!mounted || thread.posts.isEmpty) {
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
    if (thread.posts.isEmpty || !mounted) {
      return;
    }

    _preloadDebounce?.cancel();
    _preloadDebounce = Timer(const Duration(milliseconds: 140), () {
      _refreshPreloadWindow();
    });
  }

  void _restorePlace() {
    // Opened at a specific post (e.g. from search): never resume instead,
    // even if that post has since been deleted.
    if (widget.initialPost != null) {
      final int? row = rowByPost[widget.initialPost];
      if (row != null && row > 0) {
        itemScrollController.jumpTo(index: row, alignment: belowHeader);
        flashRow(rows[row].path);
      }
      _settleList();
      return;
    }

    if (!Provider.of<SettingsProvider>(
      context,
      listen: false,
    ).autoScrollToLastSeen.value) {
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
    if (row != null && (row != 0 || alignment < 0)) {
      itemScrollController.jumpTo(index: row, alignment: alignment);
    }
    _settleList();
  }

  void _openGallery() {
    Navigator.of(context).push(
      BackSwipePageRoute<void>(
        // What's hidden stays out of sight here too.
        builder: (_) => ThreadGalleryPage(
          mediaPosts: <Post>[
            for (final Post post in thread.media)
              if (!isHidden(post.no)) post,
          ],
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
          label: 'Gallery',
          icon: const Icon(CupertinoIcons.square_grid_3x2),
          onPressed: _openGallery,
        ),
        BookmarkButton(bookmark: Bookmark.fromPost(_opening)),
        DashMenuButton(
          menuChildren: [
            DashMenuEntry(
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
            DashMenuEntry(
              title: 'Open in Browser',
              icon: CupertinoIcons.globe,
              onPressed: () {
                openUrl(urls.threadPage(widget.board, widget.thread));
              },
            ),
            DashMenuEntry(
              title: 'Refresh',
              icon: CupertinoIcons.arrow_clockwise,
              onPressed: _refresh,
            ),
            DashMenuEntry(
              title: 'Scroll to Top',
              icon: CupertinoIcons.arrow_up,
              onPressed: () {
                scrollToRow(0, alignment: 0);
              },
            ),
            DashMenuEntry(
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
        future: _loaded,
        builder: (BuildContext context, AsyncSnapshot<List<Post>> snapshot) {
          switch (snapshot.connectionState) {
            case ConnectionState.waiting:
              return const Center(child: CupertinoActivityIndicator());
            default:
              if (snapshot.error is ThreadNotFound) {
                return ReloadWidget(
                  onReload: loadThread,
                  icon: CupertinoIcons.trash,
                  title: 'Thread not found',
                  message: 'It was deleted or has dropped out of the archive.',
                  secondaryLabel: 'Open on 4chan',
                  onSecondary: () =>
                      openUrl(urls.threadPage(widget.board, widget.thread)),
                );
              }
              if (snapshot.hasError) {
                return ReloadWidget.forError(
                  snapshot.error,
                  onReload: loadThread,
                );
              } else {
                if (!_didRestorePlace) {
                  // Once the list is there to be told.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      _restorePlace();
                      _didRestorePlace = true;
                    }
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
