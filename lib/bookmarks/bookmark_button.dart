import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/bookmarks/bookmark.dart';
import 'package:flutter_chan/bookmarks/bookmarks_model.dart';
import 'package:flutter_chan/ui/dash_header.dart';
import 'package:provider/provider.dart';

class BookmarkButton extends StatelessWidget {
  const BookmarkButton({super.key, required this.bookmark});

  final Bookmark bookmark;

  @override
  Widget build(BuildContext context) {
    final bookmarks = Provider.of<BookmarksProvider>(context);
    final bool isBookmarked = bookmarks.isBookmarked(bookmark);

    return DashIconButton(
      label: isBookmarked ? 'Remove bookmark' : 'Bookmark',
      onPressed: () => bookmarks.toggleBookmark(bookmark),
      icon: Icon(
        isBookmarked ? CupertinoIcons.bookmark_fill : CupertinoIcons.bookmark,
      ),
    );
  }
}
