import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:visibility_detector/visibility_detector.dart';

class FeedVideoPlayer extends StatefulWidget {
  const FeedVideoPlayer({
    super.key,
    required this.videoUrl,
    required this.thumbnailUrl,
    required this.aspectRatio,
  });

  final String videoUrl;
  final String thumbnailUrl;
  final double aspectRatio;

  @override
  State<FeedVideoPlayer> createState() => _FeedVideoPlayerState();
}

class _FeedVideoPlayerState extends State<FeedVideoPlayer> {
  Player? _player;
  VideoController? _controller;

  bool _visible = false;
  bool _initialized = false;
  bool _hasFirstFrame = false;
  bool _isMuted = true;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;

  // ---------------------------
  // Lifecycle
  // ---------------------------

  Future<void> _initAndPlay() async {
    if (_initialized) {
      return;
    }

    final player = Player();
    final controller = VideoController(player);

    _player = player;
    _controller = controller;

    try {
      await player.open(Media(widget.videoUrl));
      await player.setAudioTrack(AudioTrack.no());
      await player.setPlaylistMode(PlaylistMode.loop);

      _positionSub = player.stream.position.listen((pos) {
        if (pos > Duration.zero && !_hasFirstFrame) {
          if (mounted) {
            setState(() {
              _hasFirstFrame = true;
            });
          }
        }
        if (mounted) {
          setState(() => _position = pos);
        }
      });
      _durationSub = player.stream.duration.listen((dur) {
        if (mounted) {
          setState(() => _duration = dur);
        }
      });

      if (!mounted) {
        return;
      }

      setState(() {
        _initialized = true;
      });

      await player.play();
    } catch (_) {
      // keep it simple: fail silently for feed
    }
  }

  Future<void> _pauseAndDispose() async {
    final player = _player;

    _positionSub?.cancel();
    _positionSub = null;

    _durationSub?.cancel();
    _durationSub = null;

    if (player != null) {
      try {
        await player.pause();
        await player.dispose();
      } catch (_) {}
    }

    _player = null;
    _controller = null;

    if (mounted) {
      setState(() {
        _initialized = false;
        _hasFirstFrame = false;
      });
    }
  }

  // ---------------------------
  // Visibility
  // ---------------------------

  void _handleVisibility(double fraction) {
    final shouldPlay = fraction > 0;

    if (shouldPlay && !_visible) {
      _visible = true;
      _initAndPlay();
    } else if (!shouldPlay && _visible) {
      _visible = false;
      _pauseAndDispose();
    }
  }

  // ---------------------------
  // UI
  // ---------------------------

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: ValueKey(widget.videoUrl),
      onVisibilityChanged: (info) {
        _handleVisibility(info.visibleFraction);
      },
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(widget.thumbnailUrl, fit: BoxFit.cover),

              if (_controller != null)
                AnimatedOpacity(
                  opacity: _hasFirstFrame ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Video(
                    controller: _controller!,
                    fit: BoxFit.cover,
                    controls: NoVideoControls,
                  ),
                ),

              if (_visible && !_hasFirstFrame)
                const Center(child: CupertinoActivityIndicator()),

              if (_controller != null)
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: GestureDetector(
                    onTap: () async {
                      final player = _player;
                      if (player == null) {
                        return;
                      }

                      final nextMuted = !_isMuted;

                      try {
                        await player.setAudioTrack(
                          nextMuted ? AudioTrack.no() : AudioTrack.auto(),
                        );

                        if (!mounted) {
                          return;
                        }

                        setState(() {
                          _isMuted = nextMuted;
                        });
                      } catch (_) {}
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        _isMuted ? Icons.volume_off : Icons.volume_up,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),

              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: _duration.inMicroseconds > 0
                      ? (_position.inMicroseconds / _duration.inMicroseconds)
                            .clamp(0.0, 1.0)
                      : 0.0,
                  backgroundColor: Colors.white.withValues(alpha: 0.25),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  minHeight: 3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pauseAndDispose();
    super.dispose();
  }
}
