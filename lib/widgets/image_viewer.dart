import 'package:flutter/cupertino.dart';

class ImageViewer extends StatelessWidget {
  const ImageViewer({
    super.key,
    required this.url,
    this.interactiveViewer = false,
    this.fit = BoxFit.contain,
    this.height,
    this.width,
  });

  final String url;
  final bool interactiveViewer;
  final BoxFit fit;
  final double? height;
  final double? width;

  Widget _loadingBuilder(
    BuildContext context,
    Widget child,
    ImageChunkEvent? loadingProgress,
  ) {
    if (loadingProgress == null) {
      return child;
    }

    return const Center(child: CupertinoActivityIndicator());
  }

  @override
  Widget build(BuildContext context) {
    return interactiveViewer
        ? InteractiveViewer(
            minScale: 0.5,
            maxScale: 5,
            child: Image.network(
              url,
              loadingBuilder: _loadingBuilder,
              errorBuilder: imageErrorPlaceholder,
            ),
          )
        : Image.network(
            url,
            fit: fit,
            height: height,
            width: width,
            loadingBuilder: _loadingBuilder,
            frameBuilder: fadeInImageFrame,
            errorBuilder: imageErrorPlaceholder,
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
  final bool isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

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
