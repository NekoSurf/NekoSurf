import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/archived.dart';
import 'package:flutter_chan/API/urls.dart' as urls;
import 'package:flutter_chan/Models/bookmark.dart';
import 'package:flutter_chan/Models/bookmark_status.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/bookmarks_model.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/blocs/watched_posts_model.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_widgets.dart';
import 'package:flutter_chan/pages/replies_row.dart';
import 'package:flutter_chan/pages/thread/thread_page.dart';
import 'package:flutter_chan/services/string.dart';
import 'package:flutter_chan/widgets/image_viewer.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

class BookmarksPost extends StatefulWidget {
  const BookmarksPost({super.key, required this.favorite});

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
    final bool isDark = theme.isDark;

    return FutureBuilder<BookmarkStatus>(
      future: _fetchBookmarkStatus,
      builder: (BuildContext context, snapshot) {
        final bool hasStatusData = snapshot.hasData && snapshot.data != null;
        final bool failedToLoad =
            snapshot.hasError ||
            (snapshot.connectionState == ConnectionState.done &&
                !hasStatusData);
        final ThreadStatus status =
            snapshot.connectionState == ConnectionState.waiting
            ? ThreadStatus.online
            : failedToLoad
            ? ThreadStatus.deleted
            : (snapshot.data?.status ?? ThreadStatus.online);
        final ThreadReplyCount? replyCount =
            snapshot.connectionState == ConnectionState.waiting || failedToLoad
            ? null
            : snapshot.data?.replies;
        final bool isDeleted = status == ThreadStatus.deleted;

        final int? replies = replyCount?.replies;
        final int? threadNo = widget.favorite.no;
        // Read positions change on every scroll in a thread; only rebuild
        // when this bookmark's own count changes.
        final Widget card = Selector<WatchedPostsProvider, int>(
          selector: (_, watched) => replies == null || threadNo == null
              ? 0
              : watched.newReplies(threadNo, replies) ?? 0,
          builder: (_, newReplies, _) => _BookmarkCard(
            favorite: widget.favorite,
            status: status,
            replyCount: replyCount,
            newReplies: newReplies,
            isDeleted: isDeleted,
            isDark: isDark,
          ),
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
                  right: Radius.circular(20),
                ),
                label: 'Delete',
                backgroundColor: const Color(0xFFE53935),
                foregroundColor: Colors.white,
                icon: CupertinoIcons.trash,
                onPressed: (context) => {
                  bookmarks.removeBookmark(widget.favorite),
                },
              ),
            ],
          ),
          child: GestureDetector(
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
    required this.newReplies,
    required this.isDeleted,
    required this.isDark,
  });

  final Bookmark favorite;
  final ThreadStatus? status;
  final ThreadReplyCount? replyCount;
  final int newReplies;
  final bool isDeleted;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final Color cardColor = DashColors.card(isDark);
    final Color primaryText = DashColors.text(isDark);
    final Color secondaryText = DashColors.muted(isDark);
    final Color boardTint = boardColor(favorite.board ?? '');

    final String headline = unescape(
      cleanTags(favorite.sub ?? favorite.com ?? ''),
    ).trim();
    final String excerpt = favorite.sub != null && favorite.com != null
        ? unescape(cleanTags(favorite.com ?? '')).trim()
        : '';

    final bool hasImage = favorite.imageUrl != null;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: DashColors.border(isDark)),
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: boardTint.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '/${favorite.board}/',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: boardTint,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'No.${favorite.no}',
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
                    RepliesRow(
                      replies: replyCount?.replies ?? '-',
                      imageReplies: replyCount?.images ?? '-',
                    ),
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
                child: ImageViewer(
                  url: urls.boardFile(
                    '${favorite.board}',
                    '${favorite.imageUrl}',
                  ),
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
