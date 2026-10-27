import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/api.dart';
import 'package:flutter_chan/API/archive.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/pages/board/list_post.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_widgets.dart';
import 'package:flutter_chan/widgets/dash_scaffold.dart';
import 'package:flutter_chan/widgets/reload.dart';

/// A board's archived threads, newest first.
///
/// 4chan's archive lists only thread numbers, so each row fetches its own
/// preview through [ArchivePreviewLoader] as it scrolls into view.
class ArchivePage extends StatefulWidget {
  const ArchivePage({Key? key, required this.board, required this.boardName})
    : super(key: key);

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
  bool _hasError = false;

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
      _hasError = false;
    });

    try {
      final List<int> threads = await fetchArchive(widget.board);
      if (mounted) {
        setState(() {
          _threads = threads;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final Color color = boardColor(widget.board);

    return DashScaffold(
      title: 'Archive',
      subtitle: '/${widget.board}/ · ${widget.boardName}',
      keyboardDismiss: true,
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
        if (!_isLoading && !_hasError)
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
        else if (_hasError)
          SliverFillRemaining(child: ReloadWidget(onReload: _load))
        else
          ListenableBuilder(
            listenable: _loader,
            builder: (context, _) => _search.text.trim().isEmpty
                ? _buildAll()
                : _buildSearchResults(isDark),
          ),
      ],
    );
  }

  Widget _buildAll() {
    return SliverPadding(
      padding: const EdgeInsets.only(top: 6, bottom: 16),
      sliver: SliverList.builder(
        itemCount: _threads.length,
        itemBuilder: (context, index) {
          final int no = _threads[index];
          return _ArchiveRow(
            key: ValueKey<int>(no),
            board: widget.board,
            no: no,
            loader: _loader,
          );
        },
      ),
    );
  }

  /// Searching every archived thread would mean downloading thousands of
  /// them, so search covers only the previews loaded so far.
  Widget _buildSearchResults(bool isDark) {
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
    Key? key,
    required this.board,
    required this.no,
    required this.loader,
  }) : super(key: key);

  final String board;
  final int no;
  final ArchivePreviewLoader loader;

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
      return ListPost(board: widget.board, post: post);
    }

    final bool isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final bool failed = widget.loader.hasFailed(widget.no);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: failed ? () => widget.loader.retry(widget.no) : null,
      child: Container(
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
                    failed
                        ? 'Couldn’t load · tap to retry'
                        : 'Loading preview…',
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
      ),
    );
  }
}
