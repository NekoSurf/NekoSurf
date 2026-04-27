import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/pages/thread/thread_video_player_page.dart';
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
    this.showMuteButton = true,
    this.positionNotifier,
  }) : super(key: key);

  final String playerKey;
  final String videoUrl;
  final String thumbnailUrl;
  final double aspectRatio;
  final double playWhenVisibleFraction;
  final double pauseWhenVisibleFraction;
  final bool showMuteButton;
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
  StreamSubscription<int?>? _widthSub;
  StreamSubscription<int?>? _heightSub;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<String>? _errorSub;

  bool _isVisibleEnough = false;
  bool _hasRenderableSize = false;
  bool _isInitialized = false;
  bool _isMuted = true;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _hasFatalError = false;
  bool _hasFirstFrame = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  int _videoWidth = 0;
  int _videoHeight = 0;
  int _reopenAttempts = 0;

  Timer? _playRetryTimer;
  Timer? _recoveryTimer;
  Timer? _pauseDebounceTimer;
  Timer? _stallWatchdogTimer;
  Timer? _visibilityRecheckTimer;
  int _playRetryAttempts = 0;
  int _visibilityRecheckAttempts = 0;

  Duration _lastObservedPosition = Duration.zero;
  DateTime _lastProgressAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastPositionUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  int _stallRecoveries = 0;
  String? _resolvedVideoSource;

  // ---------------------------------------------------------------------------
  // Audio mode
  // ---------------------------------------------------------------------------

  /// Fixes media-kit issue #964: on iOS, calling AudioTrack.no() triggers an
  /// AVAudioSession re-configuration inside libmpv which momentarily halts
  /// decoding even after play() has been called.  Muting is therefore done
  /// purely via setVolume(0); AudioTrack.auto() is only applied when the user
  /// explicitly unmutes.
  Future<void> _applyAudioMode(Player player) async {
    try {
      if (Platform.isIOS && !_isMuted) {
        await player.setAudioTrack(AudioTrack.auto());
      }
      await player.setVolume(_isMuted ? 0 : 100);
    } catch (_) {
      // Ignore transient track/volume races.
    }
  }

  // ---------------------------------------------------------------------------
  // Stream subscriptions
  // ---------------------------------------------------------------------------

  void _cancelSubscriptions() {
    _playingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _widthSub?.cancel();
    _heightSub?.cancel();
    _bufferingSub?.cancel();
    _errorSub?.cancel();
    _playingSub = null;
    _positionSub = null;
    _durationSub = null;
    _widthSub = null;
    _heightSub = null;
    _bufferingSub = null;
    _errorSub = null;
  }

  void _attachSubscriptions(Player player) {
    _cancelSubscriptions();

    _playingSub = player.stream.playing.listen((playing) {
      if (!mounted) return;
      setState(() {
        _isPlaying = playing;
        if (playing) {
          _hasFirstFrame = true;
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

    _widthSub = player.stream.width.listen((value) {
      _videoWidth = value ?? 0;
      if (mounted && !_hasFirstFrame && _videoWidth > 0 && _videoHeight > 0) {
        setState(() {
          _hasFirstFrame = true;
          _reopenAttempts = 0;
        });
      }
    });

    _heightSub = player.stream.height.listen((value) {
      _videoHeight = value ?? 0;
      if (mounted && !_hasFirstFrame && _videoWidth > 0 && _videoHeight > 0) {
        setState(() {
          _hasFirstFrame = true;
          _reopenAttempts = 0;
        });
      }
    });

    _bufferingSub = player.stream.buffering.listen((value) {
      if (!mounted) return;
      setState(() {
        _isBuffering = value;
      });
    });

    _durationSub = player.stream.duration.listen((value) {
      if (!mounted) return;
      setState(() {
        _duration = value;
      });
    });

    _errorSub = player.stream.error.listen((message) {
      if (!mounted) return;
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
    _visibilityRecheckTimer?.cancel();
    _cancelSubscriptions();

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
    _position = Duration.zero;
    _duration = Duration.zero;
    _videoWidth = 0;
    _videoHeight = 0;
    _reopenAttempts = 0;
    _stallRecoveries = 0;
    _playRetryAttempts = 0;
    _lastObservedPosition = Duration.zero;
    _lastProgressAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastPositionUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);
    _visibilityRecheckAttempts = 0;
    _resolvedVideoSource = null;

    if (!mounted) return;

    if (_isVisibleEnough && _hasRenderableSize) {
      await _ensureInitialized();
      await _playIfNeeded();
    } else {
      setState(() {});
    }
  }

  Future<void> _ensureInitialized() async {
    if (_isInitialized || _player != null) return;

    // Snapshot key + URL so we can detect a source change that happens while
    // the two awaits below are in flight.
    final snapshotKey = widget.playerKey;
    final snapshotUrl = widget.videoUrl;

    final resolvedSource = await resolveCachedVideoSource(snapshotUrl);
    if (!mounted) return;

    // Bail if the widget's source changed while we were resolving.
    if (widget.playerKey != snapshotKey || widget.videoUrl != snapshotUrl) {
      return;
    }

    final slot = await FeedPlayerPool.instance.acquire(
      snapshotKey,
      resolvedSource,
    );

    if (!mounted) {
      // Widget disposed while waiting for pool; release any claim we made.
      FeedPlayerPool.instance.release(snapshotKey);
      return;
    }

    // Bail again if the source changed during pool.acquire().
    if (widget.playerKey != snapshotKey || widget.videoUrl != snapshotUrl) {
      FeedPlayerPool.instance.release(snapshotKey);
      return;
    }

    if (slot == null) {
      // Pool exhausted; retry — slots are typically freed within milliseconds.
      _schedulePlayRetry();
      return;
    }

    _player = slot.player;
    _videoController = slot.controller;
    _acquiredPlayerKey = snapshotKey;
    _resolvedVideoSource = resolvedSource;

    // Open the media on the acquired player if it isn't already loaded.
    // This used to happen inside pool.acquire(), but moving it here prevents
    // the iOS AVAudioSession reconfiguration triggered by open() from
    // interrupting the other already-playing pool players (media-kit #964).
    if (!FeedPlayerPool.instance.isMediaLoaded(snapshotKey, resolvedSource)) {
      try {
        await _player!.open(Media(resolvedSource), play: false);
      } catch (_) {
        // Open failed; release the slot so the retry machinery can recover.
        FeedPlayerPool.instance.release(snapshotKey);
        _acquiredPlayerKey = null;
        _player = null;
        _videoController = null;
        _resolvedVideoSource = null;
        _schedulePlayRetry();
        return;
      }
      if (!mounted ||
          widget.playerKey != snapshotKey ||
          widget.videoUrl != snapshotUrl) {
        return;
      }
      FeedPlayerPool.instance.markMediaLoaded(snapshotKey, resolvedSource);
    }

    _attachSubscriptions(slot.player);

    if (!mounted || _player != slot.player) return;

    setState(() {
      _isInitialized = true;
    });
  }

  Future<void> _playIfNeeded() async {
    final player = _player;
    if (!_isVisibleEnough || !mounted) return;
    if (_hasFatalError) return;

    if (player == null || !_isInitialized) {
      _schedulePlayRetry();
      return;
    }

    try {
      // _applyAudioMode is called exactly once, immediately before play().
      // The 90 ms delayed re-call that existed previously was itself the
      // stutter trigger on iOS (media-kit #964).
      await _applyAudioMode(player);
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
    if (player == null) return;

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
    _position = Duration.zero;
    _duration = Duration.zero;
    _videoWidth = 0;
    _videoHeight = 0;
    _reopenAttempts = 0;
    _stallRecoveries = 0;
    _playRetryAttempts = 0;
    _lastObservedPosition = Duration.zero;
    _lastProgressAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastPositionUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);
    _resolvedVideoSource = null;

    if (mounted) setState(() {});
  }

  void _startPlaybackPipeline() {
    _ensureInitialized().then((_) {
      _playIfNeeded();
      _scheduleRecoveryCheck();
    });
  }

  void _scheduleVisibilityRecheck() {
    _visibilityRecheckTimer?.cancel();

    if (!mounted || !_isVisibleEnough || _visibilityRecheckAttempts >= 8) {
      return;
    }

    _visibilityRecheckAttempts += 1;
    _visibilityRecheckTimer = Timer(const Duration(milliseconds: 50), () {
      if (!mounted || !_isVisibleEnough) {
        return;
      }

      final renderObject = context.findRenderObject();
      final hasStableSize =
          renderObject is RenderBox &&
          renderObject.hasSize &&
          renderObject.size.width > 1 &&
          renderObject.size.height > 1;

      if (hasStableSize) {
        _hasRenderableSize = true;
        _visibilityRecheckAttempts = 0;
        _startPlaybackPipeline();
      } else {
        _scheduleVisibilityRecheck();
      }
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
    _videoWidth = 0;
    _videoHeight = 0;

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

    if (!mounted || !_isVisibleEnough || _playRetryAttempts >= 18) {
      return;
    }

    _playRetryAttempts += 1;
    // Use 200 ms to give pool slots time to be freed after fast-scroll.
    _playRetryTimer = Timer(const Duration(milliseconds: 200), () {
      if (_player == null) {
        // Pool was exhausted; retry the full acquire.
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

  Future<void> _toggleMuted() async {
    final player = _player;

    setState(() {
      _isMuted = !_isMuted;
    });

    if (player == null) {
      return;
    }

    await _applyAudioMode(player);
  }

  @override
  void dispose() {
    _cancelPlayRetry();
    _pauseDebounceTimer?.cancel();
    _visibilityRecheckTimer?.cancel();
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
        final hasSize = info.size.width > 1 && info.size.height > 1;
        _hasRenderableSize = hasSize;

        if (!hasSize) {
          // During fast scroll/layout churn, some callbacks report 0x0 briefly.
          // Ignore those to avoid pausing all currently visible videos.
          return;
        }

        final visible = info.visibleFraction >= widget.playWhenVisibleFraction;
        final hiddenThreshold = widget.pauseWhenVisibleFraction <= 0
            ? 0.0001
            : widget.pauseWhenVisibleFraction;
        final hidden = info.visibleFraction <= hiddenThreshold;

        if (hidden && _isVisibleEnough) {
          _isVisibleEnough = false;
          _visibilityRecheckAttempts = 0;
          _visibilityRecheckTimer?.cancel();
          _pauseDebounceTimer?.cancel();
          _pauseDebounceTimer = Timer(const Duration(milliseconds: 420), () {
            if (!mounted || _isVisibleEnough) return;
            _pause().then((_) {
              if (!mounted || _isVisibleEnough) return;
              _releasePoolSlot();
            });
          });
          return;
        }

        if (visible && _hasRenderableSize) {
          _pauseDebounceTimer?.cancel();
          _isVisibleEnough = true;
          _visibilityRecheckAttempts = 0;
          _visibilityRecheckTimer?.cancel();
          _startPlaybackPipeline();
          return;
        }

        if (visible) {
          _pauseDebounceTimer?.cancel();
          _isVisibleEnough = true;
          _scheduleVisibilityRecheck();
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
              if (!_isPlaying)
                Container(
                  color: Colors.black.withValues(alpha: 0.08),
                  child: Center(
                    child: _isBuffering
                        ? const CupertinoActivityIndicator(radius: 14)
                        : const Icon(
                            CupertinoIcons.play_circle_fill,
                            size: 46,
                            color: Colors.white,
                          ),
                  ),
                ),
              if (widget.showMuteButton && _videoController != null)
                Positioned(
                  top: 10,
                  left: 10,
                  child: CupertinoButton(
                    minimumSize: const Size(30, 30),
                    padding: const EdgeInsets.all(6),
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(999),
                    onPressed: _toggleMuted,
                    child: Icon(
                      _isMuted
                          ? CupertinoIcons.speaker_slash_fill
                          : CupertinoIcons.speaker_2_fill,
                      color: Colors.white,
                      size: 15,
                    ),
                  ),
                ),
              if (_videoController != null)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: CupertinoButton(
                    minimumSize: const Size(28, 28),
                    padding: const EdgeInsets.all(5),
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(999),
                    onPressed: () async {
                      await FeedPlayerPool.instance.pauseAll();
                      if (!context.mounted) return;
                      Navigator.of(context).push(
                        CupertinoPageRoute<void>(
                          builder: (_) => ThreadVideoPlayerPage(
                            videoUrl: widget.videoUrl,
                            startPosition: _position,
                          ),
                        ),
                      );
                    },
                    child: const Icon(
                      Icons.fullscreen,
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
                        ? (_position.inMicroseconds /
                                _duration.inMicroseconds)
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
