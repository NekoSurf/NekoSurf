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
import 'package:liquid_glass_widgets/types/glass_quality.dart';
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
  final ScrollController scrollController = ScrollController();
  final TextEditingController _searchBarController = TextEditingController();
  final _titleController = GlassLargeTitleController();

  late Future<List<Post>> _fetchAllThreadsFromBoard;

  late List<Post> filteredBoards;

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
    scrollController.dispose();
    _searchBarController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void loadBoard() {
    final settings = Provider.of<SettingsProvider>(context, listen: false);

    setState(() {
      _fetchAllThreadsFromBoard = fetchAllThreadsFromBoard(
        settings.getBoardSort(),
        widget.board,
        direction: settings.getBoardSortDirection(),
      ).then((value) => filteredBoards = value);
    });
  }

  void setSort(Sort sortBy, SettingsProvider settings) {
    setState(() {
      _searchBarController.clear();

      _fetchAllThreadsFromBoard = fetchAllThreadsFromBoard(
        sortBy,
        widget.board,
        direction: sortDirection,
      ).then((value) => filteredBoards = value);

      sort = sortBy;
    });
  }

  void toggleSortDirection(SettingsProvider settings) {
    final newDirection = sortDirection == SortDirection.asc
        ? SortDirection.desc
        : SortDirection.asc;
    settings.setBoardSortDirection(newDirection);
    setState(() {
      sortDirection = newDirection;
      _searchBarController.clear();

      _fetchAllThreadsFromBoard = fetchAllThreadsFromBoard(
        sort,
        widget.board,
        direction: newDirection,
      ).then((value) => filteredBoards = value);
    });
  }

  Widget getBoardView(List<Post> threads, SettingsProvider settings) {
    if (settings.getBoardViewMode() == ViewMode.list) {
      return BoardListView(
        scrollController: scrollController,
        board: widget.board,
        threads: threads,
      );
    }
    return BoardGridView(
      scrollController: scrollController,
      board: widget.board,
      threads: threads,
    );
  }

  void _updateThreadsList(String value) {
    _fetchAllThreadsFromBoard = fetchAllThreadsFromBoard(
      sort,
      widget.board,
      searchValue: value,
      direction: sortDirection,
    ).then((value) => filteredBoards = value);

    setState(() {});
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
          title: Text(
            '/${widget.board}/ - ${widget.boardName}',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: CupertinoColors.label.resolveFrom(context),
            ),
          ),
          largeTitleController: _titleController,
          leading: GlassButton(
            icon: const Icon(CupertinoIcons.back),
            onTap: () => Navigator.of(context).pop(),
            width: 40,
            height: 40,
            iconSize: 20,
            quality: GlassQuality.premium,
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
              quality: GlassQuality.premium,
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
              quality: GlassQuality.premium,
            ),
            GlassButton(
              icon: Icon(
                sortDirection == SortDirection.asc
                    ? Icons.arrow_upward
                    : Icons.arrow_downward,
              ),
              onTap: () => toggleSortDirection(settings),
              width: 40,
              height: 40,
              iconSize: 20,
              quality: GlassQuality.premium,
            ),
            GlassMenu(
              menuAlignment: GlassMenuAlignment.bottomRight,
              autoAdjustToScreen: true,
              quality: GlassQuality.premium,
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
              ],
              triggerBuilder: (ctx, toggle) => AdaptiveLiquidGlassLayer(
                child: GlassButton(
                  icon: const Icon(Icons.sort),
                  onTap: toggle,
                  width: 40,
                  height: 40,
                  iconSize: 20,
                  quality: GlassQuality.premium,
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

          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: GlassSearchBar(
                  controller: _searchBarController,
                  onChanged: (value) {
                    _updateThreadsList(value);
                  },
                  useOwnLayer: true,
                  quality: GlassQuality.premium,
                ),
              ),

              FutureBuilder(
                future: _fetchAllThreadsFromBoard,
                builder:
                    (BuildContext context, AsyncSnapshot<List<Post>> snapshot) {
                      switch (snapshot.connectionState) {
                        case ConnectionState.waiting:
                          return const SizedBox(
                            height: 400,
                            child: Center(child: CupertinoActivityIndicator()),
                          );
                        default:
                          if (snapshot.hasError) {
                            return ReloadWidget(onReload: () => {loadBoard()});
                          } else {
                            return getBoardView(filteredBoards, settings);
                          }
                      }
                    },
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
