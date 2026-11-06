import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/media/image_cache.dart';
import 'package:flutter_chan/media/media_video.dart';
import 'package:flutter_chan/media/post_thumbnail.dart';
import 'package:flutter_chan/media/video_scrub_gesture.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// An inline video that plays while it's on screen.
///
/// What counts is the part below the top padding, which in a thread
/// includes the floating header the list runs behind. With more videos on
/// screen than players, the ones shown most play (see [MediaVideo.want]).
///
/// It shows the same [MediaVideo] as the fullscreen viewer, so tapping it
/// continues the very same playback fullscreen, zooming from [boxKey].
class InlineVideo extends StatefulWidget {
  const InlineVideo({
    super.key,
    required this.videoUrl,
    required this.thumbnailUrl,
    required this.aspectRatio,
    this.videoWidth,
    this.videoHeight,
    this.boxKey,
    required this.preload,
    required this.autoplay,
    required this.startMuted,
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

  /// Plays while it's on screen; otherwise it only plays once opened.
  final bool autoplay;
  final bool startMuted;
  final VoidCallback? onTap;

  @override
  State<InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<InlineVideo> {
  static const double _playVisibilityThreshold = 0.02;
  static const double _pauseVisibilityThreshold = 0.01;
  // Smaller changes while scrolling don't change which videos play.
  static const double _shownStep = 0.05;

  // Per-instance: two posts can share a video URL.
  final Key _visibilityKey = UniqueKey();

  late MediaVideo _video;
  bool _visible = false;
  bool _tickerEnabled = true;

  // How much is inside the list's viewport, from VisibilityDetector, and
  // how much of that isn't under the header.
  double _inViewport = 0;
  double _shown = 0;
  double _screenTop = 0;
  double _screenBottom = 0;
  ScrollPosition? _scrollPosition;
  bool _measureScheduled = false;

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

    _screenTop = MediaQuery.paddingOf(context).top;
    _screenBottom = MediaQuery.sizeOf(context).height;
    final ScrollPosition? position = Scrollable.maybeOf(context)?.position;
    if (position != _scrollPosition) {
      _scrollPosition?.removeListener(_measureSoon);
      _scrollPosition = position?..addListener(_measureSoon);
    }

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
  void didUpdateWidget(covariant InlineVideo oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!oldWidget.preload && widget.preload) {
      _video.prefetch();
    }
  }

  void _handleVisibility(VisibilityInfo info) {
    _inViewport = info.visibleFraction;
    _measure();
  }

  // Scrolling moves the video under the header without VisibilityDetector
  // noticing: inside the viewport, nothing about it changes. Measured once
  // the frame is laid out.
  void _measureSoon() {
    if (_inViewport == 0 || _measureScheduled) {
      return;
    }
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (mounted) {
        _measure();
      }
    });
  }

  void _measure() {
    double shown = _inViewport;
    final RenderObject? box = context.findRenderObject();
    if (shown > 0 && box is RenderBox && box.attached && box.hasSize) {
      final Rect rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.height > 0) {
        final double below =
            min(rect.bottom, _screenBottom) - max(rect.top, _screenTop);
        shown = min(shown, (below / rect.height).clamp(0.0, 1.0));
      }
    }

    final bool visible = _visible
        ? shown > _pauseVisibilityThreshold
        : shown >= _playVisibilityThreshold;
    if (visible == _visible && (shown - _shown).abs() < _shownStep) {
      return;
    }
    _visible = visible;
    _shown = shown;
    _updateDemand();
  }

  void _updateDemand() {
    if (_visible && _tickerEnabled && widget.autoplay) {
      _video.want(this, shown: _shown);
    } else {
      _video.unwant(this);
    }
  }

  @override
  void dispose() {
    _scrollPosition?.removeListener(_measureSoon);
    _video.release(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget thumbnail = Image(
      image: thumbnailImage(widget.thumbnailUrl),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: imageErrorPlaceholder,
    );
    // Without autoplay (data saver) the feed only shows the thumbnail, even
    // when the fullscreen viewer has already loaded this video: the shared
    // player would otherwise show its frame here after going back.
    final Widget view = widget.autoplay
        ? MediaVideoView(video: _video, fit: BoxFit.cover, thumbnail: thumbnail)
        : thumbnail;
    return GestureDetector(
      onTap: widget.onTap,
      child: VisibilityDetector(
        key: _visibilityKey,
        onVisibilityChanged: _handleVisibility,
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
                  if (widget.autoplay)
                    _InlineOverlay(video: _video)
                  else
                    const Center(
                      child: Icon(
                        CupertinoIcons.play_circle_fill,
                        color: Colors.white,
                        size: 44,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
                    semanticLabel: video.muted ? 'Unmute' : 'Mute',
                  ),
                ),
              ),
            ),
            if (durationMs > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ListenableBuilder(
                  listenable: video.progressChanged,
                  builder: (context, _) {
                    return CustomPaint(
                      size: const Size.fromHeight(3),
                      painter: _ProgressPainter(
                        position:
                            (video.shownPosition.inMilliseconds / durationMs)
                                .clamp(0.0, 1.0),
                        loaded: video.loaded.value,
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ProgressPainter extends CustomPainter {
  const _ProgressPainter({required this.position, required this.loaded});

  final double position;
  final List<(double, double)> loaded;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = Colors.white.withValues(alpha: 0.2);
    canvas.drawRect(Offset.zero & size, paint);
    paint.color = Colors.white.withValues(alpha: 0.4);
    for (final (double start, double end) in loaded) {
      canvas.drawRect(
        Rect.fromLTRB(start * size.width, 0, end * size.width, size.height),
        paint,
      );
    }
    paint.color = Colors.white;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, position * size.width, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ProgressPainter old) =>
      old.position != position || old.loaded != loaded;
}
