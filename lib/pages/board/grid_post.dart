import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/Models/bookmark.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/bookmarks_model.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/pages/replies_row.dart';
import 'package:flutter_chan/pages/thread/thread_page.dart';
import 'package:flutter_chan/services/string.dart';
import 'package:flutter_chan/widgets/image_viewer.dart';
import 'package:provider/provider.dart';

class GridPost extends StatefulWidget {
  const GridPost({Key? key, required this.board, required this.post})
    : super(key: key);

  final String board;
  final Post post;

  @override
  State<GridPost> createState() => _GridPostState();
}

class _GridPostState extends State<GridPost> {
  late Bookmark favorite;
  bool isFavorite = false;
  late String favoriteString;

  @override
  void initState() {
    super.initState();

    favorite = Bookmark(
      no: widget.post.no,
      sub: widget.post.sub,
      com: widget.post.com,
      imageUrl: '${widget.post.tim}s.jpg',
      board: widget.board,
    );

    favoriteString = json.encode(favorite);
  }

  @override
  Widget build(BuildContext context) {
    final bookmarks = Provider.of<BookmarksProvider>(context);
    final theme = Provider.of<ThemeChanger>(context);
    final bool isDark = theme.getTheme() == ThemeData.dark();
    final Color cardColor = isDark
        ? const Color(0xFF13161B)
        : const Color(0xFFFFFFFF);
    final String headline = unescape(
      cleanTags(widget.post.sub ?? widget.post.com ?? ''),
    ).trim();
    final String excerpt = unescape(cleanTags(widget.post.com ?? '')).trim();

    isFavorite = bookmarks.getBookmarks().contains(favoriteString);

    return InkWell(
      onLongPress: () => {
        showCupertinoModalPopup(
          context: context,
          builder: (BuildContext context) => CupertinoActionSheet(
            actions: [
              if (isFavorite)
                CupertinoActionSheetAction(
                  child: const Text('Remove bookmark'),
                  onPressed: () {
                    bookmarks.removeBookmarks(favorite);

                    Navigator.pop(context);
                  },
                )
              else
                CupertinoActionSheetAction(
                  child: const Text('Set bookmark'),
                  onPressed: () {
                    bookmarks.addBookmarks(favorite);

                    Navigator.pop(context);
                  },
                ),
            ],
            cancelButton: CupertinoActionSheetAction(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
          ),
        ),
      },
      onTap: () => {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ThreadPage(
              threadName: widget.post.sub ?? widget.post.com ?? '',
              thread: widget.post.no ?? 0,
              board: widget.board,
              post: widget.post,
            ),
          ),
        ),
      },
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark
                ? CupertinoColors.systemGrey.withValues(alpha: 0.25)
                : const Color(0x14000000),
          ),
          boxShadow: isDark
              ? []
              : const [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ImageViewer(
                      url:
                          'https://i.4cdn.org/${widget.board}/${widget.post.tim}s.jpg',
                      fit: BoxFit.cover,
                      height: MediaQuery.of(context).size.height,
                      width: MediaQuery.of(context).size.width,
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.08),
                            Colors.black.withValues(alpha: 0.02),
                            Colors.black.withValues(alpha: 0.58),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: GestureDetector(
                        onTap: () => {
                          if (isFavorite)
                            bookmarks.removeBookmarks(favorite)
                          else
                            bookmarks.addBookmarks(favorite),
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Icon(
                            isFavorite
                                ? CupertinoIcons.bookmark_fill
                                : CupertinoIcons.bookmark,
                            color: isFavorite
                                ? CupertinoColors.activeBlue
                                : Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            headline,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (excerpt.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              excerpt,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 12,
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    RepliesRow(
                      replies: widget.post.replies,
                      imageReplies: widget.post.images,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? CupertinoColors.systemGrey.withValues(alpha: 0.16)
                            : CupertinoColors.systemGrey6,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'No.${widget.post.no}',
                        style: TextStyle(
                          color: isDark
                              ? CupertinoColors.systemGrey
                              : const Color(0xFF5B6470),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
