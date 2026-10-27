import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/api.dart';
import 'package:flutter_chan/Models/board.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/favorite_model.dart';
import 'package:flutter_chan/blocs/history_model.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/pages/board/board_page.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_widgets.dart';
import 'package:flutter_chan/pages/feed/feed_page.dart';
import 'package:flutter_chan/pages/thread/thread_page.dart';
import 'package:flutter_chan/services/string.dart';
import 'package:flutter_chan/widgets/reload.dart';
import 'package:provider/provider.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({Key? key, required this.onSelectTab}) : super(key: key);

  final ValueChanged<int> onSelectTab;

  @override
  State<Dashboard> createState() => DashboardState();
}

class DashboardState extends State<Dashboard> {
  late Future<List<Board>> _boardsFuture;
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _load({bool refresh = false}) {
    _boardsFuture = fetchAllBoards(refresh: refresh);
    Provider.of<HistoryProvider>(
      context,
      listen: false,
    ).checkThreads(force: refresh);
  }

  Future<void> refresh() {
    setState(() => _load(refresh: true));
    return _boardsFuture.then((_) {}, onError: (_) {});
  }

  void _openFeed() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const FeedPage()));
  }

  void _openBoard(String code, String title) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BoardPage(board: code, boardName: title),
      ),
    );
  }

  void _openThread(HistoryThread t) {
    final imageUrl = t.imageUrl;
    final tim = imageUrl != null && imageUrl.length > 5
        ? int.tryParse(imageUrl.substring(0, imageUrl.length - 5))
        : null;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ThreadPage(
          post: Post(
            no: t.no,
            sub: t.title,
            com: t.com,
            tim: tim,
            board: t.board,
          ),
          threadName: t.title.isNotEmpty ? t.title : 'No.${t.no}',
          thread: t.no,
          board: t.board,
        ),
      ),
    );
  }

  bool _isVisible(Board b, bool nsfw) => nsfw || b.wsBoard != 0;

  bool _matches(Board b) {
    final q = _query.toLowerCase();
    return (b.board ?? '').toLowerCase().contains(q) ||
        (b.title ?? '').toLowerCase().contains(q) ||
        (b.metaDescription ?? '').toLowerCase().contains(q);
  }

  Widget _row(Board b, bool isDark, FavoriteProvider favorites) {
    final code = b.board ?? '';
    return DashBoardRow(
      board: code,
      title: b.title ?? '',
      description: cleanTags(unescape(b.metaDescription ?? '')),
      isDark: isDark,
      isFavorite: favorites.getFavorites().contains(code),
      nsfw: b.wsBoard == 0,
      onTap: () => _openBoard(code, b.title ?? ''),
      onToggleFavorite: () => favorites.getFavorites().contains(code)
          ? favorites.removeFavorites(code)
          : favorites.addFavorites(code),
    );
  }

  Widget _group(List<Widget> rows, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DashCard(
        isDark: isDark,
        child: Column(
          children: [
            for (int i = 0; i < rows.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  indent: 68,
                  color: DashColors.border(isDark),
                ),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }

  Widget _searchField(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: CupertinoSearchTextField(
        controller: _search,
        placeholder: 'Search boards',
        backgroundColor: DashColors.card(isDark),
        onChanged: (v) => setState(() => _query = v.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final favorites = Provider.of<FavoriteProvider>(context);
    final history = Provider.of<HistoryProvider>(context);
    final nsfw = Provider.of<SettingsProvider>(context).getNSFW();

    return SliverToBoxAdapter(
      child: FutureBuilder<List<Board>>(
        future: _boardsFuture,
        builder: (context, snapshot) {
          final boards = (snapshot.data ?? const <Board>[])
              .where((b) => b.board != null && _isVisible(b, nsfw))
              .toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DashHero(isDark: isDark),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Center(child: CupertinoActivityIndicator()),
                )
              else if (snapshot.hasError)
                ReloadWidget(onReload: () => setState(_load))
              else
                ..._sections(boards, isDark, favorites, history),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _sections(
    List<Board> boards,
    bool isDark,
    FavoriteProvider favorites,
    HistoryProvider history,
  ) {
    final favoriteBoards = boards
        .where((b) => favorites.getFavorites().contains(b.board))
        .toList();

    final sorted = [...boards]..sort((a, b) => a.board!.compareTo(b.board!));
    final visibleBoards = _query.isEmpty
        ? sorted
        : sorted.where(_matches).toList();

    return [
      if (history.threads.isNotEmpty) ...[
        DashSectionHeader(
          title: 'Continue',
          isDark: isDark,
          actionLabel: 'Clear',
          onAction: history.clear,
        ),
        SizedBox(
          height: 170,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: history.threads.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final t = history.threads[i];
              return DashThreadCard(
                thread: t,
                isDark: isDark,
                isArchived: history.isArchived(t),
                onTap: () => _openThread(t),
                onRemove: () => history.removeThread(t),
              );
            },
          ),
        ),
      ],
      if (favoriteBoards.isNotEmpty) ...[
        DashSectionHeader(title: 'Favorites', isDark: isDark),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: DashFeedCard(
            isDark: isDark,
            boardCount: favorites.getFavorites().length,
            onTap: _openFeed,
          ),
        ),
        _group([
          for (final b in favoriteBoards) _row(b, isDark, favorites),
        ], isDark),
      ],
      DashSectionHeader(title: 'All boards', isDark: isDark),
      _searchField(isDark),
      if (visibleBoards.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Center(
            child: Text(
              'No boards match',
              style: TextStyle(color: DashColors.muted(isDark)),
            ),
          ),
        )
      else
        _group([
          for (final b in visibleBoards) _row(b, isDark, favorites),
        ], isDark),
    ];
  }
}
