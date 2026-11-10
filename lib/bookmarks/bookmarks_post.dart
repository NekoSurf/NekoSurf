import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/bookmarks/bookmark.dart';
import 'package:flutter_chan/bookmarks/bookmarks_model.dart';
import 'package:flutter_chan/chan/post_text.dart';
import 'package:flutter_chan/chan/thread_status.dart';
import 'package:flutter_chan/history/new_replies.dart';
import 'package:flutter_chan/media/post_thumbnail.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_widgets.dart';
import 'package:flutter_chan/ui/open.dart';
import 'package:flutter_chan/ui/pills.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

class BookmarksPost extends StatefulWidget {
  const BookmarksPost({super.key, required this.bookmark});

  final Bookmark bookmark;

  @override
  State<BookmarksPost> createState() => _BookmarksPostState();
}

class _BookmarksPostState extends State<BookmarksPost> {
  late Future<ThreadCheck?> _check;

  Future<ThreadCheck?> _loadCheck() =>
      checkThread(widget.bookmark.board, widget.bookmark.no, exact: true);

  @override
  void initState() {
    super.initState();
    _check = _loadCheck();
  }

  @override
  void didUpdateWidget(covariant BookmarksPost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookmark.key != widget.bookmark.key) {
      _check = _loadCheck();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookmarks = Provider.of<BookmarksProvider>(context);

    return FutureBuilder<ThreadCheck?>(
      future: _check,
      builder: (BuildContext context, snapshot) {
        // Until it's known, or if it can't be, it can still be opened.
        final ThreadStatus status =
            snapshot.data?.status ?? ThreadStatus.online;
        final int? replies = snapshot.data?.replies;
        final bool isDeleted = status == ThreadStatus.deleted;

        final Widget card = NewRepliesCount(
          thread: widget.bookmark.no,
          replies: replies,
          builder: (_, newReplies) => _BookmarkCard(
            bookmark: widget.bookmark,
            status: status,
            replies: replies,
            images: snapshot.data?.images,
            newReplies: newReplies,
          ),
        );

        if (snapshot.connectionState == ConnectionState.waiting) {
          return card;
        }

        return Slidable(
          endActionPane: swipeActions(
            label: 'Delete',
            icon: CupertinoIcons.trash,
            onPressed: () => bookmarks.removeBookmark(widget.bookmark),
          ),
          child: GestureDetector(
            onTap: () {
              if (!isDeleted) {
                openThread(context, widget.bookmark.toPost());
              }
            },
            child: card,
          ),
        );
      },
    );
  }
}

class _BookmarkCard extends StatelessWidget {
  const _BookmarkCard({
    required this.bookmark,
    required this.status,
    required this.replies,
    required this.images,
    required this.newReplies,
  });

  final Bookmark bookmark;
  final ThreadStatus status;
  final int? replies;
  final int? images;
  final int newReplies;

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;
    final Color cardColor = DashColors.card(context);
    final Color primaryText = DashColors.text(context);
    final Color secondaryText = DashColors.muted(context);

    final String headline = bookmark.toPost().title;
    final String excerpt = bookmark.sub != null && bookmark.com != null
        ? plainText(bookmark.com ?? '').trim()
        : '';

    final bool hasImage = bookmark.imageUrl != null;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: DashColors.border(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    BoardPill(board: bookmark.board),
                    const SizedBox(width: 6),
                    Text(
                      'No.${bookmark.no}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: secondaryText,
                      ),
                    ),

                    if (status == ThreadStatus.archived ||
                        status == ThreadStatus.deleted) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: CupertinoColors.systemRed.withValues(
                            alpha: isDark ? 0.25 : 0.12,
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          status == ThreadStatus.archived
                              ? 'Archived'
                              : 'Deleted',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: CupertinoColors.systemRed,
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
                const SizedBox(height: 10),
                Row(
                  children: [
                    RepliesRow(replies: replies, imageReplies: images),
                    if (newReplies > 0) ...[
                      const SizedBox(width: 8),
                      NewRepliesBadge(count: newReplies),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (hasImage) ...[
            const SizedBox(width: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 76,
                height: 76,
                child: PostThumbnail(post: bookmark.toPost()),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
