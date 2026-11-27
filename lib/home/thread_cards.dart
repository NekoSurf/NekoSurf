import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/media/post_thumbnail.dart';
import 'package:flutter_chan/ui/colors.dart';

/// A thread as a big picture card in a [ThreadCardRow].
class ThreadCard {
  const ThreadCard({required this.post, required this.onTap, this.badge});

  final Post post;
  final VoidCallback onTap;

  /// Over the picture's corner, like how many replies are new.
  final Widget? badge;
}

/// Threads as big picture cards side by side, swiped through sideways, like
/// "Continue reading" on the Boards tab.
class ThreadCardRow extends StatelessWidget {
  const ThreadCardRow({
    super.key,
    required this.cards,
    this.width = 180,
    this.imageHeight = 130,
  });

  final List<ThreadCard> cards;
  final double width;
  final double imageHeight;

  static const double _gap = 12;
  static const double _titleSize = 14;
  static const double _titleLineHeight = 1.3;

  @override
  Widget build(BuildContext context) {
    // Room for two lines of the title at the text size chosen.
    final double titleHeight =
        MediaQuery.textScalerOf(context).scale(_titleSize) *
        _titleLineHeight *
        2;
    return SizedBox(
      height: imageHeight + 8 + titleHeight + 4,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: cards.length,
        separatorBuilder: (_, _) => const SizedBox(width: _gap),
        itemBuilder: (context, i) =>
            _Card(card: cards[i], width: width, imageHeight: imageHeight),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.card,
    required this.width,
    required this.imageHeight,
  });

  final ThreadCard card;
  final double width;
  final double imageHeight;

  @override
  Widget build(BuildContext context) {
    final Post post = card.post;
    final Color color = boardColor(post.board);
    final Widget? badge = card.badge;

    return Semantics(
      button: true,
      label: '${post.title}, /${post.board}/',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: card.onTap,
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  height: imageHeight,
                  width: width,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (post.tim != null)
                        PostThumbnail(post: post)
                      else
                        _NoPicture(color: color),
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xA60B0D11),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '/${post.board}/',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: color,
                            ),
                          ),
                        ),
                      ),
                      if (badge != null)
                        Positioned(bottom: 10, right: 10, child: badge),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                post.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: ThreadCardRow._titleSize,
                  height: ThreadCardRow._titleLineHeight,
                  fontWeight: FontWeight.w700,
                  color: DashColors.text(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where a thread without a picture has one: its board's colour.
class _NoPicture extends StatelessWidget {
  const _NoPicture({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.5)],
        ),
      ),
      child: Center(
        child: Icon(
          CupertinoIcons.text_bubble,
          size: 30,
          color: color.withValues(alpha: 0.9),
        ),
      ),
    );
  }
}
