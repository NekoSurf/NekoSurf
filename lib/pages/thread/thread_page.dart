import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/api.dart';
import 'package:flutter_chan/Models/bookmark.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/bookmarks_model.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/blocs/watched_posts_model.dart';
import 'package:flutter_chan/constants.dart';
import 'package:flutter_chan/pages/bookmark_button.dart';
import 'package:flutter_chan/pages/thread/thread_page_post.dart';
import 'package:flutter_chan/services/string.dart';
import 'package:flutter_chan/widgets/floating_action_buttons.dart';
import 'package:flutter_chan/widgets/feed_player_pool.dart';
import 'package:flutter_chan/widgets/reload.dart';
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
  }) : super(key: key);

  final String board;
  final int thread;
  final String threadName;
  final Post post;
  final bool fromFavorites;

  @override
  ThreadPageState createState() => ThreadPageState();
}

class ThreadPageState extends State<ThreadPage> {
  static const int _offscreenVideoWarmupEachSide = 3;
  static const int _maxOffscreenWarmVideos = 6;
  static const int _thumbWarmupMaxPerPass = _maxOffscreenWarmVideos;
  // Pool size = warm-window cap + a couple for currently-visible items.
  static const int _playerPoolSize = _maxOffscreenWarmVideos + 4;

  final ScrollController scrollController = ScrollController();
  final ItemScrollController itemScrollController = ItemScrollController();
  final ItemPositionsListener itemPositionsListener =
      ItemPositionsListener.create();

  late Future<List<Post>> _fetchAllPostsFromThread;
  late final FeedPlayerPool _playerPool;

  List<Post> allPosts = [];
  Map<int, int> _replyDescendantCountByPost = const <int, int>{};
  Set<int> _eagerVideoPostIds = const <int>{};
  bool _hasScrolledToLastWatched = false;
  bool _didPrimeEagerWindow = false;
  Timer? _eagerWindowDebounce;
  final Set<int> _prefetchedThumbnailMediaIds = <int>{};

  late Bookmark favorite;
  void _markVisiblePostsAsWatched() {
    if (allPosts.isEmpty) {
      return;
    }

    final watchedPosts = Provider.of<WatchedPostsProvider>(
      context,
      listen: false,
    );

    final positions = itemPositionsListener.itemPositions.value;

    for (final position in positions) {
      if (position.itemLeadingEdge < 0 || position.itemLeadingEdge > 0.85) {
        continue;
      }

      final int index = position.index;
      if (index < 0 || index >= allPosts.length) {
        continue;
      }

      watchedPosts.markAsWatched(postIndex: index, thread: widget.thread);
    }

    _scheduleEagerWindowRefresh();
  }

