import 'package:flutter/material.dart';
import 'package:flutter_chan/bookmarks/bookmark.dart';
import 'package:flutter_chan/media/post_thumbnail.dart';
import 'package:flutter_chan/ui/colors.dart';

/// The card at the top of the Bookmarks tab, like Saved's: how many threads
/// are bookmarked, from how many boards, in which order, and the newest
/// ones' thumbnails fanned out.
class BookmarksSummary extends StatelessWidget {
  const BookmarksSummary({
    super.key,
    required this.bookmarks,
    required this.newestFirst,
  });

  /// In the order shown.
  final List<Bookmark> bookmarks;
  final bool newestFirst;

  String get _boards {
    final Set<String> boards = {for (final Bookmark b in bookmarks) b.board};
    return boards.length == 1
        ? 'on /${boards.single}/'
        : 'from ${boards.length} boards';
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;
    const Color color = DashColors.feed;
    const angles = [-0.2, 0.05, 0.22];
    final int total = bookmarks.length;
    // The newest three with a thumbnail, the newest on top.
    final List<Bookmark> previews =
        (newestFirst ? bookmarks : bookmarks.reversed)
            .where((b) => b.imageUrl != null)
            .take(3)
            .toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(20, 18, 8, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: isDark ? 0.22 : 0.35),
            context.accent2.withValues(alpha: isDark ? 0.18 : 0.28),
          ],
        ),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$total',
                  style: TextStyle(
                    fontSize: 44,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.5,
                    color: DashColors.text(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  total == 1 ? 'bookmarked thread' : 'bookmarked threads',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DashColors.text(context).withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '$_boards · ${newestFirst ? 'newest' : 'oldest'} first',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: DashColors.text(context).withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
          if (previews.isNotEmpty)
            SizedBox(
              width: 112,
              height: 96,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  for (int i = previews.length - 1; i >= 0; i--)
                    Transform.translate(
                      offset: Offset((i - 1) * 14.0, 0),
                      child: Transform.rotate(
                        angle: angles[i],
                        child: Container(
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: PostThumbnail(post: previews[i].toPost()),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
