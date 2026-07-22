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
import 'package:flutter_chan/widgets/reload.dart';
import 'package:liquid_glass_widgets/widgets/containers/glass_divider.dart';
import 'package:liquid_glass_widgets/widgets/input/glass_search_bar.dart';
import 'package:liquid_glass_widgets/widgets/interactive/glass_button.dart';
import 'package:liquid_glass_widgets/widgets/overlays/glass_menu.dart';
import 'package:liquid_glass_widgets/widgets/overlays/glass_menu_item.dart';
import 'package:liquid_glass_widgets/widgets/shared/adaptive_liquid_glass_layer.dart';
import 'package:liquid_glass_widgets/widgets/surfaces/glass_app_bar.dart';
import 'package:liquid_glass_widgets/widgets/surfaces/glass_large_title.dart';
import 'package:liquid_glass_widgets/widgets/surfaces/glass_scaffold.dart';
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
  final _titleController = GlassLargeTitleController();

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

    loadBoard();
  }

  @override
  void dispose() {
    _searchBarController.dispose();
    _titleController.dispose();
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
    if (settings.getBoardViewMode() == ViewMode.list) {
      return BoardListView(board: widget.board, threads: threads);
    }
    return BoardGridView(board: widget.board, threads: threads);
  }

  void _updateThreadsList(String value) {
    fetchAllThreadsFromBoard(
      sort,
      widget.board,
      searchValue: value,
      direction: sortDirection,
    ).then((result) {
      if (mounted) setState(() => filteredBoards = result);
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final favorites = Provider.of<FavoriteProvider>(context);

    isFavorite = favorites.getFavorites().contains(widget.board);

    return GlassScaffold(
      backgroundColor: AppColors.pageBackground(
        Theme.of(context).brightness == Brightness.dark,
      ),
      appBar: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        child: GlassAppBar(
          title: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              '/${widget.board}/ - ${widget.boardName}',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                overflow: TextOverflow.ellipsis,
                color: CupertinoColors.label.resolveFrom(context),
              ),
            ),
          ),
          largeTitleController: _titleController,
          leading: GlassButton(
            icon: const Icon(CupertinoIcons.back),
            onTap: () => Navigator.of(context).pop(),
            width: 40,
            height: 40,
            iconSize: 20,
          ),
          actions: [
            GlassButton(
              icon: Icon(
                isFavorite ? Icons.star_rate : Icons.star_outline,
                color: CupertinoColors.systemYellow,
              ),
              onTap: () => isFavorite
                  ? favorites.removeFavorites(widget.board)
                  : favorites.addFavorites(widget.board),
              width: 40,
              height: 40,
              iconSize: 20,
            ),
            GlassButton(
              icon: Icon(
                settings.getBoardViewMode() == ViewMode.grid
                    ? Icons.view_list
                    : Icons.grid_view,
              ),
              onTap: () {
                final nextMode = settings.getBoardViewMode() == ViewMode.grid
                    ? ViewMode.list
                    : ViewMode.grid;
                settings.setBoardViewMode(nextMode);
              },
              width: 40,
              height: 40,
              iconSize: 20,
            ),
            GlassMenu(
              menuAlignment: GlassMenuAlignment.bottomRight,
              autoAdjustToScreen: true,
              menuWidth: 250,
              menuHeight: 300,
              items: [
                GlassMenuItem(
                  title: 'Image Count',
                  icon: const Icon(CupertinoIcons.photo),
                  isDestructive: false,
                  onTap: () => setSort(Sort.byImagesCount, settings),
                  trailing: sort == Sort.byImagesCount
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                ),
                GlassMenuItem(
                  title: 'Reply Count',
                  icon: const Icon(CupertinoIcons.text_bubble),
                  isDestructive: false,
                  onTap: () => setSort(Sort.byReplyCount, settings),
                  trailing: sort == Sort.byReplyCount
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                ),
                GlassMenuItem(
                  title: 'Bump Order',
                  icon: const Icon(CupertinoIcons.arrow_up_arrow_down),
                  isDestructive: false,
                  onTap: () => setSort(Sort.byBumpOrder, settings),
                  trailing: sort == Sort.byBumpOrder
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                ),
                GlassMenuItem(
                  title: 'Newest',
                  icon: const Icon(CupertinoIcons.clock),
                  isDestructive: false,
                  onTap: () => setSort(Sort.byNewest, settings),
                  trailing: sort == Sort.byNewest
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                ),
                const GlassDivider(),
                GlassMenuItem(
                  title: 'Descending',
                  icon: const Icon(Icons.arrow_downward),
                  isDestructive: false,
                  onTap: () => setSortDirection(SortDirection.desc, settings),
                  trailing: sortDirection == SortDirection.desc
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                ),
                GlassMenuItem(
                  title: 'Ascending',
                  icon: const Icon(Icons.arrow_upward),
                  isDestructive: false,
                  onTap: () => setSortDirection(SortDirection.asc, settings),
                  trailing: sortDirection == SortDirection.asc
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                ),
              ],
              triggerBuilder: (ctx, toggle) => AdaptiveLiquidGlassLayer(
                child: GlassButton(
                  icon: const Icon(Icons.sort),
                  onTap: toggle,
                  width: 40,
                  height: 40,
                  iconSize: 20,
                ),
              ),
            ),
          ],
        ),
      ),
      body: CustomScrollView(
        controller: _titleController.scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.paddingOf(context).top + 44 + 8),
          ),

          GlassLargeTitle(
            text: '/${widget.board}/ - ${widget.boardName}',
            controller: _titleController,
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: GlassSearchBar(
                controller: _searchBarController,
                onChanged: _updateThreadsList,
                useOwnLayer: true,
              ),
            ),
          ),

          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CupertinoActivityIndicator()),
            )
          else if (_hasError)
            SliverFillRemaining(child: ReloadWidget(onReload: loadBoard))
          else
            getBoardSliverView(filteredBoards, settings),
        ],
      ),
    );
  }
}
