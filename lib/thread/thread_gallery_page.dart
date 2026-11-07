import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/media/image_cache.dart';
import 'package:flutter_chan/media/post_thumbnail.dart';
import 'package:flutter_chan/media/spoiler_cover.dart';
import 'package:flutter_chan/thread/media_viewer_route.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_scaffold.dart';
import 'package:flutter_chan/ui/pills.dart';

class ThreadGalleryPage extends StatefulWidget {
  const ThreadGalleryPage({super.key, required this.mediaPosts});

  final List<Post> mediaPosts;

  @override
  State<ThreadGalleryPage> createState() => _ThreadGalleryPageState();
}

class _ThreadGalleryPageState extends State<ThreadGalleryPage> {
  MediaFilter _filter = MediaFilter.all;

  /// Swiping in the viewer stays within what's shown here.
  void _open(List<Post> shown, int index) {
    Navigator.of(
      context,
    ).push<int>(ThreadMediaViewerRoute(mediaPosts: shown, initialIndex: index));
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;
    final List<Post> mediaPosts = widget.mediaPosts;
    final int videos = mediaPosts.where((post) => post.isVideo).length;
    final int images = mediaPosts.length - videos;
    final List<Post> shown = mediaPosts
        .where((post) => _filter.shows(isVideo: post.isVideo))
        .toList();
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
        // With only one kind, there's nothing to choose between.
        if (images > 0 && videos > 0)
          SliverToBoxAdapter(
            child: MediaFilterPills(
              filter: _filter,
              images: images,
              videos: videos,
              sidePadding: 8,
              onChanged: (MediaFilter filter) =>
                  setState(() => _filter = filter),
            ),
          ),
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
              itemCount: shown.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemBuilder: (context, index) {
                final Post post = shown[index];
                return GestureDetector(
                  key: ValueKey<int>(post.no),
                  onTap: () => _open(shown, index),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: DashColors.border(isDark)),
                        SpoilerCover(
                          upload: post.spoilerUpload,
                          canReveal: false,
                          child: Image(
                            image: ResizeImage.resizeIfNeeded(
                              decodeWidth,
                              null,
                              thumbnailImage(post.thumbnailUrl),
                            ),
                            fit: BoxFit.cover,
                            frameBuilder: fadeInImageFrame,
                            errorBuilder: imageErrorPlaceholder,
                          ),
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
