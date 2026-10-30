import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/api.dart';
import 'package:flutter_chan/Models/board.dart';
import 'package:flutter_chan/blocs/favorite_model.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/pages/board/board_page.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_widgets.dart';
import 'package:flutter_chan/pages/feed/feed_page.dart';
import 'package:flutter_chan/services/string.dart';
import 'package:flutter_chan/widgets/reload.dart';
import 'package:provider/provider.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key, required this.onSelectTab});

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
                ..._sections(boards, isDark, favorites),
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
  ) {
    final favoriteBoards = boards
        .where((b) => favorites.getFavorites().contains(b.board))
        .toList();

    final sorted = [...boards]..sort((a, b) => a.board!.compareTo(b.board!));
    final visibleBoards = _query.isEmpty
        ? sorted
        : sorted.where(_matches).toList();

    return [
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
