import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/Models/bookmark.dart';
import 'package:flutter_chan/blocs/bookmarks_model.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/pages/bookmarks/bookmarks_post.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class Bookmarks extends ConsumerWidget {
  const Bookmarks({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final bookmarks = ref.watch(bookmarksProvider);
    final bookmarkStrings = bookmarks.getBookmarks().toList(growable: false);

    if (bookmarkStrings.isEmpty)
      return SliverToBoxAdapter(
        child: Center(
          child: Text(
            'Add bookmarks first!',
            style: TextStyle(
              fontSize: 26,
              color: theme == ThemeData.dark() ? Colors.white : Colors.black,
            ),
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
