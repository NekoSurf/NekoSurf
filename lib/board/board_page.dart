import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/board/archive_page.dart';
import 'package:flutter_chan/board/favorite_model.dart';
import 'package:flutter_chan/board/thread_order.dart';
import 'package:flutter_chan/board/thread_views.dart';
import 'package:flutter_chan/chan/api.dart';
import 'package:flutter_chan/chan/catalog.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/ui/back_swipe_route.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_header.dart';
import 'package:flutter_chan/ui/dash_scaffold.dart';
import 'package:flutter_chan/ui/dash_widgets.dart';
import 'package:flutter_chan/ui/pills.dart';
import 'package:flutter_chan/ui/reload.dart';
import 'package:provider/provider.dart';

class BoardPage extends StatefulWidget {
  const BoardPage({super.key, required this.board, required this.boardName});

  final String board;
  final String boardName;

  @override
  State<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends State<BoardPage> with ThreadOrder<BoardPage> {
  final TextEditingController _searchBarController = TextEditingController();

  List<Post> _catalog = [];
  List<Post> _threads = [];
  bool _isLoading = true;
  Object? _error;

  bool _hasArchive = false;

  @override
  void initState() {
    super.initState();

    _loadBoard();

    // boards.json is cached for the session, so this is usually instant.
    fetchAllBoards().then((boards) {
      final bool hasArchive = boards.any(
        (b) => b.board == widget.board && b.hasArchive,
      );
      if (mounted && hasArchive) {
        setState(() => _hasArchive = true);
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _searchBarController.dispose();
    super.dispose();
  }

  /// Downloads the catalog; sorting and searching then work on this copy.
  Future<void> _loadBoard({bool keepShown = false}) async {
    if (!keepShown) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final List<Post> catalog = await fetchCatalog(widget.board);
      if (!mounted) {
        return;
      }
      setState(() {
        _catalog = catalog;
        _isLoading = false;
        _applyView();
      });
    } catch (error) {
      // Pulling to refresh keeps the threads shown if it fails.
      if (mounted && !keepShown) {
        setState(() {
          _isLoading = false;
          _error = error;
        });
      }
    }
  }

  void _applyView() {
    _threads = filterThreads(
      stickyFirst(sortThreads(_catalog, sort, sortDirection)),
      _searchBarController.text,
    );
  }

  @override
  void onOrderChanged() => _applyView();

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final favorites = Provider.of<FavoriteProvider>(context);
    final List<Post> visibleThreads = _threads
        .where(settings.isThreadListed)
        .toList();
    final bool isFavorite = favorites.contains(widget.board);

    return DashScaffold(
      title: widget.boardName,
      onRefresh: () => _loadBoard(keepShown: true),
      actions: [
        DashIconButton(
          label: isFavorite ? 'Remove from favorites' : 'Add to favorites',
          icon: Icon(
            isFavorite ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
            color: CupertinoColors.systemRed,
          ),
          onPressed: () => favorites.toggle(widget.board),
        ),
        const ViewModeButton(),
        if (_hasArchive)
          DashIconButton(
            label: 'Archive',
            icon: const Icon(CupertinoIcons.archivebox),
            onPressed: () => Navigator.of(context).push(
              BackSwipePageRoute(
                builder: (_) => ArchivePage(
                  board: widget.board,
                  boardName: widget.boardName,
                ),
              ),
            ),
          ),
        sortMenu(settings),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: DashPageHeader(
            color: boardColor(widget.board),
            badge: BoardBadge(board: widget.board),
            title: _isLoading
                ? 'Loading...'
                : '${visibleThreads.length} threads',
            subtitle: 'Sorted by ${sort.title.toLowerCase()}',
          ),
        ),
        SliverToBoxAdapter(
          child: DashSearchField(
            controller: _searchBarController,
            onChanged: (_) => setState(_applyView),
          ),
        ),

        if (_isLoading)
          const SliverFillRemaining(
            child: Center(child: CupertinoActivityIndicator()),
          )
        else if (_error != null)
          SliverFillRemaining(
            child: ReloadWidget.forError(_error, onReload: _loadBoard),
          )
        else
          ThreadsView(
            threads: visibleThreads,
            grid: settings.boardViewMode.value == ViewMode.grid,
          ),
      ],
    );
  }
}
