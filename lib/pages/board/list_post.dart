import 'dart:convert';

import 'package:country_flags/country_flags.dart';
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
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class ListPost extends StatefulWidget {
  const ListPost({Key? key, required this.board, required this.post})
    : super(key: key);

  final String board;
  final Post post;

  @override
  State<ListPost> createState() => _ListPostState();
}

class _ListPostState extends State<ListPost> {
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
    final theme = Provider.of<ThemeChanger>(context);
    final bookmarks = Provider.of<BookmarksProvider>(context);
    final bool isDark = theme.getTheme() == ThemeData.dark();
    final Color cardColor = isDark
        ? const Color(0xFF13161B)
        : const Color(0xFFFFFFFF);
    final Color primaryText = isDark ? Colors.white : const Color(0xFF121417);
    final Color secondaryText = isDark
        ? CupertinoColors.systemGrey
        : const Color(0xFF5B6470);
    final String excerpt = unescape(cleanTags(widget.post.com ?? '')).trim();
    final String headline = unescape(
      cleanTags(widget.post.sub ?? widget.post.com ?? ''),
    ).trim();
    final String posterName = (widget.post.name ?? 'Anonymous').trim();

    isFavorite = bookmarks.getBookmarks().contains(favoriteString);

    return Slidable(
      endActionPane: isFavorite
          ? ActionPane(
              extentRatio: 0.3,
              motion: const BehindMotion(),
              children: [
                SlidableAction(
                  label: 'Remove',
                  backgroundColor: Colors.red,
                  icon: Icons.delete,
                  onPressed: (context) => {bookmarks.removeBookmarks(favorite)},
                ),
              ],
            )
          : ActionPane(
              extentRatio: 0.3,
              motion: const BehindMotion(),
              children: [
                SlidableAction(
                  label: 'Add',
                  backgroundColor: Colors.green,
                  icon: Icons.add,
                  onPressed: (context) => {bookmarks.addBookmarks(favorite)},
                ),
              ],
            ),
      child: InkWell(
        onTap: () => {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ThreadPage(
                threadName: widget.post.sub ?? widget.post.com ?? '',
                thread: widget.post.no ?? 0,
                post: widget.post,
                board: widget.board,
              ),
            ),
          ),
        },
        child: Container(
          margin: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark
                  ? CupertinoColors.systemGrey.withValues(alpha: 0.25)
                  : const Color(0x14000000),
              width: 1,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: CupertinoColors.activeBlue.withValues(
                      alpha: 0.2,
                    ),
                    child: Text(
                      posterName.characters.first.toUpperCase(),
                      style: const TextStyle(
                        color: CupertinoColors.activeBlue,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                posterName,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: primaryText,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (widget.post.country != null &&
                                CountryFlag.fromCountryCode(
                                      widget.post.country!,
                                    ) !=
                                    null)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: SizedBox(
                                  width: 16,
                                  height: 11,
                                  child: CountryFlag.fromCountryCode(
                                    widget.post.country!,
                                  ),
                                ),
                              ),
                            if (widget.post.sticky == 1)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: CupertinoColors.systemOrange
                                      .withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  'Sticky',
                                  style: TextStyle(
                                    color: CupertinoColors.systemOrange,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? CupertinoColors.systemGrey.withValues(
                                        alpha: 0.18,
                                      )
                                    : const Color(0x11000000),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'No.${widget.post.no}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: secondaryText,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                DateFormat('kk:mm - dd.MM.y').format(
                                  DateTime.fromMillisecondsSinceEpoch(
                                    widget.post.time! * 1000,
                                  ),
                                ),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: secondaryText,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (widget.post.tim != null) ...[
                    const SizedBox(width: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 72,
                        height: 72,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ImageViewer(
                              url:
                                  'https://i.4cdn.org/${widget.board}/${widget.post.tim}s.jpg',
                              fit: BoxFit.cover,
                            ),
                            if (widget.post.ext == '.webm' ||
                                widget.post.ext == '.mp4')
                              const Center(
                                child: Icon(
                                  CupertinoIcons.play_circle_fill,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (headline.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  headline,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: primaryText,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (excerpt.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  excerpt,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: secondaryText,
                  ),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  RepliesRow(
                    replies: widget.post.replies,
                    imageReplies: widget.post.images,
                  ),
                  const Spacer(),
                  Icon(
                    isFavorite
                        ? CupertinoIcons.bookmark_fill
                        : CupertinoIcons.bookmark,
                    size: 18,
                    color: isFavorite
                        ? CupertinoColors.activeBlue
                        : secondaryText,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
