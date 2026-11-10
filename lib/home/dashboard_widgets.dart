import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_widgets.dart';

class DashHero extends StatelessWidget {
  const DashHero({super.key});

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 5) {
      return 'Night owl mode';
    }
    if (hour < 12) {
      return 'Good morning';
    }
    if (hour < 18) {
      return 'Good afternoon';
    }
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  context.accent.withValues(alpha: 0.22),
                  context.accent2.withValues(alpha: 0.18),
                ]
              : [
                  context.accent.withValues(alpha: 0.35),
                  context.accent2.withValues(alpha: 0.28),
                ],
        ),
        border: Border.all(color: context.accent.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -50,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    context.accent2.withValues(alpha: 0.35),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: context.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _greeting,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: DashColors.text(context),
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
  });

  final String board;
  final String title;
  final String description;
  final bool isFavorite;
  final bool nsfw;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final color = nsfw ? DashColors.danger : boardColor(board);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(13),
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 3),
              // Stays on one line, however large the text is set.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '/$board/',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: board.length > 3 ? 10 : 12,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: DashColors.text(context),
                          ),
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
                    ],
                  ),
                  if (description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: DashColors.muted(context),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.all(6),
              minimumSize: const Size(32, 32),
              onPressed: onToggleFavorite,
              child: Icon(
                isFavorite ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                semanticLabel: isFavorite
                    ? 'Remove from favorites'
                    : 'Add to favorites',
                size: 20,
                color: isFavorite ? DashColors.feed : DashColors.muted(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
