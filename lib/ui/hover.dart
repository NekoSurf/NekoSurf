import 'package:flutter/material.dart';
import 'package:flutter_chan/ui/colors.dart';

/// A tint over [child] while a pointer (a trackpad or mouse on an iPad or
/// tablet) is over it, so what can be clicked shows it. Fingers don't
/// hover, so on a phone it never shows.
class HoverHighlight extends StatefulWidget {
  const HoverHighlight({super.key, required this.child, this.radius = 14});

  final Widget child;

  /// The corners of the tint, as the shape under it.
  final double radius;

  @override
  State<HoverHighlight> createState() => _HoverHighlightState();
}

class _HoverHighlightState extends State<HoverHighlight> {
  bool _hovered = false;

  void _hover(bool hovered) {
    if (hovered != _hovered) {
      setState(() => _hovered = hovered);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _hover(true),
      onExit: (_) => _hover(false),
      // Sized as the child would be on its own: a tab fills its slot, a card
      // its column.
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _hovered ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(widget.radius),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
