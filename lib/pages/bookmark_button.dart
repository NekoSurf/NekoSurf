import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/Models/bookmark.dart';
import 'package:flutter_chan/blocs/bookmarks_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/widgets/interactive/glass_button.dart';

class BookmarkButton extends ConsumerStatefulWidget {
  const BookmarkButton({Key? key, this.favorite}) : super(key: key);

  final Bookmark? favorite;

  @override
  ConsumerState<BookmarkButton> createState() => _BookmarkButtonState();
}

class _BookmarkButtonState extends ConsumerState<BookmarkButton> {
  @override
  Widget build(BuildContext context) {
    final bookmarks = ref.watch(bookmarksProvider);
    final favoriteString = json.encode(widget.favorite);
    final isFavorite = bookmarks.getBookmarks().contains(favoriteString);

    return GlassButton(
      onTap: () => isFavorite
          ? ref
              .read(bookmarksProvider.notifier)
              .removeBookmarks(widget.favorite)
          : ref.read(bookmarksProvider.notifier).addBookmarks(widget.favorite),
      icon: Icon(isFavorite ? Icons.bookmark : Icons.bookmark_border),
      width: 40,
      height: 40,
      iconSize: 20,
    );
  }
}
