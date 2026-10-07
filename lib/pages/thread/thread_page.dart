import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/api.dart';
import 'package:flutter_chan/Models/bookmark.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/blocs/watched_posts_model.dart';
import 'package:flutter_chan/constants.dart';
import 'package:flutter_chan/pages/bookmark_button.dart';
import 'package:flutter_chan/pages/thread/thread_page_post.dart';
import 'package:flutter_chan/services/string.dart';
import 'package:flutter_chan/widgets/cupertino_menu.dart';
import 'package:flutter_chan/widgets/feed_player_recycler.dart';
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
  // Null until the list reports positions; every post counts as on screen.
  Set<int>? _onScreenPostIds;
  bool _hasScrolledToLastWatched = false;
  bool _didStartPreloading = false;
  Timer? _preloadDebounce;
  final Set<int> _preloadedThumbnailIds = <int>{};

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

    _refreshOnScreenPosts();
    _schedulePreloadRefresh();
  }

  void _refreshOnScreenPosts() {
    final Set<int> onScreen = <int>{};
    for (final position in _visiblePositions()) {
      if (position.index < 0 || position.index >= allPosts.length) {
        continue;
      }
      final Post post = allPosts[position.index];
      final int? postId = post.no ?? post.tim;
      if (postId != null) {
        onScreen.add(postId);
      }
    }

    final Set<int>? current = _onScreenPostIds;
    if (!mounted ||
        onScreen.isEmpty ||
        (current != null && _sameIdSet(current, onScreen))) {
      return;
    }

    setState(() {
      _onScreenPostIds = onScreen;
    });
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

  @override
  void dispose() {
    itemPositionsListener.itemPositions.removeListener(
      _markVisiblePostsAsWatched,
    );
    _preloadDebounce?.cancel();
    _preloadDebounce = null;
    scrollController.dispose();
    unawaited(_playerRecycler.dispose());
    super.dispose();
  }

  void loadThread() {
    _hasScrolledToLastWatched = false;
    _didStartPreloading = false;
    _preloadDebounce?.cancel();
    _preloadDebounce = null;
    _preloadedThumbnailIds.clear();
    _preloadVideoPostIds = const <int>{};
    _onScreenPostIds = null;
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
    return CupertinoPageScaffold(
      backgroundColor: AppColors.pageBackground(
        Theme.of(context).brightness == Brightness.dark,
      ),
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          unescape(cleanTags(widget.threadName)),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BookmarkButton(favorite: favorite),
            CupertinoMenuButton(
              icon: CupertinoIcons.ellipsis_circle,
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
        ),
      ),
      child: FutureBuilder(
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
                _startPreloadingIfNeeded();

                if (!_hasScrolledToLastWatched) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    scrollToLastWatchedPosts(allPosts);
                    _hasScrolledToLastWatched = true;
                  });
                }

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
                      top: index == 0
                          ? MediaQuery.paddingOf(context).top + 8
                          : 0,
                    ),
                    child: ThreadPagePost(
                      board: widget.board,
                      thread: widget.thread,
                      post: allPosts[index],
                      allPosts: allPosts,
                      replyCount:
                          _replyDescendantCountByPost[allPosts[index].no] ?? 0,
                      preloadVideo: _preloadVideoPostIds.contains(
                        allPosts[index].no ?? allPosts[index].tim,
                      ),
                      isOnScreen:
                          _onScreenPostIds?.contains(
                            allPosts[index].no ?? allPosts[index].tim,
                          ) ??
                          true,
                      playerRecycler: _playerRecycler,
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
