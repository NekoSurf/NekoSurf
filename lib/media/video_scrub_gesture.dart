import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chan/media/media_video.dart';

/// Horizontal drag over [child] scrubs [video] live: it pauses, follows the
/// finger frame by frame and plays on when let go. With [holdToFastForward],
/// holding a finger on it plays it at double speed until let go.
class VideoScrubGesture extends StatefulWidget {
  const VideoScrubGesture({
    super.key,
    required this.video,
    required this.child,
    this.onScrubStateChanged,
    this.holdToFastForward = false,
  });

  /// Drags starting this close to the screen's left edge are left to the
  /// back-swipe gesture.
  static const double edgeInset = 24;

  final MediaVideo video;
  final Widget child;
  final ValueChanged<bool>? onScrubStateChanged;

  /// Off for inline posts, where holding opens the post's menu.
  final bool holdToFastForward;

  @override
  State<VideoScrubGesture> createState() => _VideoScrubGestureState();
}

class _VideoScrubGestureState extends State<VideoScrubGesture> {
  MediaVideo? _scrubbing;
  MediaVideo? _fastForwarding;
  double _targetMs = 0;

  // Only a video showing its picture is scrubbed. A drag on one that isn't
  // (still loading, or failed) is left to what's behind it, like the page's
  // back swipe: claimed and then ignored, the swipe did nothing.
  bool _canScrub() =>
      widget.video.hasFirstFrame && widget.video.duration > Duration.zero;

  void _handleHoldStart(LongPressStartDetails details) {
    final MediaVideo video = widget.video;
    if (_scrubbing != null || !video.fastForwardStart()) {
      return;
    }
    _fastForwarding = video;
    HapticFeedback.selectionClick();
    setState(() {});
  }

  void _handleHoldRelease(LongPressEndDetails details) => _handleHoldEnd();

  void _handleHoldEnd() {
    final MediaVideo? video = _fastForwarding;
    if (video == null) {
      return;
    }
    _fastForwarding = null;
    video.fastForwardEnd();
    if (mounted) {
      setState(() {});
    }
  }

  void _handleStart(DragStartDetails details) {
    final MediaVideo video = widget.video;
    if (!_canScrub()) {
      return;
    }

    _scrubbing = video;
    _targetMs = video.position.value.inMilliseconds.toDouble();
    video.scrubStart();
    setState(() {});
    widget.onScrubStateChanged?.call(true);
  }

  void _handleUpdate(DragUpdateDetails details) {
    final MediaVideo? video = _scrubbing;
    if (video == null) {
      return;
    }

    final double width = context.size?.width ?? 0;
    final double durationMs = video.duration.inMilliseconds.toDouble();
    if (width <= 0 || durationMs <= 0) {
      return;
    }

    // A full swipe covers short videos whole, long ones a minute and a half.
    final double msPerWidth = durationMs.clamp(15000.0, 90000.0);
    _targetMs = (_targetMs + details.delta.dx / width * msPerWidth).clamp(
      0.0,
      durationMs,
    );
    video.scrubTo(Duration(milliseconds: _targetMs.round()));
  }

  void _handleEnd([DragEndDetails? details]) {
    final MediaVideo? video = _scrubbing;
    if (video == null) {
      return;
    }
    _scrubbing = null;
    unawaited(video.scrubEnd());
    if (mounted) {
      setState(() {});
    }
    widget.onScrubStateChanged?.call(false);
  }

  @override
  void dispose() {
    _fastForwarding?.fastForwardEnd();
    _fastForwarding = null;
    final MediaVideo? video = _scrubbing;
    _scrubbing = null;
    if (video != null) {
      unawaited(video.scrubEnd());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MediaVideo? scrubbing = _scrubbing;

    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        _EdgeExcludingHorizontalDragRecognizer:
            GestureRecognizerFactoryWithHandlers<
              _EdgeExcludingHorizontalDragRecognizer
            >(_EdgeExcludingHorizontalDragRecognizer.new, (recognizer) {
              recognizer
                ..canStart = _canScrub
                ..onStart = _handleStart
                ..onUpdate = _handleUpdate
                ..onEnd = _handleEnd
                ..onCancel = _handleEnd;
            }),
        if (widget.holdToFastForward)
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                LongPressGestureRecognizer.new,
                (recognizer) {
                  recognizer
                    ..onLongPressStart = _handleHoldStart
                    ..onLongPressEnd = _handleHoldRelease
                    ..onLongPressCancel = _handleHoldEnd;
                },
              ),
      },
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          if (_fastForwarding != null)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(child: _FastForwardLabel()),
            ),
          if (scrubbing != null)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.58),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ValueListenableBuilder<Duration?>(
                      valueListenable: scrubbing.scrubPosition,
                      builder: (context, target, _) => Text(
                        '${formatVideoTime(target ?? Duration.zero)} / '
                        '${formatVideoTime(scrubbing.duration)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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

/// Over the top of the video while it fast-forwards, like YouTube's.
class _FastForwardLabel extends StatelessWidget {
  const _FastForwardLabel();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        // Below the viewer's top bar.
        padding: const EdgeInsets.only(top: 64),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.58),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${MediaVideo.fastForwardRate.toStringAsFixed(0)}×',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  CupertinoIcons.forward_fill,
                  color: Colors.white,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EdgeExcludingHorizontalDragRecognizer
    extends HorizontalDragGestureRecognizer {
  _EdgeExcludingHorizontalDragRecognizer();

  /// Whether a drag starting now would scrub.
  bool Function() canStart = () => true;

  // Not claiming edge pointers, or any while there's nothing to scrub,
  // keeps them away from the arena entirely.
  @override
  bool isPointerAllowed(PointerEvent event) {
    return event.position.dx > VideoScrubGesture.edgeInset &&
        canStart() &&
        super.isPointerAllowed(event);
  }
}

String formatVideoTime(Duration value) {
  final int hours = value.inHours;
  final String minutes = value.inMinutes
      .remainder(60)
      .toString()
      .padLeft(2, '0');
  final String seconds = value.inSeconds
      .remainder(60)
      .toString()
      .padLeft(2, '0');

  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
  }

  return '$minutes:$seconds';
}
