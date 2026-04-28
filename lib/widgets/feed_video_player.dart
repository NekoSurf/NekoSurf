import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/services/cached_video.dart';
import 'package:flutter_chan/services/feed_player_pool.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:visibility_detector/visibility_detector.dart';

class FeedVideoPlayer extends StatefulWidget {
  const FeedVideoPlayer({
    Key? key,
    required this.playerKey,
    required this.videoUrl,
    required this.thumbnailUrl,
    required this.aspectRatio,
    this.playWhenVisibleFraction = 0.05,
    this.pauseWhenVisibleFraction = 0.0,
    this.positionNotifier,
  }) : super(key: key);

  final String playerKey;
  final String videoUrl;
  final String thumbnailUrl;
  final double aspectRatio;
  final double playWhenVisibleFraction;
  final double pauseWhenVisibleFraction;
  final ValueNotifier<Duration>? positionNotifier;

  @override
  State<FeedVideoPlayer> createState() => _FeedVideoPlayerState();
}

class _FeedVideoPlayerState extends State<FeedVideoPlayer> {
  Player? _player;
  VideoController? _videoController;
  // Tracks the playerKey under which the current pool slot was acquired so
  // that release() is always called with the correct key even when
  // didUpdateWidget changes widget.playerKey before the slot is released.
  String? _acquiredPlayerKey;

  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<String>? _errorSub;

  bool _isVisibleEnough = false;
  bool _hasRenderableSize = false;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _hasFatalError = false;
  bool _hasFirstFrame = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  int _reopenAttempts = 0;

  Timer? _playRetryTimer;
  Timer? _recoveryTimer;
  Timer? _pauseDebounceTimer;
  Timer? _stallWatchdogTimer;
  bool _isInitializing = false;
  int _playRetryAttempts = 0;

  bool _isMuted = true;

  Duration _lastObservedPosition = Duration.zero;
  DateTime _lastProgressAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastPositionUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  int _stallRecoveries = 0;
  String? _resolvedVideoSource;
  Future<String>? _resolvedSourceFuture;
  String? _resolvedSourceFutureUrl;

  // ---------------------------------------------------------------------------
  // Stream subscriptions
  // ---------------------------------------------------------------------------

  void _cancelSubscriptions() {
    _playingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferingSub?.cancel();
    _errorSub?.cancel();
    _playingSub = null;
    _positionSub = null;
    _durationSub = null;
    _bufferingSub = null;
    _errorSub = null;
  }

  void _attachSubscriptions(Player player) {
    _cancelSubscriptions();

    _playingSub = player.stream.playing.listen((playing) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPlaying = playing;
        if (playing) {
          _reopenAttempts = 0;
        }
      });

      if (playing) {
        _startStallWatchdog();
      }

