import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/board/thread_filters.dart';
import 'package:flutter_chan/bookmarks/bookmark.dart';
import 'package:flutter_chan/bookmarks/bookmarks_model.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/history/new_replies.dart';
import 'package:flutter_chan/media/image_cache.dart';
import 'package:flutter_chan/media/post_thumbnail.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/open.dart';
import 'package:flutter_chan/ui/pills.dart';
import 'package:provider/provider.dart';

const Color _chipTint = Color(0x40000000);

// Where the number chip and the bookmark button sit on the card.
const double _chipInset = 10;

class GridPost extends StatelessWidget {
  const GridPost({super.key, required this.post, this.showBoard = false});

  final Post post;
  final bool showBoard;

  @override
  Widget build(BuildContext context) {
    final bookmarks = Provider.of<BookmarksProvider>(context);
    final bool isDark = context.isDark;
    final Color cardColor = DashColors.card(isDark);
    final Color boardTint = boardColor(post.board);
    final String headline = post.title;
    final String excerpt = post.commentText;

    final Bookmark bookmark = Bookmark.fromPost(post);
    final bool isBookmarked = bookmarks.isBookmarked(bookmark);

    return GestureDetector(
      onTap: () => openThread(context, post),
      onLongPress: () => showThreadFilterMenu(context, post),
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: DashColors.border(isDark)),
          boxShadow: DashColors.cardShadow(isDark),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final Size card = constraints.biggest;
              return Stack(
                fit: StackFit.expand,
                children: [
                  PostThumbnail(post: post),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        // Darkest behind the title, above the counts.
                        stops: const [0, 0.4, 0.8],
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
                    left: 10,
                    // Clear of the bookmark button.
                    right: 50,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        // First, so that its place on the card is known.
                        _FrostedChip(
                          post: post,
                          card: card,
                          anchor: Alignment.topLeft,
                          inset: const Offset(-_chipInset, -_chipInset),
                          radius: 8,
                          tint: _chipTint,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'No.${post.no}',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        if (showBoard)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: boardTint.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '/${post.board}/',
                              style: const TextStyle(
                                color: CupertinoColors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        if (post.isSticky)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: CupertinoColors.systemOrange.withValues(
                                alpha: 0.65,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    CupertinoIcons.pin,
                                    color: CupertinoColors.white,
                                    size: 12,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Sticky',
                                    style: TextStyle(
                                      color: CupertinoColors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: GestureDetector(
                      onTap: () => bookmarks.toggleBookmark(bookmark),
                      child: _FrostedChip(
                        post: post,
                        card: card,
                        anchor: Alignment.topRight,
                        inset: const Offset(_chipInset, -_chipInset),
                        radius: 8,
                        tint: _chipTint,
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          child: Icon(
                            isBookmarked
                                ? CupertinoIcons.bookmark_fill
                                : CupertinoIcons.bookmark,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                headline,
                                style: const TextStyle(
                                  height: 1.1,
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (excerpt.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  excerpt,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 12,
                                    height: 1.3,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                        _FrostedChip(
                          post: post,
                          card: card,
                          anchor: Alignment.bottomCenter,
                          inset: Offset.zero,
                          radius: 0,
                          tint: cardColor.withValues(
                            alpha: isDark ? 0.7 : 0.85,
                          ),
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
                          child: NewRepliesCount(
                            thread: post.no,
                            replies: post.replies,
                            builder: (context, newReplies) => Row(
                              children: [
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: RepliesRow(
                                      replies: post.replies,
                                      imageReplies: post.images,
                                    ),
                                  ),
                                ),
                                if (newReplies > 0) ...[
                                  const SizedBox(width: 6),
                                  NewRepliesBadge(
                                    count: newReplies,
                                    short: true,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Looks frosted, but isn't blurred: a blur of what's behind it has to be redone
/// for each card in every frame, which makes scrolling a board stutter. So this
/// shows a tiny copy of the card's image, stretched to the card and cut to the
/// chip, which draws like any other image.
class _FrostedChip extends StatelessWidget {
  const _FrostedChip({
    required this.post,
    required this.card,
    required this.anchor,
    required this.inset,
    required this.radius,
    required this.tint,
    required this.child,
    this.padding,
  });

  final Post post;

  /// The size of the card the image fills.
  final Size card;

  /// The corner or edge of the card this chip is measured from, and how far
  /// that is from the same place on the chip.
  final Alignment anchor;
  final Offset inset;

  final double radius;
  final Color tint;
  final EdgeInsetsGeometry? padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final BorderRadius corners = BorderRadius.circular(radius);
    // A spoiler's picture stays hidden, even this blurry.
    final bool showsImage = post.tim != null && post.spoilerUpload == null;

    return Stack(
      children: [
        if (showsImage)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: corners,
              child: OverflowBox(
                alignment: anchor,
                minWidth: card.width,
                maxWidth: card.width,
                minHeight: card.height,
                maxHeight: card.height,
                child: Transform.translate(
                  offset: inset,
                  child: Image(
                    image: ResizeImage.resizeIfNeeded(
                      16,
                      null,
                      thumbnailImage(post.thumbnailUrl),
                    ),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        Container(
          padding: padding,
          decoration: BoxDecoration(color: tint, borderRadius: corners),
          child: child,
        ),
      ],
    );
  }
}
