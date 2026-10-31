import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/API/api.dart';
import 'package:flutter_chan/API/archive.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:flutter_chan/pages/board/grid_post.dart';
import 'package:flutter_chan/pages/board/list_post.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_widgets.dart';
import 'package:flutter_chan/widgets/dash_header.dart';
import 'package:flutter_chan/widgets/dash_scaffold.dart';
import 'package:flutter_chan/widgets/reload.dart';
import 'package:provider/provider.dart';

/// A board's archived threads, newest first.
///
/// 4chan's archive lists only thread numbers, so each row fetches its own
/// preview through [ArchivePreviewLoader] as it scrolls into view.
class ArchivePage extends StatefulWidget {
  const ArchivePage({super.key, required this.board, required this.boardName});

  final String board;
  final String boardName;

  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  late final ArchivePreviewLoader _loader = ArchivePreviewLoader(widget.board);
  final TextEditingController _search = TextEditingController();

  List<int> _threads = const <int>[];
  bool _isLoading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _loader.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final List<int> threads = await fetchArchive(widget.board);
      if (mounted) {
        setState(() {
          _threads = threads;
          _isLoading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final Color color = boardColor(widget.board);
    final settings = Provider.of<SettingsProvider>(context);
    // Same setting as the boards, so the archive opens in the layout you
    // browse with.
    final bool grid = settings.getBoardViewMode() == ViewMode.grid;

    return DashScaffold(
      title: 'Archive',
      subtitle: '/${widget.board}/ · ${widget.boardName}',
      keyboardDismiss: true,
      actions: [
        DashIconButton(
          icon: Icon(
            grid ? CupertinoIcons.list_bullet : CupertinoIcons.square_grid_2x2,
          ),
          onPressed: () =>
              settings.setBoardViewMode(grid ? ViewMode.list : ViewMode.grid),
        ),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: DashPageHeader(
            isDark: isDark,
            color: color,
            badge: Text(
              '/${widget.board}/',
              style: TextStyle(
                fontSize: widget.board.length > 3 ? 13 : 17,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            title: _isLoading
                ? 'Loading...'
                : '${_threads.length} archived threads',
            subtitle: 'Newest first · previews load as you scroll',
          ),
        ),
        if (!_isLoading && _error == null)
          SliverToBoxAdapter(
            child: DashSearchField(
              isDark: isDark,
              controller: _search,
              placeholder: 'Search loaded threads',
              onChanged: (_) => setState(() {}),
            ),
          ),
        if (_isLoading)
          const SliverFillRemaining(
            child: Center(child: CupertinoActivityIndicator()),
          )
        else if (_error != null)
          SliverFillRemaining(
            child: ReloadWidget.forError(_error, onReload: _load),
          )
        else
          ListenableBuilder(
            listenable: _loader,
            builder: (context, _) => _search.text.trim().isEmpty
                ? _buildAll(grid)
                : _buildSearchResults(isDark, grid),
          ),
      ],
    );
  }

  Widget _buildAll(bool grid) {
    Widget row(BuildContext context, int index) {
      final int no = _threads[index];
      return _ArchiveRow(
        key: ValueKey<int>(no),
        board: widget.board,
        no: no,
        loader: _loader,
        grid: grid,
      );
    }

    return grid
        ? _gridSliver(_threads.length, row)
        : SliverPadding(
            padding: const EdgeInsets.only(top: 6, bottom: 16),
            sliver: SliverList.builder(
              itemCount: _threads.length,
              itemBuilder: row,
            ),
          );
  }

  /// Same layout as the board grid (BoardGridView).
  Widget _gridSliver(int count, NullableIndexedWidgetBuilder itemBuilder) {
    final int crossCount = (MediaQuery.sizeOf(context).width / 230).floor();

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 18),
      sliver: SliverGrid.builder(
        itemCount: count,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: max(2, crossCount),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.82,
        ),
        itemBuilder: itemBuilder,
      ),
    );
  }

