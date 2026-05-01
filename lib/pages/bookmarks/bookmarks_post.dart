import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/archived.dart';
import 'package:flutter_chan/Models/bookmark.dart';
import 'package:flutter_chan/Models/bookmark_status.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/bookmarks_model.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:flutter_chan/pages/replies_row.dart';
import 'package:flutter_chan/pages/thread/thread_page.dart';
import 'package:flutter_chan/services/string.dart';
import 'package:flutter_chan/widgets/image_viewer.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

class BookmarksPost extends StatefulWidget {
  const BookmarksPost({Key? key, required this.favorite}) : super(key: key);

  final Bookmark favorite;

  @override
  State<BookmarksPost> createState() => _BookmarksPostState();
}

class _BookmarksPostState extends State<BookmarksPost> {
  late Future<BookmarkStatus> _fetchBookmarkStatus;

  Future<BookmarkStatus> _loadBookmarkStatus() {
    return fetchBookmarkStatus(
      widget.favorite.board,
      widget.favorite.no.toString(),
    );
  }

  @override
  void initState() {
    super.initState();
    _fetchBookmarkStatus = _loadBookmarkStatus();
  }

  @override
  void didUpdateWidget(covariant BookmarksPost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldBoard = oldWidget.favorite.board;
    final oldNo = oldWidget.favorite.no;
    final newBoard = widget.favorite.board;
    final newNo = widget.favorite.no;

    if (oldBoard != newBoard || oldNo != newNo) {
      _fetchBookmarkStatus = _loadBookmarkStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeChanger>(context);
    final bookmarks = Provider.of<BookmarksProvider>(context);
    final bool isDark = theme.getTheme() == ThemeData.dark();

    return FutureBuilder<BookmarkStatus>(
      future: _fetchBookmarkStatus,
      builder: (BuildContext context, snapshot) {
        final ThreadStatus status =
            snapshot.connectionState == ConnectionState.waiting
            ? ThreadStatus.online
            : (snapshot.data!.status ?? ThreadStatus.online);
        final ThreadReplyCount? replyCount =
            snapshot.connectionState == ConnectionState.waiting
            ? null
            : snapshot.data!.replies;
        final bool isDeleted = status == ThreadStatus.deleted;

        final Widget card = _BookmarkCard(
          favorite: widget.favorite,
          status: status,
          replyCount: replyCount,
          isDeleted: isDeleted,
          isDark: isDark,
        );

        if (snapshot.connectionState == ConnectionState.waiting) {
          return card;
        }

        return Slidable(
          endActionPane: ActionPane(
            extentRatio: 0.28,
            motion: const BehindMotion(),
            children: [
              SlidableAction(
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(14),
                ),
                label: 'Delete',
                backgroundColor: const Color(0xFFE53935),
                foregroundColor: Colors.white,
                icon: CupertinoIcons.trash,
                onPressed: (context) => {
                  bookmarks.removeBookmarks(widget.favorite),
                },
              ),
            ],
          ),
          child: InkWell(
            onTap: () {
              if (!isDeleted) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => ThreadPage(
                      post: Post(
                        no: widget.favorite.no,
                        sub: widget.favorite.sub,
                        com: widget.favorite.com,
                        tim: widget.favorite.imageUrl != null
                            ? int.tryParse(
                                widget.favorite.imageUrl!.substring(
                                  0,
                                  widget.favorite.imageUrl!.length - 5,
                                ),
                              )
                            : null,
                        board: widget.favorite.board,
                      ),
                      threadName:
                          widget.favorite.sub ??
                          widget.favorite.com ??
                          'No.${widget.favorite.no}',
                      thread: widget.favorite.no ?? 0,
                      board: widget.favorite.board ?? '',
                      fromFavorites: true,
                    ),
                  ),
                );
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
    required this.favorite,
    required this.status,
    required this.replyCount,
    required this.isDeleted,
    required this.isDark,
  });

  final Bookmark favorite;
  final ThreadStatus? status;
  final ThreadReplyCount? replyCount;
  final bool isDeleted;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final Color cardColor = isDark
        ? const Color(0xFF13161B)
        : const Color(0xFFFFFFFF);
    final Color primaryText = isDark ? Colors.white : const Color(0xFF121417);
    final Color secondaryText = isDark
        ? CupertinoColors.systemGrey
        : const Color(0xFF5B6470);

    final String headline = unescape(
      cleanTags(favorite.sub ?? favorite.com ?? ''),
    ).trim();
    final String excerpt = favorite.sub != null && favorite.com != null
        ? unescape(cleanTags(favorite.com ?? '')).trim()
        : '';

    final bool hasImage = favorite.imageUrl != null;

    return Container(
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? CupertinoColors.systemGrey.withValues(alpha: 0.18)
                        : const Color(0x11000000),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'No.${favorite.no}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: secondaryText,
                    ),
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
                      status == ThreadStatus.archived ? 'Archived' : 'Deleted',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: CupertinoColors.systemRed,
                      ),
                    ),
                  ),
                ],
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
                RepliesRow(
                  replies: replyCount?.replies ?? '-',
                  imageReplies: replyCount?.images ?? '-',
                ),
              ],
            ),
          ),
          if (hasImage) ...[
            const SizedBox(width: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 72,
                height: 72,
                child: ImageViewer(
                  url:
                      'https://i.4cdn.org/${favorite.board}/${favorite.imageUrl}',
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
