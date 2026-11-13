import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:provider/provider.dart';

/// Uploads shown after all, until the app closes.
final ValueNotifier<Set<int>> revealedSpoilers = ValueNotifier<Set<int>>(
  const <int>{},
);

/// The upload of [post] to cover until it's tapped (its `tim`), or null: a
/// spoiler, or, with NSFW images covered, any on an NSFW board. Rebuilds
/// [context] when that setting changes.
int? coveredUpload(BuildContext context, Post post) {
  final bool nsfwCovered = context.select<SettingsProvider, bool>(
    (settings) =>
        settings.blurNsfwImages.value && settings.isNsfwBoard(post.board),
  );
  return post.spoilerUpload ?? (nsfwCovered ? post.tim : null);
}

/// What [SpoilerCover] says it is, for [post]'s upload.
String coverLabel(Post post) => post.spoilerUpload != null ? 'Spoiler' : 'NSFW';

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
    this.label = 'Spoiler',
    this.alignment = Alignment.center,
  });

  final int? upload;
  final Widget child;
  final bool canReveal;

  /// What it says it is: a spoiler, or NSFW ([coverLabel]).
  final String label;

  /// Where its icon goes: in the middle of what of it can be seen, where
  /// text covers part of it.
  final AlignmentGeometry alignment;

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
      child: Align(
        alignment: alignment,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.eye_slash,
              color: color,
              semanticLabel: canReveal ? '$label, tap to show' : label,
            ),
            if (canReveal) ...[
              const SizedBox(height: 6),
              ExcludeSemantics(
                child: Text(
                  label,
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
