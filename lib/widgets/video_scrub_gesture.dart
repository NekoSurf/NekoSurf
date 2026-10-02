import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

/// Horizontal drag over [child] scrubs [player], showing a time preview.
class VideoScrubGesture extends StatefulWidget {
  const VideoScrubGesture({
    super.key,
    required this.player,
    required this.child,
    this.onScrubStateChanged,
    this.onPreviewChanged,
    this.edgeInset = 24,
  });

  final Player? player;
  final Widget child;
  final ValueChanged<bool>? onScrubStateChanged;

  /// Preview position while scrubbing; null once the scrub ends.
  final ValueChanged<Duration?>? onPreviewChanged;

  /// Drags starting this close to the screen's left edge are left to the
  /// back-swipe gesture.
  final double edgeInset;

  @override
  State<VideoScrubGesture> createState() => _VideoScrubGestureState();
}

class _VideoScrubGestureState extends State<VideoScrubGesture> {
  bool _isScrubbing = false;
  double _previewMs = 0;
  Duration _duration = Duration.zero;

  void _handleStart(DragStartDetails details) {
    final player = widget.player;
    if (player == null) {
      return;
    }

    final duration = player.state.duration;
    if (duration <= Duration.zero) {
      return;
    }

    _duration = duration;
    _previewMs = player.state.position.inMilliseconds.toDouble();
    setState(() => _isScrubbing = true);
    widget.onScrubStateChanged?.call(true);
    widget.onPreviewChanged?.call(Duration(milliseconds: _previewMs.round()));
  }

  void _handleUpdate(DragUpdateDetails details) {
    if (!_isScrubbing) {
      return;
    }

    final double width = context.size?.width ?? 0;
    final double durationMs = _duration.inMilliseconds.toDouble();
    if (width <= 0 || durationMs <= 0) {
      return;
    }

    final double msPerWidth = durationMs.clamp(15000.0, 90000.0);
    setState(() {
      _previewMs = (_previewMs + details.delta.dx / width * msPerWidth).clamp(
        0.0,
        durationMs,
      );
    });
    widget.onPreviewChanged?.call(Duration(milliseconds: _previewMs.round()));
  }

  Future<void> _handleEnd(DragEndDetails details) async {
    if (!_isScrubbing) {
      return;
    }

    final target = Duration(milliseconds: _previewMs.round());
    _stopScrubbing();
    try {
      await widget.player?.seek(target);
    } catch (_) {}
  }

  void _stopScrubbing() {
    if (!_isScrubbing) {
      return;
    }

    setState(() => _isScrubbing = false);
    widget.onScrubStateChanged?.call(false);
    widget.onPreviewChanged?.call(null);
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
                  ..onCancel = _stopScrubbing;
              },
            ),
      },
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          if (_isScrubbing)
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
                    child: Text(
                      '${_format(Duration(milliseconds: _previewMs.round()))} / ${_format(_duration)}',
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
