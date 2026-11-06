import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/media/image_cache.dart';
import 'package:flutter_chan/media/spoiler_cover.dart';
import 'package:flutter_chan/ui/colors.dart';

/// Corner radius of media in a post; the zoom into fullscreen rounds it off.
const double mediaInlineRadius = 12;

class PostThumbnail extends StatelessWidget {
  const PostThumbnail({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    if (post.tim == null) {
      return imageErrorPlaceholder(context, 'No file', null);
    }
    return SpoilerCover(
      upload: post.spoilerUpload,
      canReveal: false,
      child: Image(
        image: thumbnailImage(post.thumbnailUrl),
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) =>
            loadingProgress == null
            ? child
            : const Center(child: CupertinoActivityIndicator()),
        frameBuilder: fadeInImageFrame,
        errorBuilder: imageErrorPlaceholder,
      ),
    );
  }
}

/// Fades an image in once its first frame is decoded, instead of popping in.
/// Images already in memory (e.g. scrolled back to) show immediately.
Widget fadeInImageFrame(
  BuildContext context,
  Widget child,
  int? frame,
  bool wasSynchronouslyLoaded,
) {
  if (wasSynchronouslyLoaded) {
    return child;
  }

  return AnimatedOpacity(
    opacity: frame == null ? 0 : 1,
    duration: const Duration(milliseconds: 180),
    curve: Curves.easeOut,
    child: child,
  );
}

/// Shown instead of Flutter's debug error box when an image fails to load,
/// e.g. a thumbnail 4chan has already deleted.
Widget imageErrorPlaceholder(
  BuildContext context,
  Object error,
  StackTrace? stackTrace,
) {
  final bool isDark = context.isDark;

  return ColoredBox(
    color: isDark ? const Color(0xFF1C1F26) : const Color(0xFFE6E8EC),
    child: Center(
      child: Icon(
        CupertinoIcons.photo,
        size: 28,
        color: isDark ? const Color(0xFF4B5160) : const Color(0xFFA3A9B5),
      ),
    ),
  );
}
