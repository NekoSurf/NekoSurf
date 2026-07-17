import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/Models/bookmark.dart';
import 'package:flutter_chan/blocs/bookmarks_model.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/pages/bookmarks/bookmarks_post.dart';
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
    final theme = Provider.of<ThemeChanger>(context);
    final bookmarks = Provider.of<BookmarksProvider>(context);
    final bookmarkStrings = bookmarks.getBookmarks().toList(growable: false);

    if (bookmarkStrings.isEmpty)
      return SliverToBoxAdapter(
        child: Center(
          child: Text(
            'Add bookmarks first!',
            style: TextStyle(
              fontSize: 26,
              color: theme.getTheme() == ThemeData.dark()
                  ? Colors.white
                  : Colors.black,
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
