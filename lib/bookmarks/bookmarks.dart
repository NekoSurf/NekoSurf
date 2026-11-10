import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/bookmarks/bookmark.dart';
import 'package:flutter_chan/bookmarks/bookmarks_model.dart';
import 'package:flutter_chan/bookmarks/bookmarks_post.dart';
import 'package:flutter_chan/bookmarks/bookmarks_summary.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_menu.dart';
import 'package:flutter_chan/ui/dash_scaffold.dart';
import 'package:provider/provider.dart';

class Bookmarks extends StatefulWidget {
  const Bookmarks({super.key});

  @override
  State<Bookmarks> createState() => _BookmarksState();
}

class _BookmarksState extends State<Bookmarks> {
  static const Duration _statusesKept = Duration(minutes: 2);

  // A new one has each bookmark check its thread's status again.
  int _statusGeneration = 0;
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
        _statusGeneration++;
      }
      _shownAt = now;
    }
    _isShown = isShown;
  }

  @override
  Widget build(BuildContext context) {
    final bookmarks = Provider.of<BookmarksProvider>(context);
    final List<Bookmark> items = bookmarks.bookmarks;

    return DashScaffold(
      title: 'Bookmarks',
      reserveTabBarSpace: true,
      actions: [
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
        DashMenuButton(
          menuChildren: [
            DashMenuEntry(
              title: 'Clear bookmarks',
              icon: CupertinoIcons.trash,
              isDestructive: true,
              onPressed: bookmarks.clearBookmarks,
            ),
          ],
        ),
      ],
      slivers: [
        if (items.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: BookmarksSummary(
              bookmarks: items,
              newestFirst: bookmarks.newestFirst,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
        ],
        _list(items),
      ],
    );
  }

  Widget _list(List<Bookmark> items) {
    final bool isDark = context.isDark;

    if (items.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
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
                  color: DashColors.text(isDark),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Tap the bookmark icon on a thread to keep it here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: DashColors.muted(isDark)),
              ),
            ],
          ),
        ),
      );
    } else {
      return SliverList(
        delegate: SliverChildBuilderDelegate((BuildContext context, int index) {
          final Bookmark bookmark = items[index];

          return BookmarksPost(
            key: ValueKey<String>('$_statusGeneration/${bookmark.key}'),
            bookmark: bookmark,
          );
        }, childCount: items.length),
      );
    }
  }
}
