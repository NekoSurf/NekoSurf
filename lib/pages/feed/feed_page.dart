import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/api.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/favorite_model.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/constants.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:flutter_chan/pages/board/grid_view.dart';
import 'package:flutter_chan/pages/board/list_view.dart';
import 'package:flutter_chan/widgets/cupertino_menu.dart';
import 'package:flutter_chan/widgets/reload.dart';
import 'package:provider/provider.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({Key? key}) : super(key: key);

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  List<Post> _threads = [];
  bool _isLoading = true;
  bool _hasError = false;

  late Sort _sort;
  late SortDirection _sortDirection;

  @override
  void initState() {
    super.initState();

    final settings = Provider.of<SettingsProvider>(context, listen: false);
    _sort = settings.getBoardSort();
    _sortDirection = settings.getBoardSortDirection();

    _loadFeed();
  }

  Future<void> _loadFeed() async {
    final List<String> boards = List.of(
      Provider.of<FavoriteProvider>(context, listen: false).getFavorites(),
    );

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    // One failing board shouldn't hide the rest of the feed.
    final List<List<Post>?> results = await Future.wait(
      boards.map(
        (board) => fetchAllThreadsFromBoard(_sort, board)
            .then<List<Post>?>((threads) {
              for (final Post thread in threads) {
                thread.board = board;
              }
              return threads;
            })
            .catchError((_) => null),
      ),
    );

    if (!mounted) {
      return;
    }

    final List<List<Post>> loaded = results.whereType<List<Post>>().toList();

    setState(() {
      _threads = _sortThreads(loaded.expand((threads) => threads).toList());
      _isLoading = false;
      _hasError = boards.isNotEmpty && loaded.isEmpty;
    });
  }

  List<Post> _sortThreads(List<Post> threads) {
    int key(Post post) {
      switch (_sort) {
        case Sort.byBumpOrder:
          return post.lastModified ?? 0;
        case Sort.byReplyCount:
          return post.replies ?? 0;
        case Sort.byImagesCount:
          return post.images ?? 0;
        case Sort.byNewest:
        case Sort.byOldest:
          return post.time ?? 0;
      }
    }

    threads.sort((a, b) => key(a).compareTo(key(b)));
    return _sortDirection == SortDirection.desc
        ? threads.reversed.toList()
        : threads;
  }

  void _setSort(Sort sort) {
    _sort = sort;
    _loadFeed();
  }

  void _setSortDirection(SortDirection direction) {
    setState(() {
      _sortDirection = direction;
      _threads = _sortThreads(_threads);
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final List<Post> visibleThreads = settings.getShowStickyThreads()
        ? _threads
        : _threads.where((post) => (post.sticky ?? 0) != 1).toList();

    return CupertinoPageScaffold(
      backgroundColor: AppColors.pageBackground(
        Theme.of(context).brightness == Brightness.dark,
      ),
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Feed'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CupertinoIconButton(
                  icon: settings.getBoardViewMode() == ViewMode.grid
                      ? CupertinoIcons.list_bullet
                      : CupertinoIcons.square_grid_2x2,
                  onPressed: () => settings.setBoardViewMode(
                    settings.getBoardViewMode() == ViewMode.grid
                        ? ViewMode.list
                        : ViewMode.grid,
                  ),
                ),
                CupertinoMenuButton(
                  icon: CupertinoIcons.ellipsis_circle,
                  menuChildren: [
                    buildMenuItem(
                      title: 'Image Count',
                      icon: CupertinoIcons.photo,
                      isSelected: _sort == Sort.byImagesCount,
                      onPressed: () => _setSort(Sort.byImagesCount),
                    ),
                    buildMenuItem(
                      title: 'Reply Count',
                      icon: CupertinoIcons.text_bubble,
                      isSelected: _sort == Sort.byReplyCount,
                      onPressed: () => _setSort(Sort.byReplyCount),
                    ),
                    buildMenuItem(
                      title: 'Bump Order',
                      icon: CupertinoIcons.arrow_up_arrow_down,
                      isSelected: _sort == Sort.byBumpOrder,
                      onPressed: () => _setSort(Sort.byBumpOrder),
                    ),
                    buildMenuItem(
                      title: 'Newest',
                      icon: CupertinoIcons.clock,
                      isSelected: _sort == Sort.byNewest,
                      onPressed: () => _setSort(Sort.byNewest),
                    ),
                    const CupertinoMenuDivider(),
                    buildMenuItem(
                      title: 'Descending',
                      icon: CupertinoIcons.arrow_down,
                      isSelected: _sortDirection == SortDirection.desc,
                      onPressed: () => _setSortDirection(SortDirection.desc),
                    ),
                    buildMenuItem(
                      title: 'Ascending',
                      icon: CupertinoIcons.arrow_up,
                      isSelected: _sortDirection == SortDirection.asc,
                      onPressed: () => _setSortDirection(SortDirection.asc),
                    ),
                    const CupertinoMenuDivider(),
                    buildMenuItem(
                      title: 'Show Sticky Threads',
                      icon: CupertinoIcons.pin,
                      isSelected: settings.getShowStickyThreads(),
                      onPressed: () => settings.setShowStickyThreads(
                        !settings.getShowStickyThreads(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          CupertinoSliverRefreshControl(onRefresh: _loadFeed),
          if (_isLoading && _threads.isEmpty)
            const SliverFillRemaining(
              child: Center(child: CupertinoActivityIndicator()),
            )
          else if (_hasError)
            SliverFillRemaining(child: ReloadWidget(onReload: _loadFeed))
          else if (settings.getBoardViewMode() == ViewMode.grid)
            BoardGridView(board: '', threads: visibleThreads, showBoard: true)
          else
            BoardListView(board: '', threads: visibleThreads, showBoard: true),
        ],
      ),
    );
  }
}
