import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/board/thread_order.dart';
import 'package:flutter_chan/board/thread_views.dart';
import 'package:flutter_chan/bookmarks/bookmark.dart';
import 'package:flutter_chan/bookmarks/bookmarks_model.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/chan/thread_status.dart';
import 'package:flutter_chan/history/watched_posts_model.dart';
import 'package:flutter_chan/home/bookmarks_summary.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/sync/cloud_sync.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_dialogs.dart';
import 'package:flutter_chan/ui/dash_menu.dart';
import 'package:flutter_chan/ui/dash_scaffold.dart';
import 'package:flutter_chan/ui/dash_widgets.dart';
import 'package:provider/provider.dart';

/// The Bookmarks tab: the bookmarked threads as a board shows its threads,
/// those with new replies first.
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

  Future<void> _clear(BookmarksProvider bookmarks) async {
    final int n = bookmarks.bookmarks.length;
    if (await _confirm(
      'Clear all $n ${n == 1 ? 'bookmark' : 'bookmarks'}?',
      'Every bookmark goes$_everywhere. This can’t be undone.',
      'Clear',
    )) {
      await bookmarks.clearBookmarks();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookmarks = Provider.of<BookmarksProvider>(context);
    final List<Bookmark> items = bookmarks.bookmarks;
    _check(items);
    final Set<String> dead = _deadKeys(items);

    return DashScaffold(
      title: 'Bookmarks',
      reserveTabBarSpace: true,
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
              onPressed: () => bookmarks.setNewestFirst(true),
            ),
            DashMenuEntry(
              title: 'Oldest',
              icon: CupertinoIcons.clock_fill,
              onPressed: () => bookmarks.setNewestFirst(false),
            ),
          ],
        ),
        // Only what there's something to do with.
        if (items.isNotEmpty)
          DashMenuButton(
            menuChildren: [
              if (dead.isNotEmpty)
                DashMenuEntry(
                  title: 'Remove dead threads',
                  icon: CupertinoIcons.archivebox,
                  onPressed: () => _removeDead(bookmarks, dead),
                ),
              DashMenuEntry(
                title: 'Clear bookmarks',
                icon: CupertinoIcons.trash,
                isDestructive: true,
                onPressed: () => _clear(bookmarks),
              ),
            ],
          ),
      ],
      slivers: [
        if (items.isEmpty)
          const SliverToBoxAdapter(child: _EmptyState())
        else ...[
          SliverToBoxAdapter(
            child: BookmarksSummary(
              bookmarks: items,
              newestFirst: bookmarks.newestFirst,
            ),
          ),
          _Threads(posts: [for (final b in items) _post(b)], statusOf: _status),
        ],
      ],
    );
  }
}

/// The threads, in two groups when some have new replies and some don't.
class _Threads extends StatelessWidget {
  const _Threads({required this.posts, required this.statusOf});

  final List<Post> posts;
  final ThreadStatus Function(Post post) statusOf;

  @override
  Widget build(BuildContext context) {
    final bool grid =
        Provider.of<SettingsProvider>(context).boardViewMode.value ==
        ViewMode.grid;
    // Read positions change with every scroll in a thread; this only
    // rebuilds when which threads have new replies does.
    // A string, which compares by what it says.
    final String which = context.select<WatchedPostsProvider, String>(
      (watched) => [
        for (int i = 0; i < posts.length; i++)
          if ((watched.newReplies(posts[i].no, posts[i].replies ?? 0) ?? 0) > 0)
            i,
      ].join(','),
    );
    final List<int> updated = [
      if (which.isNotEmpty)
        for (final String i in which.split(',')) int.parse(i),
    ];

    Widget threads(List<Post> posts) => ThreadsView(
      threads: posts,
      grid: grid,
      showBoard: true,
      statusOf: statusOf,
    );

    if (updated.isEmpty || updated.length == posts.length) {
      return threads(posts);
    }
    final Set<int> isUpdated = updated.toSet();
    return SliverMainAxisGroup(
      slivers: [
        const SliverToBoxAdapter(
          child: DashSectionHeader(title: 'New replies'),
        ),
        threads([for (final int i in updated) posts[i]]),
        const SliverToBoxAdapter(
          child: DashSectionHeader(title: 'Other bookmarks'),
        ),
        threads([
          for (int i = 0; i < posts.length; i++)
            if (!isUpdated.contains(i)) posts[i],
        ]),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 80, 32, 0),
      child: Column(
        children: [
          Icon(
            CupertinoIcons.bookmark,
            size: 44,
            color: context.accent.withValues(alpha: 0.8),
          ),
          const SizedBox(height: 16),
          Text(
            'No bookmarks yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: DashColors.text(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap the bookmark icon on a thread to keep it here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: DashColors.muted(context)),
          ),
        ],
      ),
    );
  }
}
