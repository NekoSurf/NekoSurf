import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/widgets/media_video.dart';

/// Horizontal drag over [child] scrubs [video] live: it pauses, follows the
/// finger frame by frame and plays on when let go.
class VideoScrubGesture extends StatefulWidget {
  const VideoScrubGesture({
    super.key,
    required this.video,
    required this.child,
    this.onScrubStateChanged,
    this.edgeInset = 24,
  });

  /// Null while there's nothing to scrub yet.
  final MediaVideo? video;
  final Widget child;
  final ValueChanged<bool>? onScrubStateChanged;

  /// Drags starting this close to the screen's left edge are left to the
  /// back-swipe gesture.
  final double edgeInset;

  @override
  State<VideoScrubGesture> createState() => _VideoScrubGestureState();
}

class _VideoScrubGestureState extends State<VideoScrubGesture> {
  MediaVideo? _scrubbing;
  double _targetMs = 0;

  void _handleStart(DragStartDetails details) {
    final MediaVideo? video = widget.video;
    if (video == null ||
        !video.hasFirstFrame ||
        video.duration <= Duration.zero) {
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
    // Gone mid-scrub: let the video play on.
    final MediaVideo? video = _scrubbing;
    _scrubbing = null;
    if (video != null) {
      unawaited(video.scrubEnd());
    }
    super.dispose();
  }

  String _format(Duration value) {
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

  @override
  Widget build(BuildContext context) {
    final MediaVideo? scrubbing = _scrubbing;

    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        _EdgeExcludingHorizontalDragRecognizer:
            GestureRecognizerFactoryWithHandlers<
              _EdgeExcludingHorizontalDragRecognizer
            >(
              () => _EdgeExcludingHorizontalDragRecognizer(
                edgeInset: widget.edgeInset,
              ),
              (recognizer) {
                recognizer
                  ..edgeInset = widget.edgeInset
                  ..onStart = _handleStart
                  ..onUpdate = _handleUpdate
                  ..onEnd = _handleEnd
                  ..onCancel = _handleEnd;
              },
            ),
      },
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
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
                        '${_format(target ?? Duration.zero)} / '
                        '${_format(scrubbing.duration)}',
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

class _EdgeExcludingHorizontalDragRecognizer
    extends HorizontalDragGestureRecognizer {
  _EdgeExcludingHorizontalDragRecognizer({required this.edgeInset});

  double edgeInset;

  // Not claiming edge pointers keeps them away from the arena entirely.
  @override
  bool isPointerAllowed(PointerEvent event) {
    return event.position.dx > edgeInset && super.isPointerAllowed(event);
  }
}
