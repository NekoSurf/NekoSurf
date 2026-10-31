import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/Models/bookmark.dart';
import 'package:flutter_chan/blocs/bookmarks_model.dart';
import 'package:flutter_chan/pages/bookmarks/bookmarks_post.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';
import 'package:provider/provider.dart';

class Bookmarks extends StatefulWidget {
  const Bookmarks({super.key});

  @override
  State<Bookmarks> createState() => _BookmarksState();
}

class _BookmarksState extends State<Bookmarks> {
  final ScrollController scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    final bool isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final bookmarks = Provider.of<BookmarksProvider>(context);
    final List<Bookmark> items = bookmarks.bookmarks;

    if (items.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 80, 32, 0),
          child: Column(
            children: [
              Icon(
                CupertinoIcons.bookmark,
                size: 44,
                color: DashColors.accent.withValues(alpha: 0.8),
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
            key: ValueKey<String>(bookmark.key),
            favorite: bookmark,
          );
        }, childCount: items.length),
      );
    }
  }
}
