import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/API/api.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/favorite_model.dart';
import 'package:flutter_chan/blocs/history_model.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:flutter_chan/pages/board/grid_view.dart';
import 'package:flutter_chan/pages/board/list_view.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_widgets.dart';
import 'package:flutter_chan/widgets/cupertino_menu.dart';
import 'package:flutter_chan/widgets/dash_dialogs.dart';
import 'package:flutter_chan/widgets/dash_header.dart';
import 'package:flutter_chan/widgets/dash_scaffold.dart';
import 'package:flutter_chan/widgets/reload.dart';
import 'package:provider/provider.dart';

class BoardPage extends StatefulWidget {
  const BoardPage({Key? key, required this.board, required this.boardName})
    : super(key: key);

  final String board;
  final String boardName;

  @override
  BoardPageState createState() => BoardPageState();
}

class BoardPageState extends State<BoardPage> {
  final TextEditingController _searchBarController = TextEditingController();

  List<Post> filteredBoards = [];
  bool _isLoading = true;
  bool _hasError = false;

  bool isFavorite = false;
  late Sort sort;
  late SortDirection sortDirection;

  @override
  void initState() {
    super.initState();

    final settings = Provider.of<SettingsProvider>(context, listen: false);
    sort = settings.getBoardSort();
    sortDirection = settings.getBoardSortDirection();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !settings.getTrackHistory()) {
        return;
      }
      Provider.of<HistoryProvider>(
        context,
        listen: false,
      ).recordBoard(board: widget.board, title: widget.boardName);
    });

    loadBoard();
  }

  @override
  void dispose() {
    _searchBarController.dispose();
    super.dispose();
  }

  void loadBoard() {
    final settings = Provider.of<SettingsProvider>(context, listen: false);

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    fetchAllThreadsFromBoard(
          settings.getBoardSort(),
          widget.board,
          direction: settings.getBoardSortDirection(),
        )
        .then((value) {
          if (mounted) {
            setState(() {
              filteredBoards = value;
              _isLoading = false;
            });
          }
        })
        .catchError((_) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _hasError = true;
            });
          }
        });
  }

  void setSort(Sort sortBy, SettingsProvider settings) {
    _searchBarController.clear();
    setState(() {
      sort = sortBy;
      _isLoading = true;
      _hasError = false;
    });

    fetchAllThreadsFromBoard(sortBy, widget.board, direction: sortDirection)
        .then((value) {
          if (mounted) {
            setState(() {
              filteredBoards = value;
              _isLoading = false;
            });
          }
        })
        .catchError((_) {
          if (mounted)
            setState(() {
              _isLoading = false;
              _hasError = true;
            });
        });
  }

  void setSortDirection(SortDirection newDirection, SettingsProvider settings) {
    _searchBarController.clear();
    setState(() {
      sortDirection = newDirection;
      _isLoading = true;
      _hasError = false;
    });

    fetchAllThreadsFromBoard(sort, widget.board, direction: newDirection)
        .then((value) {
          if (mounted) {
            setState(() {
              filteredBoards = value;
              _isLoading = false;
            });
          }
        })
        .catchError((_) {
          if (mounted)
            setState(() {
              _isLoading = false;
              _hasError = true;
            });
        });
  }

  Widget getBoardSliverView(List<Post> threads, SettingsProvider settings) {
    final visibleThreads = settings.getShowStickyThreads()
        ? threads
        : threads.where((p) => (p.sticky ?? 0) != 1).toList();

    if (settings.getBoardViewMode() == ViewMode.list) {
      return BoardListView(board: widget.board, threads: visibleThreads);
    }
    return BoardGridView(board: widget.board, threads: visibleThreads);
  }

  void _updateThreadsList(String value) {
    fetchAllThreadsFromBoard(
      sort,
      widget.board,
      searchValue: value,
      direction: sortDirection,
    ).then((result) {
      if (mounted) {
        setState(() => filteredBoards = result);
      }
    });
  }

  String get _sortLabel {
    final by = switch (sort) {
      Sort.byImagesCount => 'image count',
      Sort.byReplyCount => 'reply count',
      Sort.byBumpOrder => 'bump order',
      Sort.byNewest => 'newest',
      Sort.byOldest => 'oldest',
    };
    return 'Sorted by $by';
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final settings = Provider.of<SettingsProvider>(context);
    final favorites = Provider.of<FavoriteProvider>(context);
    final List<Post> visibleThreads = filteredBoards
        .where((post) => !settings.isThreadHidden(post))
        .toList();

    isFavorite = favorites.getFavorites().contains(widget.board);

    return DashScaffold(
      title: widget.boardName,
      keyboardDismiss: true,
      actions: [
        DashIconButton(
          icon: Icon(
            isFavorite ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
            color: CupertinoColors.systemRed,
          ),
          onPressed: () => isFavorite
              ? favorites.removeFavorites(widget.board)
              : favorites.addFavorites(widget.board),
        ),
        DashIconButton(
          icon: Icon(
            settings.getBoardViewMode() == ViewMode.grid
                ? CupertinoIcons.list_bullet
                : CupertinoIcons.square_grid_2x2,
          ),
          onPressed: () {
            final nextMode = settings.getBoardViewMode() == ViewMode.grid
                ? ViewMode.list
                : ViewMode.grid;
            settings.setBoardViewMode(nextMode);
          },
        ),
        CupertinoMenuButton(
          isGlass: true,
          menuChildren: [
            buildMenuItem(
              title: 'Image Count',
              icon: CupertinoIcons.photo,
              isSelected: sort == Sort.byImagesCount,
              onPressed: () => setSort(Sort.byImagesCount, settings),
            ),
            buildMenuItem(
              title: 'Reply Count',
              icon: CupertinoIcons.text_bubble,
              isSelected: sort == Sort.byReplyCount,
              onPressed: () => setSort(Sort.byReplyCount, settings),
            ),
            buildMenuItem(
              title: 'Bump Order',
              icon: CupertinoIcons.arrow_up_arrow_down,
              isSelected: sort == Sort.byBumpOrder,
              onPressed: () => setSort(Sort.byBumpOrder, settings),
            ),
            buildMenuItem(
              title: 'Newest',
              icon: CupertinoIcons.clock,
              isSelected: sort == Sort.byNewest,
              onPressed: () => setSort(Sort.byNewest, settings),
            ),
            const DashMenuDivider(),
            buildMenuItem(
              title: 'Descending',
              icon: CupertinoIcons.arrow_down,
              isSelected: sortDirection == SortDirection.desc,
              onPressed: () => setSortDirection(SortDirection.desc, settings),
            ),
            buildMenuItem(
              title: 'Ascending',
              icon: CupertinoIcons.arrow_up,
              isSelected: sortDirection == SortDirection.asc,
              onPressed: () => setSortDirection(SortDirection.asc, settings),
            ),
            const DashMenuDivider(),
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
      slivers: [
        SliverToBoxAdapter(
          child: DashPageHeader(
            isDark: isDark,
            color: boardColor(widget.board),
            badge: Text(
              '/${widget.board}/',
              style: TextStyle(
                fontSize: widget.board.length > 3 ? 13 : 17,
                fontWeight: FontWeight.w800,
                color: boardColor(widget.board),
              ),
            ),
            title: _isLoading ? 'Loading...' : '${visibleThreads.length} threads',
            subtitle: _sortLabel,
          ),
        ),
        SliverToBoxAdapter(
          child: DashSearchField(
            isDark: isDark,
            controller: _searchBarController,
            onChanged: _updateThreadsList,
          ),
        ),

        if (_isLoading)
          const SliverFillRemaining(
            child: Center(child: CupertinoActivityIndicator()),
          )
        else if (_hasError)
          SliverFillRemaining(child: ReloadWidget(onReload: loadBoard))
        else
          getBoardSliverView(visibleThreads, settings),
      ],
    );
  }
}
