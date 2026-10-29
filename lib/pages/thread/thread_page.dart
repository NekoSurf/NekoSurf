import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/api.dart';
import 'package:flutter_chan/Models/bookmark.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/history_model.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/blocs/watched_posts_model.dart';
import 'package:flutter_chan/pages/bookmark_button.dart';
import 'package:flutter_chan/pages/thread/thread_gallery_page.dart';
import 'package:flutter_chan/pages/thread/thread_page_post.dart';
import 'package:flutter_chan/services/string.dart';
import 'package:flutter_chan/widgets/cupertino_menu.dart';
import 'package:flutter_chan/widgets/dash_header.dart';
import 'package:flutter_chan/widgets/dash_scaffold.dart';
import 'package:flutter_chan/widgets/feed_player_recycler.dart';
import 'package:flutter_chan/widgets/new_posts_pill.dart';
import 'package:flutter_chan/widgets/reload.dart';
import 'package:flutter_chan/widgets/resume_toast.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:share_plus/share_plus.dart';

class ThreadPage extends StatefulWidget {
  const ThreadPage({
    Key? key,
    required this.board,
    required this.thread,
    required this.threadName,
    required this.post,
    this.fromFavorites = false,
    this.initialPost,
  }) : super(key: key);

  final String board;
  final int thread;
  final String threadName;
  final Post post;
  final bool fromFavorites;

  /// Post to show once the thread loads, instead of the last-read one.
  final int? initialPost;

  @override
  ThreadPageState createState() => ThreadPageState();
}

class ThreadPageState extends State<ThreadPage> {
  static const int _preloadVideosEachSide = 3;
  static const int _maxPreloadedVideos = 6;
  static const int _maxThumbnailPreloadsPerPass = _maxPreloadedVideos;

  final ScrollController scrollController = ScrollController();
  final ItemScrollController itemScrollController = ItemScrollController();
  final ItemPositionsListener itemPositionsListener =
      ItemPositionsListener.create();

  late Future<List<Post>> _fetchAllPostsFromThread;
  final FeedPlayerRecycler _playerRecycler = FeedPlayerRecycler();
  List<Post> allPosts = [];
  Map<int, int> _replyDescendantCountByPost = const <int, int>{};
  Set<int> _preloadVideoPostIds = const <int>{};
  bool _hasScrolledToLastWatched = false;
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
  int _firstNewIndex = -1;

