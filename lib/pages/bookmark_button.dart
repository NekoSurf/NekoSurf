import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/Models/bookmark.dart';
import 'package:flutter_chan/blocs/bookmarks_model.dart';
import 'package:flutter_chan/widgets/dash_header.dart';
import 'package:provider/provider.dart';

class BookmarkButton extends StatefulWidget {
  const BookmarkButton({super.key, this.favorite});

  final Bookmark? favorite;

  @override
  State<BookmarkButton> createState() => _BookmarkButtonState();
}

class _BookmarkButtonState extends State<BookmarkButton> {
  @override
  Widget build(BuildContext context) {
    final bookmarks = Provider.of<BookmarksProvider>(context);
    final Bookmark? favorite = widget.favorite;
    final bool isFavorite =
        favorite != null && bookmarks.isBookmarked(favorite);

    return DashIconButton(
      onPressed: () {
        if (favorite == null) {
          return;
        }
        if (isFavorite) {
          bookmarks.removeBookmark(favorite);
        } else {
          bookmarks.addBookmark(favorite);
        }
      },
      icon: Icon(
        isFavorite ? CupertinoIcons.bookmark_fill : CupertinoIcons.bookmark,
      ),
    );
  }
}