  @override
  void initState() {
    super.initState();

    _playerPool = FeedPlayerPool(poolSize: _playerPoolSize);
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

  @override
  void dispose() {
    itemPositionsListener.itemPositions.removeListener(
      _markVisiblePostsAsWatched,
    );
    _eagerWindowDebounce?.cancel();
    _eagerWindowDebounce = null;
    scrollController.dispose();
    unawaited(_playerPool.dispose());
    
    // Update bookmark seen counts when leaving thread
    if (widget.fromFavorites && allPosts.isNotEmpty) {
      _updateBookmarkSeenCounts();
    }
    
    super.dispose();
  }

  void _updateBookmarkSeenCounts() {
    final bookmarks = Provider.of<BookmarksProvider>(
      context,
      listen: false,
    );
    
    final replyCount = allPosts.length;
    final imageCount = allPosts.where((p) => p.tim != null).length;
    
    bookmarks.updateBookmarkSeenCounts(
      widget.thread,
      widget.board,
      replyCount,
      imageCount,
    );
  }

  void loadThread() {
    _hasScrolledToLastWatched = false;
    _didPrimeEagerWindow = false;
    _eagerWindowDebounce?.cancel();
    _eagerWindowDebounce = null;
    _prefetchedThumbnailMediaIds.clear();
    _eagerVideoPostIds = const <int>{};
    setState(() {
      _fetchAllPostsFromThread =
          fetchAllPostsFromThread(widget.board, widget.thread).then((posts) {
            _replyDescendantCountByPost = buildReplyDescendantCountIndex(posts);
            return posts;
          });
    });
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

  ({Set<int> ids, List<Post> posts}) _collectOffscreenVideoWindow() {
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
      index >= 0 && previousCollected < _offscreenVideoWarmupEachSide;
      index--
    ) {
      if (ids.length >= _maxOffscreenWarmVideos) {
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
      index < allPosts.length && nextCollected < _offscreenVideoWarmupEachSide;
      index++
    ) {
      if (ids.length >= _maxOffscreenWarmVideos) {
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

  Future<void> _precacheThumbnails(List<Post> posts) async {
    int warmed = 0;

    for (final Post post in posts) {
      if (warmed >= _thumbWarmupMaxPerPass) {
        break;
      }

      final int? tim = post.tim;
      if (tim == null || !_prefetchedThumbnailMediaIds.add(tim)) {
        continue;
      }

      final NetworkImage thumbnailProvider = NetworkImage(
        'https://i.4cdn.org/${widget.board}/${tim}s.jpg',
      );

      try {
        await precacheImage(thumbnailProvider, context);
      } catch (_) {}

      warmed++;
    }
  }

  void _refreshEagerVideoWindow() {
    if (!mounted || allPosts.isEmpty) {
      return;
    }

    final offscreenWindow = _collectOffscreenVideoWindow();

    if (!_sameIdSet(_eagerVideoPostIds, offscreenWindow.ids)) {
      setState(() {
        _eagerVideoPostIds = offscreenWindow.ids;
      });
    }

    unawaited(_precacheThumbnails(offscreenWindow.posts));
  }

  void _scheduleEagerWindowRefresh() {
    if (allPosts.isEmpty || !mounted) {
      return;
    }

    _eagerWindowDebounce?.cancel();
    _eagerWindowDebounce = Timer(const Duration(milliseconds: 140), () {
      _refreshEagerVideoWindow();
    });
  }

  void _primeEagerWindowIfNeeded() {
    if (_didPrimeEagerWindow || allPosts.isEmpty) {
      return;
    }

    _didPrimeEagerWindow = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _scheduleEagerWindowRefresh();
    });
  }

  void scrollToLastWatchedPosts(List<Post> allPosts) {
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
            itemScrollController.scrollTo(
              index: latestWatchedPosts.postIndex,
              alignment: 0,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOutCubic,
            );
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeChanger>(context);
    final bool isDark = theme.getTheme() == ThemeData.dark();

    return Scaffold(
      backgroundColor: AppColors.pageBackground(isDark),
      extendBodyBehindAppBar: true,
      appBar: CupertinoNavigationBar(
        backgroundColor: AppColors.navigationBackground(isDark),
        border: Border.all(color: Colors.transparent),
        leading: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(
              MediaQuery.textScaleFactorOf(context),
            ),
          ),
          child: Transform.translate(
            offset: const Offset(-16, 0),
            child: CupertinoNavigationBarBackButton(
              previousPageTitle: widget.fromFavorites
                  ? 'bookmarks'
                  : '/${widget.board}/',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ),
        middle: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(
              MediaQuery.textScaleFactorOf(context),
            ),
          ),
          child: Text(
            unescape(cleanTags(widget.threadName)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BookmarkButton(favorite: favorite),
            SizedBox(
              width: 20,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () {
                  showCupertinoModalPopup(
                    context: context,
                    builder: (BuildContext context) => CupertinoActionSheet(
                      actions: [
                        CupertinoActionSheetAction(
                          child: const Text('Share'),
                          onPressed: () {
                            Share.share(
                              'https://boards.4chan.org/${widget.board}/thread/${widget.thread}',
                            );
                            Navigator.pop(context);
                          },
                        ),
                        CupertinoActionSheetAction(
                          child: const Text('Open in Browser'),
                          onPressed: () {
                            launchURL(
                              'https://boards.4chan.org/${widget.board}/thread/${widget.thread}',
                            );
                            Navigator.pop(context);
                          },
                        ),
                      ],
                      cancelButton: CupertinoActionSheetAction(
                        child: const Text('Cancel'),
                        onPressed: () {
                          Navigator.pop(context);
                        },
                      ),
                    ),
                  );
                },
                child: const Icon(Icons.more_vert),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButtons(
        scrollController: scrollController,
        goUp: () {
          itemScrollController.scrollTo(
            index: 0,
            alignment: 0,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOutCubic,
          );
        },
        goDown: () {
          if (allPosts.isEmpty) {
            return;
          }

          itemScrollController.scrollTo(
            index: allPosts.length - 1,
            alignment: 0,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOutCubic,
          );
        },
      ),
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
                allPosts = snapshot.data ?? [];
                _primeEagerWindowIfNeeded();

                if (!_hasScrolledToLastWatched) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    scrollToLastWatchedPosts(allPosts);
                    _hasScrolledToLastWatched = true;
                  });
                }

                return SafeArea(
                  top: true,
                  bottom: false,
                  child: ScrollablePositionedList.builder(
                    shrinkWrap: false,
                    itemCount: allPosts.length,
                    itemScrollController: itemScrollController,
                    itemPositionsListener: itemPositionsListener,
                    itemBuilder: (context, index) => ThreadPagePost(
                      board: widget.board,
                      thread: widget.thread,
                      post: allPosts[index],
                      allPosts: allPosts,
                      replyCount:
                          _replyDescendantCountByPost[allPosts[index].no] ?? 0,
                      eagerVideoInit: _eagerVideoPostIds.contains(
                        allPosts[index].no ?? allPosts[index].tim,
                      ),
                      playerPool: _playerPool,
                      onDismiss: (postId) {
                        if (postId == null ||
                            !itemScrollController.isAttached) {
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
        },
      ),
    );
  }
}