  late Bookmark favorite;
  void _markVisiblePostsAsWatched() {
    if (allPosts.isEmpty) {
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
      if (index < 0 || index >= allPosts.length) {
        continue;
      }

      if (furthest == null || index > furthest) {
        furthest = index;
      }
    }

    if (furthest != null) {
      watchedPosts.markAsWatched(postIndex: furthest, thread: widget.thread);
      if (_newPostCount > 0 && furthest >= _firstNewIndex) {
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !Provider.of<SettingsProvider>(
            context,
            listen: false,
          ).getTrackHistory()) {
        return;
      }
      Provider.of<HistoryProvider>(context, listen: false).recordThread(
        board: widget.board,
        no: widget.thread,
        title: widget.threadName,
        imageUrl: widget.post.tim != null ? '${widget.post.tim}s.jpg' : null,
        com: widget.post.com,
      );
    });
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
    unawaited(_playerRecycler.dispose());
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Covered by the media viewer or gallery: no need to poll meanwhile.
    _isVisible = TickerMode.valuesOf(context).enabled;
  }

  void loadThread() {
    _liveTimer?.cancel();
    _liveStopped = false;
    _liveInterval = _liveMinInterval;
    _lastModified = null;
    _newPostCount = 0;
    _firstNewIndex = -1;
    _hasScrolledToLastWatched = false;
    _didStartPreloading = false;
    _preloadDebounce?.cancel();
    _preloadDebounce = null;
    _preloadedThumbnailIds.clear();
    _preloadVideoPostIds = const <int>{};
    setState(() {
      _fetchAllPostsFromThread =
          fetchAllPostsFromThread(widget.board, widget.thread).then((posts) {
            allPosts = posts;
            _replyDescendantCountByPost = buildReplyDescendantCountIndex(posts);
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
      allPosts = posts;
      _replyDescendantCountByPost = buildReplyDescendantCountIndex(posts);
      if (added > 0) {
        if (_firstNewIndex < 0) {
          _firstNewIndex = firstNew;
        }
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
      _firstNewIndex = -1;
    });
  }

  void _jumpToNewPosts() {
    final int target = _firstNewIndex;
    _clearNewPosts();
    if (target >= 0 && itemScrollController.isAttached) {
      itemScrollController.scrollTo(
        index: target,
        alignment: 0,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  bool _isVideoPost(Post post) {
    final ext = post.ext?.toLowerCase();
    return ext == '.webm' || ext == '.mp4';
  }

  List<ItemPosition> _visiblePositions() {
    return itemPositionsListener.itemPositions.value
        .where(
          (position) =>
              position.itemTrailingEdge > 0 && position.itemLeadingEdge < 1,
        )
        .toList();
  }

  int _resolveAnchorIndex(int postCount) {
    final positions = _visiblePositions();

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
    if (allPosts.isEmpty) {
      return (ids: <int>{}, posts: const <Post>[]);
    }

    final positions = _visiblePositions();

    int minVisibleIndex;
    int maxVisibleIndex;
    if (positions.isEmpty) {
      final int anchor = _resolveAnchorIndex(allPosts.length);
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

    minVisibleIndex = minVisibleIndex.clamp(0, allPosts.length - 1);
    maxVisibleIndex = maxVisibleIndex.clamp(0, allPosts.length - 1);

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

      final Post post = allPosts[index];
      if (!_isVideoPost(post)) {
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
      index < allPosts.length && nextCollected < _preloadVideosEachSide;
      index++
    ) {
      if (ids.length >= _maxPreloadedVideos) {
        break;
      }

      final Post post = allPosts[index];
      if (!_isVideoPost(post)) {
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

      final NetworkImage thumbnailProvider = NetworkImage(
        'https://i.4cdn.org/${widget.board}/${tim}s.jpg',
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
    final int initialIndex = widget.initialPost == null
        ? -1
        : allPosts.indexWhere((post) => post.no == widget.initialPost);
    if (initialIndex >= 0) {
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted && itemScrollController.isAttached) {
          itemScrollController.jumpTo(index: initialIndex, alignment: 0);
        }
      });
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

    if (latestWatchedPosts != null) {
      if (latestWatchedPosts.postIndex != -1) {
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted && itemScrollController.isAttached) {
            itemScrollController.jumpTo(
              index: latestWatchedPosts.postIndex,
              alignment: 0,
            );
            if (latestWatchedPosts.postIndex > 0) {
              _flashResumeToast();
            }
          }
        });
      }
    }
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
      MaterialPageRoute<void>(
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
                      'https://boards.4chan.org/${widget.board}/thread/${widget.thread}',
                    ),
                  ),
                );
              },
            ),
            buildMenuItem(
              title: 'Open in Browser',
              icon: CupertinoIcons.globe,
              onPressed: () {
                launchURL(
                  'https://boards.4chan.org/${widget.board}/thread/${widget.thread}',
                );
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
                    index: allPosts.length - 1,
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
              if (snapshot.hasError) {
                return ReloadWidget(onReload: () => loadThread());
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
                    _buildPostList(context),
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

  Widget _buildPostList(BuildContext context) {
    return ScrollablePositionedList.builder(
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + 8,
      ),
      shrinkWrap: false,
      itemCount: allPosts.length,
      itemScrollController: itemScrollController,
      itemPositionsListener: itemPositionsListener,
      itemBuilder: (context, index) => Padding(
        padding: EdgeInsets.only(
          top: index == 0 ? MediaQuery.paddingOf(context).top + 8 : 0,
        ),
        child: ThreadPagePost(
          board: widget.board,
          thread: widget.thread,
          post: allPosts[index],
          allPosts: allPosts,
          replyCount: _replyDescendantCountByPost[allPosts[index].no] ?? 0,
          preloadVideo: _preloadVideoPostIds.contains(
            allPosts[index].no ?? allPosts[index].tim,
          ),
          playerRecycler: _playerRecycler,
          onDismiss: (postId) {
            if (postId == null || !itemScrollController.isAttached) {
              return;
            }
            final targetIndex = allPosts.indexWhere(
              (post) => post.no == postId || post.tim == postId,
            );
            if (targetIndex < 0) {
              return;
            }
            itemScrollController.scrollTo(
              index: targetIndex,
              alignment: 0,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeInOutCubic,
            );
          },
        ),
      ),
    );
  }
}
