import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/widgets/feed_player_recycler.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:visibility_detector/visibility_detector.dart';

class FeedVideoPlayer extends StatefulWidget {
  const FeedVideoPlayer({
    super.key,
    required this.videoUrl,
    required this.thumbnailUrl,
    required this.aspectRatio,
    this.preload = false,
    this.recycler,
  });

  final String videoUrl;
  final String thumbnailUrl;
  final double aspectRatio;
  final bool preload;
  final FeedPlayerRecycler? recycler;

  @override
  State<FeedVideoPlayer> createState() => _FeedVideoPlayerState();
}

class _FeedVideoPlayerState extends State<FeedVideoPlayer> {
  static const double _playVisibilityThreshold = 0.02;
  static const double _pauseVisibilityThreshold = 0.01;
  static const Duration _pauseDebounce = Duration(milliseconds: 550);

  Player? _player;
  VideoController? _controller;
  RecycledPlayer? _recycled;
  bool _isDisposing = false;
  int _opToken = 0;

  bool _visible = false;
  bool _initialized = false;
  bool _hasFirstFrame = false;
  bool _isMuted = true;

  final ValueNotifier<double> _progressValue = ValueNotifier<double>(0.0);
  final ValueNotifier<bool> _hasDuration = ValueNotifier<bool>(false);
  Duration _lastProgressUiPosition = Duration.zero;
  int _durationMicros = 0;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  Timer? _pauseDebounceTimer;

  @override
  void initState() {
    super.initState();

    if (widget.preload) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isDisposing || _player != null || _initialized) {
          return;
        }

