import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/board/favorite_model.dart';
import 'package:flutter_chan/board/feed_page.dart';
import 'package:flutter_chan/chan/api.dart';
import 'package:flutter_chan/chan/board.dart';
import 'package:flutter_chan/chan/post_text.dart';
import 'package:flutter_chan/history/history_page.dart';
import 'package:flutter_chan/home/dashboard_widgets.dart';
import 'package:flutter_chan/home/open_link_dialog.dart';
import 'package:flutter_chan/search/search_page.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/ui/back_swipe_route.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_header.dart';
import 'package:flutter_chan/ui/dash_scaffold.dart';
import 'package:flutter_chan/ui/dash_widgets.dart';
import 'package:flutter_chan/ui/open.dart';
import 'package:flutter_chan/ui/reload.dart';
import 'package:provider/provider.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
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

  Future<void> _refresh() {
    setState(() => _load(refresh: true));
    return _boardsFuture.then((_) {}, onError: (_) {});
  }

  void _push(Widget page) {
    Navigator.of(context).push(BackSwipePageRoute<void>(builder: (_) => page));
  }

  bool _isVisible(Board b, bool nsfw) => nsfw || !b.isNsfw;

  bool _matches(Board b) {
    final q = _query.toLowerCase();
    return b.board.toLowerCase().contains(q) ||
        b.title.toLowerCase().contains(q) ||
        (b.metaDescription ?? '').toLowerCase().contains(q);
  }

  Widget _row(Board b, bool isDark, FavoriteProvider favorites) {
    final String code = b.board;
    return DashBoardRow(
      board: code,
      title: b.title,
      description: plainText(b.metaDescription ?? ''),
      isFavorite: favorites.contains(code),
      nsfw: b.isNsfw,
      onTap: () => openBoard(context, code, name: b.title),
      onToggleFavorite: () => favorites.toggle(code),
    );
  }

  Widget _group(List<Widget> rows, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DashCard(
        child: Column(
          children: [
            for (int i = 0; i < rows.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  indent: 68,
                  color: DashColors.border(context),
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
        backgroundColor: DashColors.card(context),
        onChanged: (v) => setState(() => _query = v.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;
    final favorites = Provider.of<FavoriteProvider>(context);
    final nsfw = Provider.of<SettingsProvider>(context).allowNSFW.value;

    return DashScaffold(
      title: 'NekoSurf',
      subtitle: 'Browse the boards',
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.asset(
          'assets/icons/icon-round.png',
          width: 38,
          height: 38,
        ),
      ),
      actions: [
        DashIconButton(
          label: 'History',
          icon: const Icon(CupertinoIcons.clock),
          onPressed: () => _push(const HistoryPage()),
        ),
        DashIconButton(
          label: 'Search',
          icon: const Icon(CupertinoIcons.search),
          onPressed: () => _push(const SearchPage()),
        ),
        DashIconButton(
          label: 'Open a link',
          icon: const Icon(CupertinoIcons.link),
          onPressed: () => showOpenLinkDialog(context),
        ),
      ],
      reserveTabBarSpace: true,
      onRefresh: _refresh,
      slivers: [
        SliverToBoxAdapter(
          child: FutureBuilder<List<Board>>(
            future: _boardsFuture,
            builder: (context, snapshot) {
              final boards = (snapshot.data ?? const <Board>[])
                  .where((b) => _isVisible(b, nsfw))
                  .toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const DashHero(),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.only(top: 60),
                      child: Center(child: CupertinoActivityIndicator()),
                    )
                  else if (snapshot.hasError)
                    ReloadWidget.forError(
                      snapshot.error,
                      onReload: () => setState(_load),
                    )
                  else
                    ..._sections(boards, isDark, favorites),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  List<Widget> _sections(
    List<Board> boards,
    bool isDark,
    FavoriteProvider favorites,
  ) {
    final favoriteBoards = boards
        .where((b) => favorites.contains(b.board))
        .toList();

    final sorted = [...boards]..sort((a, b) => a.board.compareTo(b.board));
    final visibleBoards = _query.isEmpty
        ? sorted
        : sorted.where(_matches).toList();

    return [
      if (favoriteBoards.isNotEmpty) ...[
        const DashSectionHeader(title: 'Favorites'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: DashFeedCard(
            boardCount: favorites.boards.length,
            onTap: () => _push(const FeedPage()),
          ),
        ),
        _group([
          for (final b in favoriteBoards) _row(b, isDark, favorites),
        ], isDark),
      ],
      const DashSectionHeader(title: 'All boards'),
      _searchField(isDark),
      if (visibleBoards.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Center(
            child: Text(
              'No boards match',
              style: TextStyle(color: DashColors.muted(context)),
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
