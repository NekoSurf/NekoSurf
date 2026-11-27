import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/board/archive_page.dart';
import 'package:flutter_chan/board/favorite_model.dart';
import 'package:flutter_chan/board/feed_page.dart';
import 'package:flutter_chan/bookmarks/bookmark.dart';
import 'package:flutter_chan/bookmarks/bookmarks_model.dart';
import 'package:flutter_chan/chan/api.dart';
import 'package:flutter_chan/chan/board.dart';
import 'package:flutter_chan/chan/post_text.dart';
import 'package:flutter_chan/history/history_model.dart';
import 'package:flutter_chan/history/history_page.dart';
import 'package:flutter_chan/history/new_replies.dart';
import 'package:flutter_chan/home/dashboard_widgets.dart';
import 'package:flutter_chan/home/open_link_dialog.dart';
import 'package:flutter_chan/home/thread_cards.dart';
import 'package:flutter_chan/search/search_page.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/ui/back_swipe_route.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_header.dart';
import 'package:flutter_chan/ui/dash_menu.dart';
import 'package:flutter_chan/ui/dash_scaffold.dart';
import 'package:flutter_chan/ui/dash_widgets.dart';
import 'package:flutter_chan/ui/haptics.dart';
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

  /// Threads in "Continue reading", at most.
  static const int _continueCount = 10;

  @override
  void initState() {
    super.initState();
    _load();
    // For how many replies are new in "Continue reading".
    Provider.of<HistoryProvider>(context, listen: false).checkThreads();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _load({bool refresh = false}) {
    final SettingsProvider settings = Provider.of<SettingsProvider>(
      context,
      listen: false,
    );
    _boardsFuture = fetchAllBoards(refresh: refresh).then((boards) {
      // So bookmarks, history and search know which to leave out.
      settings.rememberBoards(boards);
      return boards;
    });
  }

  Future<void> _refresh() {
    setState(() => _load(refresh: true));
    return Future.wait([
      _boardsFuture.then((_) {}, onError: (_) {}),
      Provider.of<HistoryProvider>(
        context,
        listen: false,
      ).checkThreads(force: true),
    ]);
  }

  /// The threads "Continue reading" shows, newest first: none when it's
  /// turned off in Settings.
  List<HistoryThread> _continueThreads(
    SettingsProvider settings,
    HistoryProvider history,
  ) {
    if (!settings.showContinueReading.value) {
      return const [];
    }
    return history.threads
        .where((t) => !history.isDeleted(t) && !settings.hidesBoard(t.board))
        .take(_continueCount)
        .toList();
  }

  /// "Continue reading": [threads] as big picture cards with how many
  /// replies are new, and a link to History.
  List<Widget> _continueReading(
    HistoryProvider history,
    List<HistoryThread> threads,
  ) {
    if (threads.isEmpty) {
      return const [];
    }
    return [
      DashSectionHeader(
        title: 'Continue reading',
        top: 8,
        trailing: DashSectionLink(
          'History',
          onTap: () => _push(const HistoryPage()),
        ),
      ),
      ThreadCardRow(
        cards: [
          for (final HistoryThread t in threads)
            ThreadCard(
              post: t.toPost(),
              onTap: () => openThread(context, t.toPost()),
              onMenu: (cardContext) => _continueMenu(cardContext, history, t),
              badge: NewRepliesCount(
                thread: t.no,
                replies: history.replies(t),
                builder: (context, newReplies) => newReplies > 0
                    ? NewRepliesBadge(count: newReplies, short: true)
                    : const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    ];
  }

  /// What holding a Continue reading card offers: bookmarking it, and taking
  /// it out of History, and so out of the row.
  void _continueMenu(
    BuildContext cardContext,
    HistoryProvider history,
    HistoryThread thread,
  ) {
    final BookmarksProvider bookmarks = Provider.of<BookmarksProvider>(
      context,
      listen: false,
    );
    final Bookmark bookmark = Bookmark.fromPost(thread.toPost());
    final bool isBookmarked = bookmarks.isBookmarked(bookmark);
    showDashMenu(
      cardContext,
      title: plainText(thread.toPost().title),
      entries: [
        DashMenuEntry(
          title: isBookmarked ? 'Remove bookmark' : 'Bookmark',
          icon: isBookmarked
              ? CupertinoIcons.bookmark_fill
              : CupertinoIcons.bookmark,
          onPressed: () {
            keepFeedback();
            bookmarks.toggleBookmark(bookmark);
          },
        ),
        DashMenuEntry(
          title: 'Remove from history',
          icon: CupertinoIcons.trash,
          isDestructive: true,
          onPressed: () => history.removeThread(thread),
        ),
      ],
    );
  }

  void _push(Widget page) {
    Navigator.of(context).push(BackSwipePageRoute<void>(builder: (_) => page));
  }

  bool _isVisible(Board b, bool nsfw) => nsfw || !b.isNsfw;

  Widget _row(Board b, bool isDark, FavoriteProvider favorites) {
    final String code = b.board;
    return DashBoardRow(
      board: code,
      title: b.title,
      description: boardBlurb(plainText(b.metaDescription ?? '')),
      isFavorite: favorites.contains(code),
      nsfw: b.isNsfw,
      onTap: () => openBoard(context, code, name: b.title),
      onToggleFavorite: () {
        keepFeedback();
        favorites.toggle(code);
      },
      onMenu: (rowContext) => showDashMenu(
        rowContext,
        title: '/$code/ · ${b.title}',
        entries: [
          DashMenuEntry(
            title: favorites.contains(code)
                ? 'Remove from favorites'
                : 'Add to favorites',
            icon: favorites.contains(code)
                ? CupertinoIcons.heart_slash
                : CupertinoIcons.heart,
            onPressed: () {
              keepFeedback();
              favorites.toggle(code);
            },
          ),
          if (b.hasArchive)
            DashMenuEntry(
              title: 'Archive',
              icon: CupertinoIcons.archivebox,
              onPressed: () =>
                  _push(ArchivePage(board: code, boardName: b.title)),
            ),
        ],
      ),
    );
  }

  Widget _group(List<Widget> rows, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DashCard(
        // What swiping a row shows stays inside the card's corners.
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            children: [
              for (int i = 0; i < rows.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    indent: DashBoardRow.textInset,
                    color: DashColors.border(context),
                  ),
                rows[i],
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// [byLetter]'s boards in one card, each letter's under a band with the
  /// letter.
  Widget _byLetter(
    Map<String, List<Board>> byLetter,
    bool isDark,
    FavoriteProvider favorites,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DashCard(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final MapEntry<String, List<Board>> letter
                  in byLetter.entries) ...[
                Container(
                  color: context.accent.withValues(alpha: 0.08),
                  padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
                  child: Text(
                    letter.key,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: context.accent,
                    ),
                  ),
                ),
                for (int i = 0; i < letter.value.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: DashBoardRow.textInset,
                      color: DashColors.border(context),
                    ),
                  _row(letter.value[i], isDark, favorites),
                ],
              ],
            ],
          ),
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
    final SettingsProvider settings = Provider.of<SettingsProvider>(context);
    final bool nsfw = settings.showsNsfw;

    final HistoryProvider history = Provider.of<HistoryProvider>(context);
    final List<HistoryThread> continueThreads = _continueThreads(
      settings,
      history,
    );

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
        if (settings.allowNSFW.value && settings.nsfwEachSession.value)
          DashIconButton(
            label: settings.nsfwSessionOn
                ? 'Hide NSFW boards'
                : 'Show NSFW boards',
            icon: Icon(
              settings.nsfwSessionOn
                  ? CupertinoIcons.flame_fill
                  : CupertinoIcons.flame,
              color: settings.nsfwSessionOn ? DashColors.danger : null,
            ),
            onPressed: () => settings.setNsfwSession(!settings.nsfwSessionOn),
          ),
        // Continue reading has its own link to History.
        if (continueThreads.isEmpty)
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
      readable: true,
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
                  ..._continueReading(history, continueThreads),
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

    final bool othersOnly = _query.isEmpty && favoriteBoards.isNotEmpty;
    final List<Board> visibleBoards = listedBoards(
      boards,
      query: _query,
      isFavorite: favorites.contains,
    );
    // By letter, unless searching.
    final Map<String, List<Board>> byLetter = {};
    if (_query.isEmpty) {
      for (final Board b in visibleBoards) {
        byLetter.putIfAbsent(boardLetter(b.board), () => []).add(b);
      }
    }

    return [
      if (favoriteBoards.isNotEmpty) ...[
        const DashSectionHeader(title: 'Favorites'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: DashFeedCard(
            boardCount: favoriteBoards.length,
            onTap: () => _push(const FeedPage()),
          ),
        ),
        _group([
          for (final b in favoriteBoards) _row(b, isDark, favorites),
        ], isDark),
      ],
      DashSectionHeader(title: othersOnly ? 'Other boards' : 'All boards'),
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
      else if (byLetter.isEmpty)
        _group([
          for (final b in visibleBoards) _row(b, isDark, favorites),
        ], isDark)
      else
        _byLetter(byLetter, isDark, favorites),
    ];
  }
}

/// The boards in the list under Favorites, by their code: those matching
/// [query], favorites too; without one, all but the favorites, which have
/// their own list above.
@visibleForTesting
List<Board> listedBoards(
  List<Board> boards, {
  required String query,
  required bool Function(String board) isFavorite,
}) {
  final String q = query.toLowerCase();
  return [
    for (final Board b in boards)
      if (q.isEmpty
          ? !isFavorite(b.board)
          : b.board.toLowerCase().contains(q) ||
                b.title.toLowerCase().contains(q) ||
                (b.metaDescription ?? '').toLowerCase().contains(q))
        b,
  ]..sort((a, b) => a.board.compareTo(b.board));
}

/// The letter a board is listed under: its code's first, or # for a digit.
String boardLetter(String board) {
  final String first = board.isEmpty ? '#' : board[0].toUpperCase();
  return RegExp('[A-Z]').hasMatch(first) ? first : '#';
}
