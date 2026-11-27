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
import 'package:flutter_chan/ui/dash_header.dart';
import 'package:flutter_chan/ui/dash_menu.dart';
import 'package:flutter_chan/ui/dash_scaffold.dart';
import 'package:flutter_chan/ui/dash_widgets.dart';
import 'package:flutter_chan/ui/haptics.dart';
import 'package:flutter_chan/ui/master_detail.dart';
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
  final FocusNode _searchFocus = FocusNode();

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
    _searchFocus.dispose();
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

    return MasterDetail(
      master: DashScaffold(
        title: widget.boardName,
        subtitle: _isLoading
            ? '/${widget.board}/'
            : '/${widget.board}/ · ${_count(visibleThreads.length)}',
        readable: settings.boardViewMode.value == ViewMode.list,
        onRefresh: () => _loadBoard(keepShown: true),
        onFind: _searchFocus.requestFocus,
        actions: [
          DashIconButton(
            label: isFavorite ? 'Remove from favorites' : 'Add to favorites',
            icon: Icon(
              isFavorite ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
              color: CupertinoColors.systemRed,
            ),
            onPressed: () {
              keepFeedback();
              favorites.toggle(widget.board);
            },
          ),
          // The rest in one menu, so the board's name has the room.
          sortMenu(
            settings,
            leading: [
              viewModeEntry(settings),
              if (_hasArchive)
                DashMenuEntry(
                  title: 'Archive',
                  icon: CupertinoIcons.archivebox,
                  onPressed: () => Navigator.of(context).push(
                    BackSwipePageRoute(
                      builder: (_) => ArchivePage(
                        board: widget.board,
                        boardName: widget.boardName,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        slivers: [
          SliverToBoxAdapter(
            child: DashSearchField(
              controller: _searchBarController,
              focusNode: _searchFocus,
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
              isDimmed: settings.matchesThreadFilter,
            ),
        ],
      ),
    );
  }
}

/// "1 thread", "152 threads".
String _count(int threads) => '$threads ${threads == 1 ? 'thread' : 'threads'}';
