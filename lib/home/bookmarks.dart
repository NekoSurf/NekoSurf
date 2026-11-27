import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/board/thread_order.dart';
import 'package:flutter_chan/board/thread_views.dart';
import 'package:flutter_chan/bookmarks/bookmark.dart';
import 'package:flutter_chan/bookmarks/bookmarks_model.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/chan/thread_status.dart';
import 'package:flutter_chan/history/new_replies.dart';
import 'package:flutter_chan/history/watched_posts_model.dart';
import 'package:flutter_chan/home/app_shell.dart';
import 'package:flutter_chan/home/thread_cards.dart';
import 'package:flutter_chan/offline/offline_threads.dart';
import 'package:flutter_chan/offline/offline_threads_page.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/sync/cloud_sync.dart';
import 'package:flutter_chan/ui/dash_dialogs.dart';
import 'package:flutter_chan/ui/dash_menu.dart';
import 'package:flutter_chan/ui/dash_scaffold.dart';
import 'package:flutter_chan/ui/dash_widgets.dart';
import 'package:flutter_chan/ui/empty_state.dart';
import 'package:flutter_chan/ui/master_detail.dart';
import 'package:flutter_chan/ui/open.dart';
import 'package:provider/provider.dart';

/// The Bookmarks tab: the bookmarked threads as a board shows its threads.
class Bookmarks extends StatefulWidget {
  const Bookmarks({super.key});

  @override
  State<Bookmarks> createState() => _BookmarksState();
}

class _BookmarksState extends State<Bookmarks> {
  static const Duration _statusesKept = Duration(minutes: 2);

  /// What's been found of each bookmarked thread, by [Bookmark.key].
  final Map<String, ThreadCheck> _checks = {};
  final Set<String> _checking = {};

  DateTime? _shownAt;
  bool _isShown = false;

  /// Whether any thread is saved for offline, for the menu to open them.
  bool _hasOffline = OfflineThreads.instance.threads.isNotEmpty;

  void _offlineChanged() {
    final bool hasOffline = OfflineThreads.instance.threads.isNotEmpty;
    if (hasOffline != _hasOffline && mounted) {
      setState(() => _hasOffline = hasOffline);
    }
  }

  @override
  void initState() {
    super.initState();
    OfflineThreads.instance.addListener(_offlineChanged);
  }

  @override
  void dispose() {
    OfflineThreads.instance.removeListener(_offlineChanged);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool isShown = TickerMode.valuesOf(context).enabled;
    if (isShown && !_isShown) {
      final DateTime now = DateTime.now();
      final DateTime? shownAt = _shownAt;
      if (shownAt != null && now.difference(shownAt) > _statusesKept) {
        _check(
          Provider.of<BookmarksProvider>(context, listen: false).bookmarks,
          again: true,
        );
      }
      _shownAt = now;
    }
    _isShown = isShown;
  }

  /// Asks after the threads of [bookmarks] not asked after yet, or, [again],
  /// all of them; each card updates as its answer comes.
  Future<void> _check(
    List<Bookmark> bookmarks, {
    bool again = false,
    bool force = false,
  }) async {
    await Future.wait([
      for (final Bookmark b in bookmarks)
        if ((again || !_checks.containsKey(b.key)) && _checking.add(b.key))
          checkThread(b.board, b.no, exact: true, force: force).then((check) {
            _checking.remove(b.key);
            if (check != null && mounted) {
              setState(() => _checks[b.key] = check);
            }
          }),
    ]);
  }

  /// The thread as last loaded, or as it was when it was bookmarked.
  Post _post(Bookmark b) => _checks[b.key]?.op ?? b.toPost();

  ThreadStatus _status(Post post) =>
      _checks['${post.board}/${post.no}']?.status ?? ThreadStatus.online;

  Set<String> _deadKeys(List<Bookmark> items) => {
    for (final Bookmark b in items)
      if (_checks[b.key]?.status
          case ThreadStatus.archived || ThreadStatus.deleted)
        b.key,
  };

