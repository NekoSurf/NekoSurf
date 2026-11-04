import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/API/api.dart';
import 'package:flutter_chan/API/urls.dart' as urls;
import 'package:flutter_chan/Models/bookmark.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/history_model.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/blocs/watched_posts_model.dart';
import 'package:flutter_chan/pages/bookmark_button.dart';
import 'package:flutter_chan/pages/thread/thread_gallery_page.dart';
import 'package:flutter_chan/pages/thread/thread_rows.dart';
import 'package:flutter_chan/pages/thread/thread_rows_list.dart';
import 'package:flutter_chan/services/back_swipe_route.dart';
import 'package:flutter_chan/services/image_cache.dart';
import 'package:flutter_chan/services/string.dart';
import 'package:flutter_chan/widgets/cupertino_menu.dart';
import 'package:flutter_chan/widgets/dash_header.dart';
import 'package:flutter_chan/widgets/dash_scaffold.dart';
import 'package:flutter_chan/widgets/new_posts_pill.dart';
import 'package:flutter_chan/widgets/reload.dart';
import 'package:flutter_chan/widgets/resume_toast.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

class ThreadPage extends StatefulWidget {
  const ThreadPage({
    super.key,
    required this.board,
    required this.thread,
    required this.threadName,
    required this.post,
    this.fromFavorites = false,
    this.initialPost,
  });

  final String board;
  final int thread;
  final String threadName;
  final Post post;
  final bool fromFavorites;

  /// Post to show once the thread loads, instead of resuming at the
  /// last-read one.
  final int? initialPost;

  @override
  ThreadPageState createState() => ThreadPageState();
}

