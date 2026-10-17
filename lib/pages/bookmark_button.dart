import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/Models/bookmark.dart';
import 'package:flutter_chan/blocs/bookmarks_model.dart';
import 'package:flutter_chan/widgets/dash_header.dart';
import 'package:provider/provider.dart';

class BookmarkButton extends StatefulWidget {
  const BookmarkButton({Key? key, this.favorite}) : super(key: key);

  final Bookmark? favorite;

  @override
  State<BookmarkButton> createState() => _BookmarkButtonState();
}

class _BookmarkButtonState extends State<BookmarkButton> {
  bool isFavorite = false;
  late String favoriteString;

  @override
  void initState() {
    super.initState();

    favoriteString = json.encode(widget.favorite);
  }

  @override
  Widget build(BuildContext context) {
    final bookmarks = Provider.of<BookmarksProvider>(context);

    isFavorite = bookmarks.getBookmarks().contains(favoriteString);

    return DashIconButton(
      onPressed: () {
        if (isFavorite) {
          bookmarks.removeBookmarks(widget.favorite);
        } else {
          bookmarks.addBookmarks(widget.favorite);
        }
      },
      icon: Icon(
        isFavorite ? CupertinoIcons.bookmark_fill : CupertinoIcons.bookmark,
      ),
    );
  }
}