  Future<bool> _confirm(String title, String message, String action) async {
    final bool? confirmed = await showDashDialog<bool>(
      context: context,
      builder: (context) => DashDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          DashDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          DashDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  String get _everywhere =>
      CloudSync.instance.isOn ? ', on all your devices with iCloud sync' : '';

  Future<void> _removeDead(
    BookmarksProvider bookmarks,
    Set<String> dead,
  ) async {
    final int n = dead.length;
    if (await _confirm(
      'Remove $n dead ${n == 1 ? 'thread' : 'threads'}?',
      'The bookmarks of threads that are archived or deleted go$_everywhere.',
      'Remove',
    )) {
      await bookmarks.removeBookmarks(dead);
    }
  }

  /// Clears the bookmarks shown, [items]: not those of hidden NSFW boards.
  Future<void> _clear(BookmarksProvider bookmarks, List<Bookmark> items) async {
    final int n = items.length;
    if (await _confirm(
      'Clear all $n ${n == 1 ? 'bookmark' : 'bookmarks'}?',
      'Every bookmark goes$_everywhere. This can’t be undone.',
      'Clear',
    )) {
      await (n == bookmarks.bookmarks.length
          ? bookmarks.clearBookmarks()
          : bookmarks.removeBookmarks({for (final b in items) b.key}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookmarks = Provider.of<BookmarksProvider>(context);
    final SettingsProvider settings = Provider.of<SettingsProvider>(context);
    final List<Bookmark> items = [
      for (final Bookmark b in bookmarks.bookmarks)
        if (!settings.hidesBoard(b.board)) b,
    ];
    _check(items);
    final Set<String> dead = _deadKeys(items);
    final bool hasOffline = _hasOffline;
    final List<Post> posts = [for (final b in items) _post(b)];
    // Archived and deleted threads go last, under their own heading.
    final List<Post> live = [
      for (final b in items)
        if (!dead.contains(b.key)) _post(b),
    ];
    final List<Post> gone = [
      for (final b in items)
        if (dead.contains(b.key)) _post(b),
    ];
    // For the tab's badge and the line under the title. Read positions
    // change with every scroll in a thread; this only rebuilds when the
    // count does.
    final int withNewReplies = context.select<WatchedPostsProvider, int>(
      (watched) => posts
          .where(
            (Post post) =>
                (watched.newReplies(post.no, post.replies ?? 0) ?? 0) > 0,
          )
          .length,
    );
    _report(context, withNewReplies);

    return MasterDetail(
      master: DashScaffold(
        title: 'Bookmarks',
        subtitle: items.isEmpty
            ? null
            : '${items.length} ${items.length == 1 ? 'bookmark' : 'bookmarks'}'
                  '${withNewReplies > 0 ? ' · $withNewReplies with new replies' : ''}',
        reserveTabBarSpace: true,
        readable: settings.boardViewMode.value == ViewMode.list,
        onRefresh: items.isEmpty
            ? null
            : () => _check(items, again: true, force: true),
        actions: [
          if (items.isNotEmpty) const ViewModeButton(),
          DashMenuButton(
            icon: CupertinoIcons.sort_down,
            label: 'Sort',
            menuChildren: [
              DashMenuEntry(
                title: 'Newest',
                icon: CupertinoIcons.clock,
                isSelected: bookmarks.newestFirst,
                onPressed: () => bookmarks.setNewestFirst(true),
              ),
              DashMenuEntry(
                title: 'Oldest',
                icon: CupertinoIcons.clock_fill,
                isSelected: !bookmarks.newestFirst,
                onPressed: () => bookmarks.setNewestFirst(false),
              ),
            ],
          ),
          // Only what there's something to do with.
          if (items.isNotEmpty || hasOffline)
            DashMenuButton(
              menuChildren: [
                if (hasOffline)
                  DashMenuEntry(
                    title: 'Saved for offline',
                    icon: CupertinoIcons.arrow_down_circle,
                    onPressed: () => openOfflineThreads(context),
                  ),
                if (dead.isNotEmpty)
                  DashMenuEntry(
                    title: 'Remove dead threads',
                    icon: CupertinoIcons.archivebox,
                    onPressed: () => _removeDead(bookmarks, dead),
                  ),
                if (items.isNotEmpty)
                  DashMenuEntry(
                    title: 'Clear bookmarks',
                    icon: CupertinoIcons.trash,
                    isDestructive: true,
                    onPressed: () => _clear(bookmarks, items),
                  ),
              ],
            ),
        ],
        slivers: [
          if (items.isEmpty)
            const SliverToBoxAdapter(child: _EmptyState())
          else ...[
            SliverToBoxAdapter(child: _NewReplies(posts: live)),
            if (live.isNotEmpty) _Threads(posts: live, statusOf: _status),
            if (gone.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: DashSectionHeader(
                  title: 'No longer live',
                  trailing: DashSectionLink(
                    'Remove all',
                    onTap: () => _removeDead(bookmarks, dead),
                  ),
                ),
              ),
              _Threads(posts: gone, statusOf: _status),
            ],
          ],
        ],
      ),
    );
  }
}

/// Tells the tab bar's badge how many threads have new replies, once this
/// frame is built, since it isn't part of this page.
void _report(BuildContext context, int count) {
  final ValueNotifier<int> badge = Provider.of<BookmarksProvider>(
    context,
    listen: false,
  ).withNewReplies;
  if (badge.value != count) {
    WidgetsBinding.instance.addPostFrameCallback((_) => badge.value = count);
  }
}

/// The threads, in the order chosen.
class _Threads extends StatelessWidget {
  const _Threads({required this.posts, required this.statusOf});

  final List<Post> posts;
  final ThreadStatus Function(Post post) statusOf;

  @override
  Widget build(BuildContext context) {
    final bool grid =
        Provider.of<SettingsProvider>(context).boardViewMode.value ==
        ViewMode.grid;
    return ThreadsView(
      threads: posts,
      grid: grid,
      showBoard: true,
      statusOf: statusOf,
      // In line with the card above, and the other tabs.
      sideInset: 16,
    );
  }
}

/// The bookmarked threads with new replies, as big picture cards above the
/// rest, under "All bookmarks"; nothing while none has any.
class _NewReplies extends StatelessWidget {
  const _NewReplies({required this.posts});

  final List<Post> posts;

  @override
  Widget build(BuildContext context) {
    // Read positions change with every scroll in a thread; this only
    // rebuilds when a count does.
    final String counts = context.select<WatchedPostsProvider, String>(
      (watched) => [
        for (final Post post in posts)
          watched.newReplies(post.no, post.replies ?? 0) ?? 0,
      ].join(','),
    );
    final List<int> newReplies = [
      for (final String n in counts.split(',')) int.tryParse(n) ?? 0,
    ];
    final List<ThreadCard> cards = [
      for (int i = 0; i < posts.length && i < newReplies.length; i++)
        if (newReplies[i] > 0)
          ThreadCard(
            post: posts[i],
            onTap: () => openThread(context, posts[i]),
            badge: NewRepliesBadge(count: newReplies[i], short: true),
          ),
    ];
    if (cards.isEmpty) {
      return const SizedBox(height: 4);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DashSectionHeader(title: 'New replies', top: 8),
        ThreadCardRow(cards: cards, width: 240, imageHeight: 150),
        const DashSectionHeader(title: 'All bookmarks'),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final VoidCallback? showBoards = ShowBoardsTab.maybeOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: DashEmptyState(
        icon: CupertinoIcons.bookmark,
        title: 'No bookmarks yet',
        message:
            'Tap the bookmark in a thread to keep it here, with its new '
            'replies.',
        actionLabel: 'Browse boards',
        onAction: showBoards,
      ),
    );
  }
}
