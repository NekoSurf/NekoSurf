import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';

// Uploads shown after all, until the app closes.
final Set<int> _revealed = <int>{};

/// Whether the spoilered upload is still covered.
bool isSpoilerCovered(int? upload) =>
    upload != null && !_revealed.contains(upload);

@visibleForTesting
void resetRevealedSpoilers() => _revealed.clear();

/// Covers [child] if it's a spoilered [upload] (its `tim`; null if it isn't
/// one), until it's tapped, which goes for everywhere that upload shows.
///
/// With [canReveal] false, the tap is left to what's around it, like a thread
/// row opening the thread.
class SpoilerCover extends StatefulWidget {
  const SpoilerCover({
    super.key,
    required this.upload,
    required this.child,
    this.canReveal = true,
    this.onRevealed,
  });

  final int? upload;
  final Widget child;
  final bool canReveal;
  final VoidCallback? onRevealed;

  @override
  State<SpoilerCover> createState() => _SpoilerCoverState();
}

class _SpoilerCoverState extends State<SpoilerCover> {
  void _reveal() {
    setState(() => _revealed.add(widget.upload!));
    widget.onRevealed?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (!isSpoilerCovered(widget.upload)) {
      return widget.child;
    }

    final bool isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final Color color = DashColors.muted(isDark);
    final Widget cover = ColoredBox(
      color: DashColors.card(isDark),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.eye_slash,
              color: color,
              semanticLabel: widget.canReveal
                  ? 'Spoiler, tap to show'
                  : 'Spoiler',
            ),
            if (widget.canReveal) ...[
              const SizedBox(height: 6),
              ExcludeSemantics(
                child: Text(
                  'Spoiler',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return widget.canReveal
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _reveal,
            child: cover,
          )
        : cover;
  }
}
