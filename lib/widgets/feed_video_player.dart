import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/widgets/feed_player_recycler.dart';
import 'package:flutter_chan/widgets/video_scrub_gesture.dart';
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
    this.startMuted = true,
    this.isOnScreen = true,
    this.recycler,
    this.onTap,
  });

  final String videoUrl;
  final String thumbnailUrl;
  final double aspectRatio;
  final bool preload;
  final bool startMuted;

  /// Set to false by the feed once the item has scrolled out of the viewport.
  /// Visibility callbacks can be missed when an item stops being painted
  /// between frames, so this forces the video to pause.
  final bool isOnScreen;
  final FeedPlayerRecycler? recycler;

  /// Receives the live player (if loaded) to show fullscreen; it is reclaimed
  /// when the returned future completes.
  final Future<void> Function(RecycledPlayer? handoff)? onTap;

  @override
  State<FeedVideoPlayer> createState() => _FeedVideoPlayerState();
}

class _FeedVideoPlayerState extends State<FeedVideoPlayer> {
  static const double _playVisibilityThreshold = 0.02;
  static const double _pauseVisibilityThreshold = 0.01;
  static const Duration _pauseDebounce = Duration(milliseconds: 550);
  // Longer than VisibilityDetector's update interval so it can report first.
  static const Duration _reclaimVisibilityGrace = Duration(milliseconds: 1200);

  Player? _player;
  VideoController? _controller;
  RecycledPlayer? _recycled;
  bool _isDisposing = false;
  bool _isLentOut = false;
  double _visibleFraction = 0;
  bool _tickerEnabled = true;
  bool _appInForeground = true;
  AppLifecycleListener? _lifecycleListener;
  int _opToken = 0;

  bool _visible = false;
  bool _initialized = false;
  bool _hasFirstFrame = false;
  late bool _isMuted;

  final ValueNotifier<double> _progressValue = ValueNotifier<double>(0.0);
  final ValueNotifier<bool> _hasDuration = ValueNotifier<bool>(false);
  Duration _lastProgressUiPosition = Duration.zero;
  int _durationMicros = 0;
  bool _isScrubbing = false;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  Timer? _pauseDebounceTimer;
  Timer? _reclaimVisibilityTimer;