  /// Searching every archived thread would mean downloading thousands of
  /// them, so search covers only the previews loaded so far.
  Widget _buildSearchResults(bool isDark, bool grid) {
    final Set<int> archived = _threads.toSet();
    final List<Post> matches = filterThreads(
      _loader.loadedPosts.where((post) => archived.contains(post.no)).toList(),
      _search.text,
    )..sort((a, b) => (b.no ?? 0).compareTo(a.no ?? 0));

    if (matches.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
          child: Text(
            'No loaded thread matches. Scroll the archive to load more '
            'previews, then search again.',
            textAlign: TextAlign.center,
            style: TextStyle(color: DashColors.muted(isDark)),
          ),
        ),
      );
    }

    if (grid) {
      return _gridSliver(
        matches.length,
        (context, index) => GridPost(
          key: ValueKey('archive-${matches[index].no}'),
          board: widget.board,
          post: matches[index],
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.only(top: 6, bottom: 16),
      sliver: SliverList.builder(
        itemCount: matches.length,
        itemBuilder: (context, index) => ListPost(
          key: ValueKey('archive-${matches[index].no}'),
          board: widget.board,
          post: matches[index],
        ),
      ),
    );
  }
}

/// Queues its thread's preview while it's built and withdraws the request
/// when it's scrolled away.
class _ArchiveRow extends StatefulWidget {
  const _ArchiveRow({
    super.key,
    required this.board,
    required this.no,
    required this.loader,
    required this.grid,
  });

  final String board;
  final int no;
  final ArchivePreviewLoader loader;
  final bool grid;

  @override
  State<_ArchiveRow> createState() => _ArchiveRowState();
}

class _ArchiveRowState extends State<_ArchiveRow> {
  @override
  void initState() {
    super.initState();
    widget.loader.want(widget.no);
  }

  @override
  void dispose() {
    widget.loader.unwant(widget.no);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Post? post = widget.loader.post(widget.no);
    if (post != null) {
      return widget.grid
          ? GridPost(board: widget.board, post: post)
          : ListPost(board: widget.board, post: post);
    }

    final bool isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final bool failed = widget.loader.hasFailed(widget.no);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: failed ? () => widget.loader.retry(widget.no) : null,
      child: widget.grid
          ? _buildGridPlaceholder(isDark, failed)
          : _buildListPlaceholder(isDark, failed),
    );
  }

  String _status(bool failed) =>
      failed ? 'Couldn’t load · tap to retry' : 'Loading preview…';

  /// Shaped like a GridPost tile: image area on top, number below.
  Widget _buildGridPlaceholder(bool isDark, bool failed) {
    return Container(
      decoration: BoxDecoration(
        color: DashColors.card(isDark),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: DashColors.border(isDark)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ColoredBox(
              color: DashColors.border(isDark),
              child: Center(
                child: Icon(
                  failed
                      ? CupertinoIcons.exclamationmark_circle
                      : CupertinoIcons.archivebox,
                  size: 28,
                  color: DashColors.muted(isDark),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No.${widget.no}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: DashColors.text(isDark),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _status(failed),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: DashColors.muted(isDark),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListPlaceholder(bool isDark, bool failed) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      padding: const EdgeInsets.all(14),
      // Close to a loaded ListPost card, so rows filling in above the
      // viewport don't push what you're reading down the screen.
      height: 190,
      decoration: BoxDecoration(
        color: DashColors.card(isDark),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: DashColors.border(isDark)),
      ),
      child: Row(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: DashColors.border(isDark),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              failed
                  ? CupertinoIcons.exclamationmark_circle
                  : CupertinoIcons.archivebox,
              color: DashColors.muted(isDark),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No.${widget.no}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: DashColors.text(isDark),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _status(failed),
                  style: TextStyle(
                    fontSize: 13,
                    color: DashColors.muted(isDark),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
