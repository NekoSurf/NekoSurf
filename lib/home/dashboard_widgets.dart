import 'package:flutter/cupertino.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chan/ui/back_swipe_route.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_widgets.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

class DashFeedCard extends StatelessWidget {
  const DashFeedCard({
    super.key,
    required this.boardCount,
    required this.onTap,
  });

  final int boardCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const Color pink = DashColors.feed;

    return DashCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: pink.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              CupertinoIcons.rectangle_stack_fill,
              color: pink,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your feed',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: DashColors.text(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Latest threads from $boardCount favorite ${boardCount == 1 ? 'board' : 'boards'}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: DashColors.muted(context),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            CupertinoIcons.chevron_right,
            size: 15,
            color: DashColors.muted(context),
          ),
        ],
      ),
    );
  }
}

/// A board on one line: its code in its colour, its name, and what it's
/// about, cut short where there's no more room. Swiped, it's added to or
/// taken out of the favorites.
class DashBoardRow extends StatelessWidget {
  const DashBoardRow({
    super.key,
    required this.board,
    required this.title,
    required this.description,
    required this.isFavorite,
    required this.nsfw,
    required this.onTap,
    required this.onToggleFavorite,
    this.onMenu,
  });

  final String board;
  final String title;
  final String description;
  final bool isFavorite;
  final bool nsfw;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  /// Opens the row's menu, when it's held (or right-clicked), anchored to
  /// the row's [context].
  final void Function(BuildContext context)? onMenu;

  /// How far the name starts from the row's edge, for the dividers between.
  static const double textInset = 16 + _codeWidth + 8;
  static const double _codeWidth = 46;

  @override
  Widget build(BuildContext context) {
    final Color color = nsfw ? DashColors.danger : boardColor(board);
    final String favoriteLabel = isFavorite
        ? 'Remove from favorites'
        : 'Add to favorites';

    final void Function(BuildContext context)? onMenu = this.onMenu;
    final Widget row = GestureDetector(
      onTap: onTap,
      onLongPress: onMenu == null
          ? null
          : () {
              HapticFeedback.mediumImpact();
              onMenu(context);
            },
      // A right click, with a trackpad or mouse, does what holding does.
      onSecondaryTap: onMenu == null ? null : () => onMenu(context),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: _codeWidth,
              // Stays on one line, however long the code.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '/$board/',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: title,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: DashColors.text(context),
                      ),
                    ),
                    if (description.isNotEmpty)
                      TextSpan(
                        text: '  $description',
                        style: TextStyle(
                          fontSize: 13,
                          color: DashColors.muted(context),
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (nsfw)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 1.5,
                ),
                decoration: BoxDecoration(
                  color: DashColors.danger.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text(
                  'NSFW',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: DashColors.danger,
                  ),
                ),
              ),
            if (isFavorite)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(
                  CupertinoIcons.heart_fill,
                  size: 14,
                  color: DashColors.feed,
                ),
              ),
          ],
        ),
      ),
    );

    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: favoriteLabel): onToggleFavorite,
      },
      child: Slidable(
        endActionPane: swipeActions(
          label: isFavorite ? 'Remove' : 'Favorite',
          icon: isFavorite
              ? CupertinoIcons.heart_slash_fill
              : CupertinoIcons.heart_fill,
          color: isFavorite ? DashColors.danger : DashColors.feed,
          onPressed: onToggleFavorite,
          borderRadius: BorderRadius.zero,
        ),
        child: SlidableBackSwipe(child: row),
      ),
    );
  }
}
