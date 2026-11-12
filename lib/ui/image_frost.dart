import 'package:flutter/widgets.dart';

/// Looks frosted, but isn't blurred: a blur of what's behind it has to be redone
/// for each card in every frame, which makes scrolling a grid stutter. So this
/// shows a tiny copy of the card's image, stretched to the card and cut to the
/// chip, which draws like any other image.
class ImageFrost extends StatelessWidget {
  const ImageFrost({
    super.key,
    required this.image,
    required this.card,
    required this.anchor,
    required this.inset,
    required this.radius,
    required this.tint,
    required this.child,
    this.padding,
  });

  /// The image filling the card, or null to show just the tint.
  final ImageProvider? image;

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
    final ImageProvider? image = this.image;

    // Passthrough, so that a chip given a width, like a bar across the card,
    // is tinted all the way across and not just behind its child.
    return Stack(
      fit: StackFit.passthrough,
      children: [
        if (image != null)
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
                    image: ResizeImage.resizeIfNeeded(16, null, image),
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
