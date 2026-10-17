import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/Models/bookmark.dart';
import 'package:flutter_chan/blocs/bookmarks_model.dart';
import 'package:flutter_chan/pages/bookmarks/bookmarks_post.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';
import 'package:provider/provider.dart';

class Bookmarks extends StatefulWidget {
  const Bookmarks({Key? key}) : super(key: key);

  @override
  State<Bookmarks> createState() => _BookmarksState();
}

class _BookmarksState extends State<Bookmarks> {
  final ScrollController scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    final bool isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final bookmarks = Provider.of<BookmarksProvider>(context);
    final bookmarkStrings = bookmarks.getBookmarks().toList(growable: false);

    if (bookmarkStrings.isEmpty)
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
    else
      return SliverList(
        delegate: SliverChildBuilderDelegate((BuildContext context, int index) {
          final String string = bookmarkStrings[index];

          return BookmarksPost(
            key: ValueKey<String>(string),
            favorite: Bookmark.fromJson(
              json.decode(string) as Map<String, dynamic>,
            ),
          );
        }, childCount: bookmarkStrings.length),
      );
  }
}