  @override
  void initState() {
    super.initState();

    _isMuted = widget.startMuted;
    _lifecycleListener = AppLifecycleListener(
      onStateChange: (AppLifecycleState state) {
        final bool inForeground =
            state == AppLifecycleState.resumed ||
            state == AppLifecycleState.inactive;
        if (inForeground == _appInForeground) {
          return;
        }
        _appInForeground = inForeground;
        _updateVisibility();
      },
    );

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
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Routes covered by an opaque route stop painting, so VisibilityDetector
    // never reports them as hidden; the Overlay disables their TickerMode.
    final bool tickerEnabled = TickerMode.of(context);
    if (tickerEnabled == _tickerEnabled) {
      return;
    }
    _tickerEnabled = tickerEnabled;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateVisibility();
      }
    });
  }

  @override
  void didUpdateWidget(covariant FeedVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.startMuted != widget.startMuted) {
      _isMuted = widget.startMuted;
      final player = _player;
      if (player != null && !_isLentOut) {
        unawaited(
          player
              .setAudioTrack(_isMuted ? AudioTrack.no() : AudioTrack.auto())
              .catchError((_) {}),
        );
      }
    }

    if (_isLentOut) {
      return;
    }

    if (oldWidget.isOnScreen != widget.isOnScreen) {
      _updateVisibility();
    }

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

      await player.setAudioTrack(
        _isMuted ? AudioTrack.no() : AudioTrack.auto(),
      );
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
        if (durationMicros <= 0 || _isScrubbing) {
          return;
        }

        final shouldUpdateUi =
            pos == Duration.zero ||
            (pos - _lastProgressUiPosition).inMilliseconds.abs() >= 100;
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

        _applyDuration(dur);
      });
      // The stream only emits changes, which may have fired during open().
      _applyDuration(player.state.duration);

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

  void _applyDuration(Duration duration) {
    final micros = duration.inMicroseconds;
    _durationMicros = micros;
    final hasDurationNow = micros > 0;
    if (_hasDuration.value != hasDurationNow) {
      _hasDuration.value = hasDurationNow;
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
  // Fullscreen handoff
  // ---------------------------

  void _handleScrubPreview(Duration? preview) {
    _isScrubbing = preview != null;
    final durationMicros = _durationMicros;
    if (preview == null || durationMicros <= 0) {
      return;
    }

    _lastProgressUiPosition = preview;
    _progressValue.value = (preview.inMicroseconds / durationMicros).clamp(
      0.0,
      1.0,
    );
  }

  Future<void> _handleTap() async {
    final onTap = widget.onTap;
    if (onTap == null || _isLentOut) {
      return;
    }

    final player = _player;
    final controller = _controller;
    if (player == null || controller == null || !_initialized) {
      await onTap(null);
      return;
    }

    final recycler = widget.recycler;
    final recycled = _recycled;
    final handoff = recycled ?? RecycledPlayer(player, controller);

    _isLentOut = true;
    _pauseDebounceTimer?.cancel();
    _pauseDebounceTimer = null;
    _reclaimVisibilityTimer?.cancel();

    try {
      await onTap(handoff);
    } finally {
      _isLentOut = false;
      if (mounted && !_isDisposing && _player == player) {
        unawaited(_reclaim(player));
      } else if (recycled != null && recycler != null) {
        // dispose() ran while lent out and left the player to us.
        unawaited(recycler.release(recycled));
      } else {
        unawaited(() async {
          try {
            await player.dispose();
          } catch (_) {}
        }());
      }
    }
  }

  Future<void> _reclaim(Player player) async {
    final playlist = player.state.playlist;
    final index = playlist.index;
    final stillOurMedia =
        index >= 0 &&
        index < playlist.medias.length &&
        playlist.medias[index].uri == widget.videoUrl;
    // _visible may be stale: updates are ignored while lent out and the feed
    // may have scrolled to another post when the viewer closed.
    final bool showing =
        _visible && _effectiveVisibleFraction >= _playVisibilityThreshold;

    if (stillOurMedia) {
      try {
        await player.setAudioTrack(
          _isMuted ? AudioTrack.no() : AudioTrack.auto(),
        );
        if (showing && _player == player) {
          await player.play();
        } else {
          await player.pause();
        }
      } catch (_) {}
    } else {
      // The viewer switched to another video; reopen ours.
      await _pauseAndDispose();
      if (mounted && !_isDisposing && showing) {
        unawaited(_initAndPlay());
      }
    }

    _reclaimVisibilityTimer?.cancel();
    _reclaimVisibilityTimer = Timer(_reclaimVisibilityGrace, () {
      if (!mounted || _isDisposing || _isLentOut) {
        return;
      }
      _updateVisibility();
    });
  }

  // ---------------------------
  // Visibility
  // ---------------------------

  void _schedulePauseAndDispose() {
    if (_isLentOut) {
      return;
    }

    // Pause right away; only releasing the player is debounced.
    unawaited(_pauseOnly());

    if (widget.preload) {
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

  double get _effectiveVisibleFraction {
    if (!widget.isOnScreen || !_tickerEnabled || !_appInForeground) {
      return 0;
    }
    return _visibleFraction;
  }

  void _handleVisibility(double fraction) {
    _visibleFraction = fraction;
    _updateVisibility();
  }

  void _updateVisibility() {
    if (_isLentOut || _isDisposing) {
      return;
    }

    final fraction = _effectiveVisibleFraction;
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
    return GestureDetector(
      onTap: widget.onTap == null ? null : _handleTap,
      child: VisibilityDetector(
        key: ValueKey(widget.videoUrl),
        onVisibilityChanged: (info) {
          _handleVisibility(info.visibleFraction);
        },
        child: VideoScrubGesture(
          player: _player,
          onPreviewChanged: _handleScrubPreview,
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return AspectRatio(
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
                          backgroundColor: Colors.white.withValues(alpha: 0.25),
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
    );
  }

  @override
  void dispose() {
    _isDisposing = true;
    ++_opToken;

    _pauseDebounceTimer?.cancel();
    _pauseDebounceTimer = null;
    _reclaimVisibilityTimer?.cancel();
    _lifecycleListener?.dispose();
    _lifecycleListener = null;

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

    // While lent out, _handleTap releases the player once the viewer returns it.
    if (player != null && !_isLentOut) {
      unawaited(_releasePlayer(player, recycled));
    }

    _progressValue.dispose();
    _hasDuration.dispose();

    super.dispose();
  }
}
