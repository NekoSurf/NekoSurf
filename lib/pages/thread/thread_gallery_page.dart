import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/API/urls.dart' as urls;
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';
import 'package:flutter_chan/pages/thread/thread_media_viewer_page.dart';
import 'package:flutter_chan/services/image_cache.dart';
import 'package:flutter_chan/widgets/dash_scaffold.dart';
import 'package:flutter_chan/widgets/image_viewer.dart';

/// Every image and video in a thread as a grid. Tapping one opens the
/// fullscreen viewer at that item, paging through the thread's media.
class ThreadGalleryPage extends StatelessWidget {
  const ThreadGalleryPage({
    super.key,
    required this.board,
    required this.thread,
    required this.mediaPosts,
  });

  final String board;
  final int thread;
  final List<Post> mediaPosts;

  void _open(BuildContext context, int index) {
    Navigator.of(context).push<int>(
      ThreadMediaViewerRoute(
        mediaPosts: mediaPosts,
        initialIndex: index,
        board: board,
        thread: thread,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final int videos = mediaPosts.where((post) => post.isVideo).length;
    final int images = mediaPosts.length - videos;
    final double width = MediaQuery.sizeOf(context).width;
    final int columns = (width / 130).floor().clamp(3, 8);
    final int decodeWidth =
        (width / columns * MediaQuery.devicePixelRatioOf(context)).round();

    return DashScaffold(
      title: 'Gallery',
      subtitle: [
        if (images > 0) '$images ${images == 1 ? 'image' : 'images'}',
        if (videos > 0) '$videos ${videos == 1 ? 'video' : 'videos'}',
      ].join(' · '),
      slivers: [
        if (mediaPosts.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                'No images or videos in this thread.',
                style: TextStyle(color: DashColors.muted(isDark)),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
            sliver: SliverGrid.builder(
              itemCount: mediaPosts.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemBuilder: (context, index) {
                final Post post = mediaPosts[index];
                return GestureDetector(
                  onTap: () => _open(context, index),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: DashColors.border(isDark)),
                        Image(
                          image: ResizeImage.resizeIfNeeded(
                            decodeWidth,
                            null,
                            thumbnailImage(urls.thumbnail(board, post.tim)),
                          ),
                          fit: BoxFit.cover,
                          frameBuilder: fadeInImageFrame,
                          errorBuilder: imageErrorPlaceholder,
                        ),
                        if (post.isVideo)
                          const Positioned(
                            right: 6,
                            bottom: 6,
                            child: _VideoBadge(),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _VideoBadge extends StatelessWidget {
  const _VideoBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(
        CupertinoIcons.play_fill,
        size: 12,
        color: Colors.white,
      ),
    );
  }
}