      if (!playing && _isVisibleEnough && !_hasFirstFrame) {
        _scheduleRecoveryCheck();
      }
    });

    _positionSub = player.stream.position.listen((value) {
      _position = value;
      widget.positionNotifier?.value = value;
      if (value > _lastObservedPosition) {
        _lastObservedPosition = value;
        _lastProgressAt = DateTime.now();
        _stallRecoveries = 0;
      }
      if (value > const Duration(milliseconds: 50) &&
          mounted &&
          !_hasFirstFrame) {
        setState(() {
          _hasFirstFrame = true;
          _reopenAttempts = 0;
        });
        return;
      }
      // Throttle progress-bar redraws to ~4 fps to avoid per-frame rebuilds.
      if (mounted && _hasFirstFrame) {
        final now = DateTime.now();
        if (now.difference(_lastPositionUiUpdate).inMilliseconds >= 250) {
          _lastPositionUiUpdate = now;
          setState(() {});
        }
      }
    });

    _bufferingSub = player.stream.buffering.listen((value) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isBuffering = value;
      });
    });

    _durationSub = player.stream.duration.listen((value) {
      if (!mounted) {
        return;
      }
      setState(() {
        _duration = value;
      });
    });

    _errorSub = player.stream.error.listen((message) {
      if (!mounted) {
        return;
      }
      // These errors are usually unrecoverable for this source instance.
      if (message.contains('moov atom not found') ||
          message.contains('Invalid data found when processing input') ||
          message.contains('failed')) {
        setState(() {
          _hasFatalError = true;
        });
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant FeedVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.videoUrl != widget.videoUrl ||
        oldWidget.playerKey != widget.playerKey) {
      _resetForNewSource(oldKey: oldWidget.playerKey);
    }
  }

  Future<void> _resetForNewSource({String? oldKey}) async {
    _cancelPlayRetry();
    _recoveryTimer?.cancel();
    _pauseDebounceTimer?.cancel();
    _stallWatchdogTimer?.cancel();
    _cancelSubscriptions();
    _isInitializing = false;

    // Release the old pool slot using whichever key actually acquired it.
    final keyToRelease = oldKey ?? _acquiredPlayerKey;
    if (keyToRelease != null) {
      FeedPlayerPool.instance.release(keyToRelease);
    }
    _acquiredPlayerKey = null;
    _player = null;
    _videoController = null;

    _isInitialized = false;
    _isPlaying = false;
    _isBuffering = false;
    _hasFatalError = false;
    _hasFirstFrame = false;
    _isMuted = true;
    _position = Duration.zero;
    _duration = Duration.zero;
    _reopenAttempts = 0;
    _stallRecoveries = 0;
    _playRetryAttempts = 0;
    _lastObservedPosition = Duration.zero;
    _lastProgressAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastPositionUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);
    _resolvedVideoSource = null;
    _resolvedSourceFuture = null;
    _resolvedSourceFutureUrl = null;

    if (!mounted) {
      return;
    }

    if (_isVisibleEnough && _hasRenderableSize) {
      await _ensureInitialized();
      await _playIfNeeded();
    } else {
      setState(() {});
    }
  }

  Future<void> _ensureInitialized() async {
    // Guard against concurrent initializations.
    if (_isInitialized || _player != null || _isInitializing) {
      return;
    }
    _isInitializing = true;

    // Snapshot key + URL so we can detect a source change that happens while
    // the two awaits below are in flight.
    final snapshotKey = widget.playerKey;
    final snapshotUrl = widget.videoUrl;

    String resolvedSource;
    try {
      resolvedSource = await _resolveSourceFor(snapshotUrl);
    } catch (_) {
      _isInitializing = false;
      _schedulePlayRetry();
      return;
    }
    if (!mounted) {
      _isInitializing = false;
      return;
    }

    // Bail if the widget's source changed while we were resolving.
    if (widget.playerKey != snapshotKey || widget.videoUrl != snapshotUrl) {
      _isInitializing = false;
      return;
    }

    final slot = await FeedPlayerPool.instance.acquire(
      snapshotKey,
      resolvedSource,
    );

    if (!mounted) {
      // Widget disposed while waiting for pool; release any claim we made.
      FeedPlayerPool.instance.release(snapshotKey);
      _isInitializing = false;
      return;
    }

    // Bail again if the source changed during pool.acquire().
    if (widget.playerKey != snapshotKey || widget.videoUrl != snapshotUrl) {
      FeedPlayerPool.instance.release(snapshotKey);
      _isInitializing = false;
      return;
    }

    if (slot == null) {
      // Pool exhausted; retry — slots are typically freed within milliseconds.
      _isInitializing = false;
      _schedulePlayRetry();
      return;
    }

    final player = slot.player;
    // A reused player can retain a stale last frame from previous media.
    // Hide the video surface until fresh frame progress is observed.
    final hadFirstFrame = _hasFirstFrame;
    _hasFirstFrame = false;
    _isPlaying = false;
    _position = Duration.zero;
    if (hadFirstFrame && mounted) {
      setState(() {});
    }

    _player = player;
    _videoController = slot.controller;
    _acquiredPlayerKey = snapshotKey;
    _resolvedVideoSource = resolvedSource;

    // Open the media on the acquired player if it isn't already loaded.
    // This used to happen inside pool.acquire(), but moving it here prevents
    // the iOS AVAudioSession reconfiguration triggered by open() from
    // interrupting the other already-playing pool players (media-kit #964).
    if (!FeedPlayerPool.instance.isMediaLoaded(snapshotKey, resolvedSource)) {
      try {
        await player.open(Media(resolvedSource), play: false);
      } catch (_) {
        // Open failed; release the slot so the retry machinery can recover.
        FeedPlayerPool.instance.release(snapshotKey);
        _acquiredPlayerKey = null;
        _player = null;
        _videoController = null;
        _resolvedVideoSource = null;
        _isInitializing = false;
        _schedulePlayRetry();
        return;
      }
      if (!mounted ||
          _player != player ||
          _acquiredPlayerKey != snapshotKey ||
          widget.playerKey != snapshotKey ||
          widget.videoUrl != snapshotUrl) {
        _isInitializing = false;
        return;
      }
      FeedPlayerPool.instance.markMediaLoaded(snapshotKey, resolvedSource);
    }

    // Start inline feed videos with audio disabled to reduce AVAudioSession
    // churn during initialization/open on iOS (media-kit #964).
    try {
      await player.setAudioTrack(AudioTrack.no());
    } catch (_) {}

    if (!mounted || _player != player || _acquiredPlayerKey != snapshotKey) {
      _isInitializing = false;
      return;
    }

    _attachSubscriptions(player);

    if (!mounted || _player != player) {
      _isInitializing = false;
      return;
    }

    _isInitializing = false;
    setState(() {
      _isInitialized = true;
    });
  }

  void _primeResolvedSource() {
    final url = widget.videoUrl;
    if (_resolvedSourceFuture != null && _resolvedSourceFutureUrl == url) {
      return;
    }

    _resolvedSourceFutureUrl = url;
    _resolvedSourceFuture = _resolveAndCacheSource(url);
  }

  Future<String> _resolveSourceFor(String url) {
    if (_resolvedSourceFuture != null && _resolvedSourceFutureUrl == url) {
      return _resolvedSourceFuture!;
    }

    _resolvedSourceFutureUrl = url;
    _resolvedSourceFuture = _resolveAndCacheSource(url);
    return _resolvedSourceFuture!;
  }

  Future<String> _resolveAndCacheSource(String url) async {
    try {
      return await resolveCachedVideoSource(url);
    } catch (_) {
      _resolvedSourceFuture = null;
      _resolvedSourceFutureUrl = null;
      rethrow;
    }
  }

  Future<void> _playIfNeeded() async {
    final player = _player;
    if (!_isVisibleEnough || !mounted) {
      return;
    }
    if (_hasFatalError) {
      return;
    }

    if (player == null || !_isInitialized) {
      _schedulePlayRetry();
      return;
    }

    try {
      await player.play();
      _startStallWatchdog();
      _cancelPlayRetry();
      _playRetryAttempts = 0;
    } catch (_) {
      _schedulePlayRetry();
    }
  }

  Future<void> _pause() async {
    final player = _player;
    if (player == null) {
      return;
    }

    try {
      await player.pause();
    } catch (_) {
      // Ignore pause races.
    }

    _stallWatchdogTimer?.cancel();
  }

  /// Releases the pool slot and clears playback state after the widget has
  /// scrolled off-screen.  Called from the pause-debounce timer.
  void _releasePoolSlot() {
    _cancelPlayRetry();
    _recoveryTimer?.cancel();
    _stallWatchdogTimer?.cancel();
    _cancelSubscriptions();
    _isInitializing = false;

    if (_acquiredPlayerKey != null) {
      FeedPlayerPool.instance.release(_acquiredPlayerKey!);
      _acquiredPlayerKey = null;
    }

    _player = null;
    _videoController = null;
    _isInitialized = false;
    _isPlaying = false;
    _isBuffering = false;
    _hasFirstFrame = false;
    _isMuted = true;
    _position = Duration.zero;
    _duration = Duration.zero;
    _reopenAttempts = 0;
    _stallRecoveries = 0;
    _playRetryAttempts = 0;
    _lastObservedPosition = Duration.zero;
    _lastProgressAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastPositionUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);
    _resolvedVideoSource = null;

    if (mounted) {
      setState(() {});
    }
  }

  void _startPlaybackPipeline() {
    _ensureInitialized().then((_) {
      _playIfNeeded();
      _scheduleRecoveryCheck();
    });
  }

  Future<void> _recoverFromStall() async {
    final player = _player;
    if (player == null || !mounted || !_isVisibleEnough || _hasFatalError) {
      return;
    }

    // First attempt: lightweight playback nudge.
    if (_stallRecoveries == 0) {
      _stallRecoveries = 1;
      try {
        final target = _position + const Duration(milliseconds: 1);
        await player.seek(target);
        await player.play();
      } catch (_) {
        // Ignore and escalate on next watchdog tick.
      }
      return;
    }

    // Second attempt: reopen the media on the same pool player.
    if (_stallRecoveries == 1) {
      _stallRecoveries = 2;
      await _reopenAndPlay();
    }
  }

  void _startStallWatchdog() {
    _stallWatchdogTimer?.cancel();

    _lastObservedPosition = _position;
    _lastProgressAt = DateTime.now();

    _stallWatchdogTimer = Timer.periodic(const Duration(milliseconds: 800), (
      _,
    ) {
      if (!mounted || !_isVisibleEnough || !_isInitialized || _hasFatalError) {
        return;
      }

      if (!_isPlaying || _isBuffering) {
        return;
      }

      final stalledFor = DateTime.now().difference(_lastProgressAt);
      if (stalledFor > const Duration(milliseconds: 1600)) {
        _recoverFromStall();
      }
    });
  }

  Future<void> _reopenAndPlay() async {
    final player = _player;
    if (player == null || !mounted) {
      return;
    }

    _isPlaying = false;
    _hasFirstFrame = false;
    _position = Duration.zero;

    try {
      final resolvedSource =
          _resolvedVideoSource ??
          await resolveCachedVideoSource(widget.videoUrl);
      if (!mounted) {
        return;
      }
      _resolvedVideoSource = resolvedSource;
      await player.pause();
      await player.open(Media(resolvedSource), play: false);
    } catch (_) {
      // Ignore transient reopen races.
    }

    if (!mounted || !_isVisibleEnough) {
      return;
    }

    _isInitialized = true;
    await _playIfNeeded();
  }

  void _schedulePlayRetry() {
    _playRetryTimer?.cancel();

    if (!mounted || !_isVisibleEnough || _playRetryAttempts >= 30) {
      return;
    }

    _playRetryAttempts += 1;
    _playRetryTimer = Timer(const Duration(milliseconds: 150), () {
      if (!mounted || !_isVisibleEnough) {
        return;
      }
      if (_player == null) {
        _startPlaybackPipeline();
      } else {
        _playIfNeeded();
      }
    });
  }

  void _cancelPlayRetry() {
    _playRetryTimer?.cancel();
    _playRetryTimer = null;
  }

  void _scheduleRecoveryCheck() {
    _recoveryTimer?.cancel();

    if (!mounted || !_isVisibleEnough || _hasFirstFrame || _hasFatalError) {
      return;
    }

    _recoveryTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted || !_isVisibleEnough || !_isInitialized) {
        return;
      }

      if (_isBuffering) {
        _scheduleRecoveryCheck();
        return;
      }

      if (!_isPlaying &&
          !_hasFirstFrame &&
          _position <= const Duration(milliseconds: 50)) {
        // A single reopen attempt can recover a bad initial texture attach.
        if (_reopenAttempts < 1) {
          _reopenAttempts += 1;
          _reopenAndPlay();
        } else {
          _playIfNeeded();
        }
      } else if (!_isPlaying) {
        _playIfNeeded();
      }
    });
  }

  @override
  void dispose() {
    _cancelPlayRetry();
    _pauseDebounceTimer?.cancel();
    _recoveryTimer?.cancel();
    _stallWatchdogTimer?.cancel();
    _cancelSubscriptions();

    if (_acquiredPlayerKey != null) {
      FeedPlayerPool.instance.release(_acquiredPlayerKey!);
      _acquiredPlayerKey = null;
    }

    _player = null;
    _videoController = null;

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: ValueKey('feed-video-${widget.playerKey}'),
      onVisibilityChanged: (info) {
        // Ignore 0x0 callbacks that arrive during layout churn.
        final hasSize = info.size.width > 1 && info.size.height > 1;
        if (!hasSize) {
          return;
        }
        _hasRenderableSize = true;

        final fraction = info.visibleFraction;
        final playThreshold = widget.playWhenVisibleFraction;
        final prewarmThreshold = playThreshold > 0 ? playThreshold * 0.5 : 0.01;
        // Pause only when truly off-screen (fraction == 0) unless the caller
        // explicitly set a non-zero pause threshold.
        final pauseThreshold = widget.pauseWhenVisibleFraction > 0
            ? widget.pauseWhenVisibleFraction
            : 0.0;

        // Start resolving slightly before playback so open() has less work
        // left once the item crosses the play threshold.
        if (fraction >= 0.01) {
          _primeResolvedSource();
        }

        // Start acquiring/opening slightly before the play threshold so
        // playback can begin faster once the item is sufficiently visible.
        if (fraction >= prewarmThreshold &&
            !_isInitialized &&
            !_isInitializing) {
          _primeResolvedSource();
          _ensureInitialized();
        }

        if (fraction >= playThreshold && !_isVisibleEnough) {
          // Widget has entered view — start playback.
          _isVisibleEnough = true;
          _playRetryAttempts = 0; // fresh entry always gets full retry budget
          _pauseDebounceTimer?.cancel();
          _startPlaybackPipeline();
        } else if (fraction <= pauseThreshold && _isVisibleEnough) {
          // Widget has left view — pause then release.
          _isVisibleEnough = false;
          _pauseDebounceTimer?.cancel();
          _pauseDebounceTimer = Timer(const Duration(milliseconds: 300), () {
            if (!mounted || _isVisibleEnough) {
              return;
            }
            _pause().then((_) {
              if (!mounted || _isVisibleEnough) {
                return;
              }
              _releasePoolSlot();
            });
          });
        }
      },
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(widget.thumbnailUrl, fit: BoxFit.cover),
              if (_videoController != null)
                AnimatedOpacity(
                  opacity: _hasFirstFrame ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  child: Video(
                    controller: _videoController!,
                    fit: BoxFit.cover,
                    controls: NoVideoControls,
                  ),
                ),
              // Show spinner while loading (visible but no frame yet, or
              // mid-playback buffer stall). Show play icon only when truly
              // idle/paused and not in the middle of loading.
              if (!_isPlaying || (_isPlaying && _isBuffering))
                Container(
                  color: Colors.black.withValues(alpha: 0.08),
                  child: Center(
                    child:
                        (_isVisibleEnough &&
                            !_hasFatalError &&
                            (_isInitializing ||
                                (_isInitialized && !_hasFirstFrame) ||
                                _isBuffering))
                        ? const CupertinoActivityIndicator(radius: 14)
                        : const Icon(
                            CupertinoIcons.play_circle_fill,
                            size: 46,
                            color: Colors.white,
                          ),
                  ),
                ),
              if (_videoController != null)
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: CupertinoButton(
                    minimumSize: const Size(28, 28),
                    padding: const EdgeInsets.all(5),
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(999),
                    onPressed: () async {
                      final player = _player;
                      if (player == null) {
                        return;
                      }

                      final nextMuted = !_isMuted;
                      try {
                        if (nextMuted) {
                          await player.setAudioTrack(AudioTrack.no());
                        } else {
                          await player.setAudioTrack(AudioTrack.auto());
                        }
                        if (!mounted) {
                          return;
                        }
                        setState(() {
                          _isMuted = nextMuted;
                        });
                      } catch (_) {
                        // Ignore toggle failures.
                      }
                    },
                    child: Icon(
                      _isMuted ? Icons.volume_off : Icons.volume_up,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              if (_isPlaying && _hasFirstFrame && _duration > Duration.zero)
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
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.white,
                    ),
                    minHeight: 3,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