class ThreadPageState extends State<ThreadPage>
    with ThreadRowsList<ThreadPage> {
  static const int _preloadVideosEachSide = 3;
  static const int _maxPreloadedVideos = 6;
  static const int _maxThumbnailPreloadsPerPass = _maxPreloadedVideos;

  final ScrollController scrollController = ScrollController();
  late Future<List<Post>> _fetchAllPostsFromThread;
  List<Post> allPosts = [];
  Map<int, int> _replyDescendantCountByPost = const <int, int>{};

  // Posts in the tree, which is built once; see [_indexReplyTree].
  Map<int, List<Post>> _replyChildren = const <int, List<Post>>{};
  Set<int>? _treePosts;

  Set<int> _preloadVideoPostIds = const <int>{};
  bool _hasScrolledToLastWatched = false;
  bool _recordedHistory = false;
  bool _showResumeToast = false;
  Timer? _resumeToastTimer;
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
  bool _isVisible = true;
  int _newPostCount = 0;
  int? _firstNewPost;

  late Bookmark favorite;
  void _markVisiblePostsAsWatched() {
    if (rows.isEmpty) {
      return;
    }

    final watchedPosts = Provider.of<WatchedPostsProvider>(
      context,
      listen: false,
    );

    // Positions come in no particular order; remember the furthest post
    // that is on screen, not whichever happened to be listed last.
    int? furthest;
    for (final position in itemPositionsListener.itemPositions.value) {
      if (position.itemLeadingEdge < 0 || position.itemLeadingEdge > 0.85) {
        continue;
      }

      final int index = position.index;
      if (index < 0 || index >= rows.length) {
        continue;
      }

      if (furthest == null || index > furthest) {
        furthest = index;
      }
    }

    if (furthest != null) {
      final ThreadRow row = rows[furthest];
      watchedPosts.markAsWatched(
        postIndex: row.postIndex,
        seen: row.seen,
        thread: widget.thread,
      );
      final int? firstNew = rowByPost[_firstNewPost];
      if (_newPostCount > 0 && (firstNew == null || furthest >= firstNew)) {
        // Positions can update mid-layout; setState must wait for the frame.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _clearNewPosts();
          }
        });
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
      imageUrl: '${widget.post.tim}s.jpg',
      board: widget.board,
    );

    itemPositionsListener.itemPositions.addListener(_markVisiblePostsAsWatched);
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
      imageUrl: op.tim != null ? '${op.tim}s.jpg' : null,
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
          imageUrl: '${op.tim}s.jpg',
          board: widget.board,
        );
      });
    }
  }

  @override
  void dispose() {
    itemPositionsListener.itemPositions.removeListener(
      _markVisiblePostsAsWatched,
    );
    _preloadDebounce?.cancel();
    _preloadDebounce = null;
    _resumeToastTimer?.cancel();
    _liveTimer?.cancel();
    scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Covered by the media viewer or gallery: no need to poll meanwhile.
    _isVisible = TickerMode.valuesOf(context).enabled;
  }

  void _setPosts(List<Post> posts) {
    allPosts = posts;
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
  List<ThreadRow> buildRows() => buildNestedRows(
    allPosts,
    children: _replyChildren,
    collapsed: collapsedRows,
    primaryParents: primaryParents,
    treePosts: _treePosts,
    opReplyCount: allPosts.isEmpty
        ? 0
        : _replyDescendantCountByPost[allPosts.first.no] ?? 0,
  );

  void loadThread() {
    _liveTimer?.cancel();
    _liveStopped = false;
    _liveInterval = _liveMinInterval;
    _lastModified = null;
    _newPostCount = 0;
    _firstNewPost = null;
    _treePosts = null;
    collapsedRows.clear();
    primaryParents.clear();
    _hasScrolledToLastWatched = false;
    _didStartPreloading = false;
    _preloadDebounce?.cancel();
    _preloadDebounce = null;
    _preloadedThumbnailIds.clear();
    _preloadVideoPostIds = const <int>{};
    setState(() {
      _fetchAllPostsFromThread =
          fetchAllPostsFromThread(widget.board, widget.thread).then((posts) {
            _setPosts(posts);
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

    try {
      final update = await fetchThreadUpdate(
        widget.board,
        widget.thread,
        lastModified: _lastModified,
      );
      if (!mounted || _liveStopped) {
        return;
      }
      _lastModified = update.lastModified;

      if (update.status == 404) {
        _liveStopped = true;
        return;
      }

      final List<Post>? posts = update.posts;
      if (posts == null || posts.isEmpty) {
        _backOff();
      } else {
        _applyUpdate(posts);
        if (!_isLive(posts)) {
          _liveStopped = true;
          return;
        }
      }
    } catch (_) {
      _backOff();
    }

    _scheduleLiveUpdate();
  }

  /// Swaps in the refreshed posts. New ones are appended below, so the list
  /// doesn't move; the pill points at the first one.
  void _applyUpdate(List<Post> posts) {
    final Set<int?> known = allPosts.map((p) => p.no).toSet();
    final int firstNew = posts.indexWhere((p) => !known.contains(p.no));
    final int added = posts.where((p) => !known.contains(p.no)).length;

    if (added == 0) {
      _backOff();
    } else {
      _liveInterval = _liveMinInterval;
    }
    if (added == 0 && posts.length == allPosts.length) {
      return;
    }

    setState(() {
      _setPosts(posts);
      if (added > 0) {
        _firstNewPost ??= posts[firstNew].no;
        _newPostCount += added;
        _showResumeToast = false;
      }
    });
    _schedulePreloadRefresh();
  }

  void _clearNewPosts() {
    if (_newPostCount == 0) {
      return;
    }
    setState(() {
      _newPostCount = 0;
      _firstNewPost = null;
    });
  }

  void _jumpToNewPosts() {
    final int? target = rowByPost[_firstNewPost];
    _clearNewPosts();
    if (target != null && itemScrollController.isAttached) {
      itemScrollController.scrollTo(
        index: target,
        alignment: belowHeader,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  int _resolveAnchorIndex(int postCount) {
    final positions = visiblePositions();

    if (positions.isEmpty) {
      return 0;
    }

    positions.sort((a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge));

    return positions.first.index.clamp(0, postCount - 1);
  }

  bool _sameIdSet(Set<int> a, Set<int> b) {
    if (a.length != b.length) {
      return false;
    }

    for (final int value in a) {
      if (!b.contains(value)) {
        return false;
      }
    }

    return true;
  }

  ({Set<int> ids, List<Post> posts}) _collectPreloadWindow() {
    if (rows.isEmpty) {
      return (ids: <int>{}, posts: const <Post>[]);
    }

    final positions = visiblePositions();

    int minVisibleIndex;
    int maxVisibleIndex;
    if (positions.isEmpty) {
      final int anchor = _resolveAnchorIndex(rows.length);
      minVisibleIndex = anchor;
      maxVisibleIndex = anchor;
    } else {
      minVisibleIndex = positions.first.index;
      maxVisibleIndex = positions.first.index;

      for (final position in positions) {
        if (position.index < minVisibleIndex) {
          minVisibleIndex = position.index;
        }
        if (position.index > maxVisibleIndex) {
          maxVisibleIndex = position.index;
        }
      }
    }

    minVisibleIndex = minVisibleIndex.clamp(0, rows.length - 1);
    maxVisibleIndex = maxVisibleIndex.clamp(0, rows.length - 1);

    final Set<int> ids = <int>{};
    final List<Post> posts = <Post>[];

    int previousCollected = 0;
    for (
      int index = minVisibleIndex - 1;
      index >= 0 && previousCollected < _preloadVideosEachSide;
      index--
    ) {
      if (ids.length >= _maxPreloadedVideos) {
        break;
      }

      final Post post = rows[index].post;
      if (!post.isVideo || rows[index].collapsed) {
        continue;
      }

      final int? postId = post.no ?? post.tim;
      if (postId == null || !ids.add(postId)) {
        continue;
      }

      posts.add(post);
      previousCollected++;
    }

    int nextCollected = 0;
    for (
      int index = maxVisibleIndex + 1;
      index < rows.length && nextCollected < _preloadVideosEachSide;
      index++
    ) {
      if (ids.length >= _maxPreloadedVideos) {
        break;
      }

      final Post post = rows[index].post;
      if (!post.isVideo || rows[index].collapsed) {
        continue;
      }

      final int? postId = post.no ?? post.tim;
      if (postId == null || !ids.add(postId)) {
        continue;
      }

      posts.add(post);
      nextCollected++;
    }

    return (ids: ids, posts: posts);
  }

  Future<void> _preloadThumbnails(List<Post> posts) async {
    int preloaded = 0;

    for (final Post post in posts) {
      if (preloaded >= _maxThumbnailPreloadsPerPass) {
        break;
      }

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

      preloaded++;
    }
  }

  void _refreshPreloadWindow() {
    if (!mounted || allPosts.isEmpty) {
      return;
    }

    final preloadWindow = _collectPreloadWindow();

    if (!_sameIdSet(_preloadVideoPostIds, preloadWindow.ids)) {
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

  void scrollToLastWatchedPosts(List<Post> allPosts) {
    // Opened at a specific post (e.g. from search): never resume instead,
    // even if that post has since been deleted.
    if (widget.initialPost != null) {
      final int? row = rowByPost[widget.initialPost];
      if (row != null && row > 0) {
        _jumpWhenAttached(row);
      }
      return;
    }

    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final watchedPosts = Provider.of<WatchedPostsProvider>(
      context,
      listen: false,
    );

    if (!settings.getAutoScrollToLastSeen()) {
      return;
    }

    final latestWatchedPosts = watchedPosts.getLatestWatchedPosts(
      widget.thread,
    );

    if (latestWatchedPosts != null && allPosts.isNotEmpty) {
      if (latestWatchedPosts.postIndex != -1) {
        // The position is saved as a place in the thread, whatever the order
        // the list was in at the time.
        final Post lastPost =
            allPosts[min(latestWatchedPosts.postIndex, allPosts.length - 1)];
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted && itemScrollController.isAttached) {
            itemScrollController.jumpTo(
              index: rowByPost[lastPost.no] ?? 0,
              alignment: belowHeader,
            );
            if (latestWatchedPosts.postIndex > 0) {
              _flashResumeToast();
            }
          }
        });
      }
    }
  }

  /// The list may not be laid out yet on the first frame; try a few more.
  void _jumpWhenAttached(int index, {int attempts = 10}) {
    Future.delayed(const Duration(milliseconds: 50), () {
      if (!mounted) {
        return;
      }
      if (itemScrollController.isAttached) {
        itemScrollController.jumpTo(index: index, alignment: belowHeader);
        flashRow(rows[index].path);
      } else if (attempts > 1) {
        _jumpWhenAttached(index, attempts: attempts - 1);
      }
    });
  }

  void _flashResumeToast() {
    _resumeToastTimer?.cancel();
    setState(() => _showResumeToast = true);
    _resumeToastTimer = Timer(const Duration(seconds: 4), _hideResumeToast);
  }

  void _hideResumeToast() {
    _resumeToastTimer?.cancel();
    _resumeToastTimer = null;
    if (mounted && _showResumeToast) {
      setState(() => _showResumeToast = false);
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
      title: unescape(cleanTags(widget.threadName)),
      actions: [
        DashIconButton(
          icon: const Icon(CupertinoIcons.square_grid_3x2),
          onPressed: _openGallery,
        ),
        BookmarkButton(favorite: favorite),
        CupertinoMenuButton(
          isGlass: true,
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
              title: 'Scroll to Top',
              icon: CupertinoIcons.arrow_up,
              onPressed: () {
                if (itemScrollController.isAttached) {
                  itemScrollController.scrollTo(
                    index: 0,
                    alignment: 0,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOutCubic,
                  );
                }
              },
            ),
            buildMenuItem(
              title: 'Scroll to Bottom',
              icon: CupertinoIcons.arrow_down,
              onPressed: () {
                if (itemScrollController.isAttached) {
                  itemScrollController.scrollTo(
                    index: rows.length - 1,
                    alignment: 0,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOutCubic,
                  );
                }
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

                if (!_hasScrolledToLastWatched) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    scrollToLastWatchedPosts(allPosts);
                    _hasScrolledToLastWatched = true;
                  });
                }

                return Stack(
                  children: [
                    buildRowList(
                      context,
                      board: widget.board,
                      thread: widget.thread,
                      allPosts: allPosts,
                      preloadVideos: _preloadVideoPostIds,
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: MediaQuery.paddingOf(context).bottom + 16,
                      child: Center(
                        child: NewPostsPill(
                          count: _newPostCount,
                          onTap: _jumpToNewPosts,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: MediaQuery.paddingOf(context).bottom + 16,
                      child: Center(
                        child: ResumeToast(
                          visible: _showResumeToast && _newPostCount == 0,
                          onBackToTop: () {
                            _hideResumeToast();
                            if (itemScrollController.isAttached) {
                              itemScrollController.scrollTo(
                                index: 0,
                                alignment: 0,
                                duration: const Duration(milliseconds: 500),
                                curve: Curves.easeInOutCubic,
                              );
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                );
              }
          }
        },
      ),
    );
  }
}