        _initAndPlay(preloadWhileHidden: true);
      });
    }
  }

  @override
  void didUpdateWidget(covariant FeedVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!oldWidget.preload && widget.preload) {
      if (_player == null && !_isDisposing) {
        _initAndPlay(preloadWhileHidden: true);
      }
      return;
    }

    if (oldWidget.preload && !widget.preload && !_visible) {
      _schedulePauseAndDispose();
    }
  }

  // ---------------------------
  // Lifecycle
  // ---------------------------

  Future<void> _initAndPlay({bool preloadWhileHidden = false}) async {
    if (_isDisposing) {
      return;
    }

    _pauseDebounceTimer?.cancel();
    _pauseDebounceTimer = null;

    if (_initialized || _player != null) {
      return;
    }

    final token = ++_opToken;

    final RecycledPlayer? recycled = widget.recycler?.acquire();
    final player = recycled?.player ?? Player();
    final controller = recycled?.controller ?? VideoController(player);

    _player = player;
    _controller = controller;
    _recycled = recycled;

    if (mounted) {
      setState(() {
        // Attach video surface immediately while first frame is loading.
      });
    }

    try {
      await player.open(Media(widget.videoUrl), play: false);
      final shouldAbortOpen =
          _isDisposing ||
          token != _opToken ||
          _player != player ||
          (!_visible && !preloadWhileHidden);

      if (shouldAbortOpen) {
        // If we no longer own it, _pauseAndDispose/dispose already released it.
        if (_player == player) {
          _player = null;
          _controller = null;
          _recycled = null;
          await _releasePlayer(player, recycled);
        }
        return;
      }

      await player.setAudioTrack(AudioTrack.no());
      await player.setPlaylistMode(PlaylistMode.loop);

      _positionSub = player.stream.position.listen((pos) {
        if (token != _opToken || _player != player) {
          return;
        }

        if (pos > Duration.zero && !_hasFirstFrame) {
          if (mounted) {
            setState(() {
              _hasFirstFrame = true;
            });
          }
        }

        final durationMicros = _durationMicros;
        if (durationMicros <= 0) {
          return;
        }

        final shouldUpdateUi =
            pos == Duration.zero ||
            (pos - _lastProgressUiPosition).inMilliseconds >= 100;
        if (!shouldUpdateUi) {
          return;
        }

        _lastProgressUiPosition = pos;
        final nextProgress = (pos.inMicroseconds / durationMicros).clamp(
          0.0,
          1.0,
        );
        if (_progressValue.value != nextProgress) {
          _progressValue.value = nextProgress;
        }
      });
      _durationSub = player.stream.duration.listen((dur) {
        if (token != _opToken || _player != player) {
          return;
        }

        final micros = dur.inMicroseconds;
        _durationMicros = micros;
        final hasDurationNow = micros > 0;
        if (_hasDuration.value != hasDurationNow) {
          _hasDuration.value = hasDurationNow;
        }
      });

      if (!mounted ||
          _isDisposing ||
          token != _opToken ||
          _player != player ||
          (!_visible && !preloadWhileHidden)) {
        return;
      }

      setState(() {
        _initialized = true;
      });

      if (_visible) {
        await player.play();
      }
    } catch (_) {
      // keep it simple: fail silently for feed
      if (_player == player) {
        _player = null;
        _controller = null;
        _recycled = null;
        _positionSub?.cancel();
        _positionSub = null;
        _durationSub?.cancel();
        _durationSub = null;
        await _releasePlayer(player, recycled);
      }
    }
  }

  Future<void> _releasePlayer(Player player, RecycledPlayer? recycled) async {
    final recycler = widget.recycler;
    if (recycled != null && recycler != null) {
      await recycler.release(recycled);
      return;
    }

    try {
      await player.pause();
      await player.dispose();
    } catch (_) {}
  }

  Future<void> _pauseAndDispose() async {
    if (_isDisposing) {
      return;
    }

    _pauseDebounceTimer?.cancel();
    _pauseDebounceTimer = null;

    ++_opToken;

    final player = _player;
    final recycled = _recycled;
    final positionSub = _positionSub;
    final durationSub = _durationSub;

    _player = null;
    _controller = null;
    _recycled = null;
    _positionSub = null;
    _durationSub = null;

    if (mounted) {
      setState(() {
        _initialized = false;
        _hasFirstFrame = false;
      });
    }

    _lastProgressUiPosition = Duration.zero;
    _durationMicros = 0;
    _progressValue.value = 0.0;
    _hasDuration.value = false;

    await positionSub?.cancel();
    await durationSub?.cancel();

    if (player != null) {
      await _releasePlayer(player, recycled);
    }
  }

  Future<void> _pauseOnly() async {
    final player = _player;
    if (player == null) {
      return;
    }

    try {
      await player.pause();
    } catch (_) {}
  }

  // ---------------------------
  // Visibility
  // ---------------------------

  void _schedulePauseAndDispose() {
    if (widget.preload) {
      unawaited(_pauseOnly());
      return;
    }

    _pauseDebounceTimer?.cancel();
    _pauseDebounceTimer = Timer(_pauseDebounce, () {
      if (_isDisposing || _visible || widget.preload) {
        return;
      }

      _pauseAndDispose();
    });
  }

  void _handleVisibility(double fraction) {
    final isVisible = fraction >= _playVisibilityThreshold;

    if (isVisible) {
      _pauseDebounceTimer?.cancel();
      _pauseDebounceTimer = null;

      if (!_visible) {
        _visible = true;
        if (_player == null || !_initialized) {
          _initAndPlay();
        } else {
          unawaited(() async {
            try {
              await _player?.play();
            } catch (_) {}
          }());
        }
      }

      return;
    }

    final shouldPause = fraction <= _pauseVisibilityThreshold;

    if (!shouldPause) {
      return;
    }

    if (_visible) {
      _visible = false;
      _schedulePauseAndDispose();
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

              if (_controller != null && _hasFirstFrame)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _hasDuration,
                    builder: (context, hasDuration, _) {
                      if (!hasDuration) {
                        return const SizedBox.shrink();
                      }

                      return ValueListenableBuilder<double>(
                        valueListenable: _progressValue,
                        builder: (context, progress, _) {
                          return LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.25,
                            ),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                            minHeight: 3,
                          );
                        },
                      );
                    },
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
    _isDisposing = true;
    ++_opToken;

    _pauseDebounceTimer?.cancel();
    _pauseDebounceTimer = null;

    final player = _player;
    final recycled = _recycled;
    final positionSub = _positionSub;
    final durationSub = _durationSub;

    _player = null;
    _controller = null;
    _recycled = null;
    _positionSub = null;
    _durationSub = null;

    unawaited(positionSub?.cancel());
    unawaited(durationSub?.cancel());

    if (player != null) {
      unawaited(_releasePlayer(player, recycled));
    }

    _progressValue.dispose();
    _hasDuration.dispose();

    super.dispose();
  }
}
