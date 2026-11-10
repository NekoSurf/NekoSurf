import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/ui/colors.dart';

/// Uploads shown after all, until the app closes.
final ValueNotifier<Set<int>> revealedSpoilers = ValueNotifier<Set<int>>(
  const <int>{},
);

bool isSpoilerCovered(int? upload) =>
    upload != null && !revealedSpoilers.value.contains(upload);

/// Covers [child] if it's a spoilered [upload] (its `tim`; null if it isn't
/// one), until it's tapped, which goes for everywhere that upload shows.
///
/// With [canReveal] false, the tap is left to what's around it, like a thread
/// row opening the thread.
class SpoilerCover extends StatelessWidget {
  const SpoilerCover({
    super.key,
    required this.upload,
    required this.child,
    this.canReveal = true,
  });

  final int? upload;
  final Widget child;
  final bool canReveal;

  void _reveal() {
    revealedSpoilers.value = <int>{...revealedSpoilers.value, upload!};
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<int>>(
      valueListenable: revealedSpoilers,
      builder: (context, _, _) =>
          isSpoilerCovered(upload) ? _cover(context) : child,
    );
  }

  Widget _cover(BuildContext context) {
    final Color color = DashColors.muted(context);
    final Widget cover = ColoredBox(
      color: DashColors.card(context),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.eye_slash,
              color: color,
              semanticLabel: canReveal ? 'Spoiler, tap to show' : 'Spoiler',
            ),
            if (canReveal) ...[
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

    return canReveal
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _reveal,
            child: cover,
          )
        : cover;
  }
}
