import 'package:country_flags/country_flags.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/board/post_time.dart';
import 'package:flutter_chan/board/thread_filters.dart';
import 'package:flutter_chan/bookmarks/bookmark.dart';
import 'package:flutter_chan/bookmarks/bookmarks_model.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/history/new_replies.dart';
import 'package:flutter_chan/media/post_thumbnail.dart';
import 'package:flutter_chan/ui/back_swipe_route.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_widgets.dart';
import 'package:flutter_chan/ui/open.dart';
import 'package:flutter_chan/ui/pills.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

class ListPost extends StatelessWidget {
  const ListPost({super.key, required this.post, this.showBoard = false});

  final Post post;
  final bool showBoard;

  @override
  Widget build(BuildContext context) {
    final bookmarks = Provider.of<BookmarksProvider>(context);
    final bool isDark = context.isDark;
    final Color cardColor = DashColors.card(isDark);
    final Color boardTint = boardColor(post.board);
    final Color primaryText = DashColors.text(isDark);
    final Color secondaryText = DashColors.muted(isDark);
    final String excerpt = post.commentText;
    final String headline = post.title;
    final String posterName = post.posterName;

    final Bookmark bookmark = Bookmark.fromPost(post);
    final bool isBookmarked = bookmarks.isBookmarked(bookmark);

    return Slidable(
      endActionPane: isBookmarked
          ? swipeActions(
              label: 'Remove',
              icon: CupertinoIcons.trash_fill,
              onPressed: () => bookmarks.removeBookmark(bookmark),
            )
          : swipeActions(
              label: 'Add',
              icon: CupertinoIcons.bookmark_fill,
              color: context.accent,
              foregroundColor: Colors.black,
              onPressed: () => bookmarks.addBookmark(bookmark),
            ),
      child: SlidableBackSwipe(
        child: GestureDetector(
          onTap: () => openThread(context, post),
          onLongPress: () => showThreadFilterMenu(context, post),
          child: Container(
            margin: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: DashColors.border(isDark)),
              boxShadow: DashColors.cardShadow(isDark),
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: boardTint.withValues(
                                  alpha: 0.2,
                                ),
                                child: Text(
                                  posterName.characters.first.toUpperCase(),
                                  style: TextStyle(
                                    color: boardTint,
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
                                        Text(
                                          posterName,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: primaryText,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),

                                        const SizedBox(width: 6),

                                        if (showBoard)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              right: 6,
                                            ),
                                            child: BoardPill(board: post.board),
                                          ),

                                        if (post.isSticky)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: CupertinoColors
                                                  .systemOrange
                                                  .withValues(alpha: 0.16),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: const Text(
                                              'Sticky',
                                              style: TextStyle(
                                                color: CupertinoColors
                                                    .systemOrange,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),

                                        const Spacer(),

                                        if (post.country != null)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              left: 6,
                                            ),
                                            child: SizedBox(
                                              width: 16,
                                              height: 11,
                                              child:
                                                  CountryFlag.fromCountryCode(
                                                    post.country!,
                                                  ),
                                            ),
                                          ),
                                      ],
                                    ),

                                    Text(
                                      formatPostedAt(post),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: secondaryText,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          if (headline.isNotEmpty) ...[
                            const SizedBox(height: 6),

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
                            const SizedBox(height: 6),

                            Text(
                              excerpt,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                color: secondaryText,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),

                    if (post.tim != null) ...[
                      const SizedBox(width: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 100,
                          height: 100,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              PostThumbnail(post: post),
                              if (post.isVideo)
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

                const SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            RepliesRow(
                              replies: post.replies,
                              imageReplies: post.images,
                            ),
                            const SizedBox(width: 6),
                            PostNumberPill(no: post.no),
                            NewRepliesCount(
                              thread: post.no,
                              replies: post.replies,
                              builder: (context, newReplies) => newReplies > 0
                                  ? Padding(
                                      padding: const EdgeInsets.only(left: 6),
                                      child: NewRepliesBadge(count: newReplies),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 6),

                    GestureDetector(
                      onTap: () => bookmarks.toggleBookmark(bookmark),
                      child: Icon(
                        isBookmarked
                            ? CupertinoIcons.bookmark_fill
                            : CupertinoIcons.bookmark,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
