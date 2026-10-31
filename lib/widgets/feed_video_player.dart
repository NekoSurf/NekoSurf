import 'package:flutter/material.dart';
import 'package:flutter_chan/services/image_cache.dart';
import 'package:flutter_chan/widgets/image_viewer.dart';
import 'package:flutter_chan/widgets/media_video.dart';
import 'package:flutter_chan/widgets/video_scrub_gesture.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// An inline video that plays while it's on screen.
///
/// It shows the same [MediaVideo] as the fullscreen viewer, so tapping it
/// continues the very same playback fullscreen, zooming from [boxKey].
class FeedVideoPlayer extends StatefulWidget {
  const FeedVideoPlayer({
    super.key,
    required this.videoUrl,
    required this.thumbnailUrl,
    required this.aspectRatio,
    this.videoWidth,
    this.videoHeight,
    this.boxKey,
    this.preload = false,
    this.startMuted = true,
    this.onTap,
  });

  final String videoUrl;
  final String thumbnailUrl;
  final double aspectRatio;
  final int? videoWidth;
  final int? videoHeight;

  /// On the video's box, so the fullscreen viewer can zoom from and back
  /// into it.
  final Key? boxKey;

  /// Downloads the video ahead of time, as it's about to scroll into view.
  final bool preload;
  final bool startMuted;
  final VoidCallback? onTap;

  @override
  State<FeedVideoPlayer> createState() => _FeedVideoPlayerState();
}

class _FeedVideoPlayerState extends State<FeedVideoPlayer> {
  static const double _playVisibilityThreshold = 0.02;
  static const double _pauseVisibilityThreshold = 0.01;

  // Per-instance: two posts can share a video URL.
  final Key _visibilityKey = UniqueKey();

  late MediaVideo _video;
  bool _visible = false;
  bool _tickerEnabled = true;

  @override
  void initState() {
    super.initState();
    _video = _obtain();
  }

  MediaVideo _obtain() {
    final MediaVideo video = MediaVideo.obtain(
      widget.videoUrl,
      width: widget.videoWidth,
      height: widget.videoHeight,
      muted: widget.startMuted,
    );
    if (widget.preload) {
      video.prefetch();
    }
    return video;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Routes covered by an opaque route (like the fullscreen viewer) stop
    // painting, so VisibilityDetector never reports them as hidden; the
    // Overlay disables their TickerMode.
    final bool tickerEnabled = TickerMode.valuesOf(context).enabled;
    if (tickerEnabled != _tickerEnabled) {
      _tickerEnabled = tickerEnabled;
      _updateDemand();
    }
  }

  @override
  void didUpdateWidget(covariant FeedVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.videoUrl != widget.videoUrl) {
      _video.unwant(this);
      _video.release();
      _video = _obtain();
      _updateDemand();
      return;
    }
    if (!oldWidget.preload && widget.preload) {
      _video.prefetch();
    }
    if (oldWidget.startMuted != widget.startMuted) {
      // Not during the build: other views of the video would rebuild.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _video.muted = widget.startMuted;
        }
      });
    }
  }

  void _handleVisibility(double fraction) {
    if (fraction >= _playVisibilityThreshold && !_visible) {
      _visible = true;
      _updateDemand();
    } else if (fraction <= _pauseVisibilityThreshold && _visible) {
      _visible = false;
      _updateDemand();
    }
  }

  void _updateDemand() {
    if (_visible && _tickerEnabled) {
      _video.want(this);
    } else {
      _video.unwant(this);
    }
  }

  @override
  void dispose() {
    _video.unwant(this);
    _video.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget view = MediaVideoView(
      video: _video,
      fit: BoxFit.cover,
      thumbnail: Image(
        image: thumbnailImage(widget.thumbnailUrl),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: imageErrorPlaceholder,
      ),
    );
    return GestureDetector(
      onTap: widget.onTap,
      child: VisibilityDetector(
        key: _visibilityKey,
        onVisibilityChanged: (info) => _handleVisibility(info.visibleFraction),
        child: VideoScrubGesture(
          video: _video,
          child: AspectRatio(
            key: widget.boxKey,
            aspectRatio: widget.aspectRatio,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(mediaInlineRadius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  view,
                  _InlineOverlay(video: _video),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mute button and progress bar, once the video shows.
class _InlineOverlay extends StatelessWidget {
  const _InlineOverlay({required this.video});

  final MediaVideo video;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: video,
      builder: (context, _) {
        if (!video.hasFirstFrame) {
          return const SizedBox.shrink();
        }
        final int durationMs = video.duration.inMilliseconds;

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              bottom: 8,
              left: 8,
              child: GestureDetector(
                onTap: () => video.muted = !video.muted,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    video.muted ? Icons.volume_off : Icons.volume_up,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),
            if (durationMs > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ValueListenableBuilder<Duration?>(
                  valueListenable: video.scrubPosition,
                  builder: (context, scrub, _) =>
                      ValueListenableBuilder<Duration>(
                        valueListenable: video.position,
                        builder: (context, position, _) =>
                            LinearProgressIndicator(
                              value:
                                  ((scrub ?? position).inMilliseconds /
                                          durationMs)
                                      .clamp(0.0, 1.0),
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.2,
                              ),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                              minHeight: 3,
                            ),
                      ),
                ),
              ),
          ],
        );
      },
    );
  }
}
