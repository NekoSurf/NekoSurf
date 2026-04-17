import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/api.dart';
import 'package:flutter_chan/Models/bookmark.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/blocs/watched_media_model.dart';
import 'package:flutter_chan/constants.dart';
import 'package:flutter_chan/pages/bookmark_button.dart';
import 'package:flutter_chan/pages/thread/thread_page_post.dart';
import 'package:flutter_chan/services/string.dart';
import 'package:flutter_chan/widgets/floating_action_buttons.dart';
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
  final ScrollController scrollController = ScrollController();
  final ItemScrollController itemScrollController = ItemScrollController();
  final ItemPositionsListener itemPositionsListener =
      ItemPositionsListener.create();

  late Future<List<Post>> _fetchAllPostsFromThread;

  List<Post> allPosts = [];
  bool _hasScrolledToLastWatched = false;

  late Bookmark favorite;
  void _markVisiblePostsAsWatched() {
    if (allPosts.isEmpty) {
      return;
    }

    final watchedMedia = Provider.of<WatchedMediaProvider>(
      context,
      listen: false,
    );

    final positions = itemPositionsListener.itemPositions.value;

    for (final position in positions) {
      final double trailing = position.itemTrailingEdge < 0
          ? 0
          : (position.itemTrailingEdge > 1 ? 1 : position.itemTrailingEdge);
      final double leading = position.itemLeadingEdge < 0
          ? 0
          : (position.itemLeadingEdge > 1 ? 1 : position.itemLeadingEdge);
      final double visiblePortion = trailing - leading;

      if (visiblePortion < 0.55) {
        continue;
      }

      final int index = position.index;
      if (index < 0 || index >= allPosts.length) {
        continue;
      }

      final Post post = allPosts[index];
      final int? watchedId = post.tim ?? post.no;

      if (watchedId == null) {
        continue;
      }

      watchedMedia.markAsWatched(
        mediaId: watchedId,
        thread: widget.thread,
        fileName: post.filename ?? '',
        ext: post.ext ?? '',
      );
    }
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
    scrollController.dispose();
    super.dispose();
  }

  void loadThread() {
    setState(() {
      _fetchAllPostsFromThread = fetchAllPostsFromThread(
        widget.board,
        widget.thread,
      );
    });
  }

  void scrollToLastWatchedMedia(List<Post> allPosts) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final watchedMedia = Provider.of<WatchedMediaProvider>(
      context,
      listen: false,
    );

    if (!settings.getAutoScrollToLastSeen()) {
      return;
    }

    final latestWatchedMedia = watchedMedia.getLatestWatchedMedia(
      widget.thread,
    );

    if (latestWatchedMedia != null) {
      final index = allPosts.indexWhere(
        (post) =>
            post.tim == latestWatchedMedia.mediaId ||
            post.no == latestWatchedMedia.mediaId,
      );

      if (index != -1) {
        Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted && itemScrollController.isAttached) {
            itemScrollController.scrollTo(
              index: index,
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
        goUp: () => {
          itemScrollController.scrollTo(
            index: 0,
            alignment: 0,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOutCubic,
          ),
        },
        goDown: () => {
          itemScrollController.scrollTo(
            index: allPosts.length,
            alignment: 0,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOutCubic,
          ),
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

                if (!_hasScrolledToLastWatched) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    scrollToLastWatchedMedia(allPosts);
                    _hasScrolledToLastWatched = true;
                  });
                }

                return SafeArea(
                  top: true,
                  bottom: false,
                  child: ScrollablePositionedList.builder(
                    shrinkWrap: false,
                    itemCount: allPosts.length,
                    physics: const ClampingScrollPhysics(),
                    itemScrollController: itemScrollController,
                    itemPositionsListener: itemPositionsListener,
                    itemBuilder: (context, index) => ThreadPagePost(
                      board: widget.board,
                      thread: widget.thread,
                      post: allPosts[index],
                      allPosts: allPosts,
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
