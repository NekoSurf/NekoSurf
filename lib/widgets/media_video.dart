import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/services/video_server.dart';
import 'package:flutter_chan/widgets/video_players.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Turns a video's source into what mpv should open, e.g. a file URI.
typedef MediaSourceResolver = Future<String> Function(String source);

/// One video, shared by every place that shows it.
///
/// The inline post and the fullscreen viewer get the same [MediaVideo] for
/// a video ([obtain]), and so the same player: opening it fullscreen
/// continues it where it is, with sound, instead of loading it again.
///
/// Places that show the video say whether they want it playing ([want],
/// [unwant]); it plays while anyone does and the user hasn't paused it. The
/// player comes from [VideoPlayers] (three at most, app-wide) and plays
/// 4chan videos through [VideoServer], which streams them while it caches
/// them. When the player is taken for another video, or the app goes to
/// the background, it continues later where it was.
class MediaVideo extends ChangeNotifier {
  MediaVideo._(this.source, this._resolveSource, this._width, this._height) {
    VideoPlayers.instance.addListener(_sync);
  }

  static final Map<String, MediaVideo> _all = <String, MediaVideo>{};

  /// The shared video for [source]; give it back with [release].
  static MediaVideo obtain(
    String source, {
    MediaSourceResolver? resolveSource,
    int? width,
    int? height,
    bool? muted,
  }) {
    final MediaVideo video = _all.putIfAbsent(source, () {
      return MediaVideo._(source, resolveSource, width, height)
        .._muted = muted ?? true;
    });
    video._refs++;
    return video;
  }

  // mpv reports bogus errors while it tries decoders, so
  // only a missing first frame counts. It may take longer while the video
  // is still arriving; that's checked before giving up.
  static const Duration _firstFrameTimeout = Duration(seconds: 10);
  // Brief gaps in demand (the fullscreen viewer closing before the inline
  // post takes over) shouldn't stutter playback.
  static const Duration _pauseGrace = Duration(milliseconds: 250);
  static const Duration _positionStep = Duration(milliseconds: 50);

  final String source;
  final MediaSourceResolver? _resolveSource;
  final int? _width;
  final int? _height;
  int _refs = 0;

  // Who wants it playing, and whether they want sound.
  final Map<Object, bool> _demands = <Object, bool>{};
  bool _userPaused = false;
  // Without sound unless someone wants it audible (fullscreen) or the user
  // unmutes the inline video.
  bool _muted = true;
  double _rate = 1;
  bool _loop = true;

  VideoLease? _lease;
  int _token = 0;
  bool _starting = false;
  bool _opened = false;
  bool _hasFirstFrame = false;
  bool _failed = false;
  bool _retried = false;
  Duration _resumeAt = Duration.zero;
  bool _resumePlaying = true;
  bool _playing = false;
  bool _buffering = false;
  Duration _duration = Duration.zero;

  final ValueNotifier<Duration> position = ValueNotifier<Duration>(
    Duration.zero,
  );

  /// Where the user is scrubbing to; null when not scrubbing.
  final ValueNotifier<Duration?> scrubPosition = ValueNotifier<Duration?>(null);

  final StreamController<void> _completed = StreamController<void>.broadcast();
  final List<StreamSubscription<Object?>> _subs =
      <StreamSubscription<Object?>>[];
  Timer? _firstFrameTimer;
  Timer? _pauseTimer;
  double? _progressMark;

  bool _scrubbing = false;
  bool _playingBeforeScrub = false;
  Duration? _seekTarget;
  bool _seeking = false;

  VideoController? get controller => _lease?.controller;
  bool get hasFirstFrame => _hasFirstFrame;
  bool get failed => _failed;
  bool get isPlaying => _playing;
  bool get isBuffering => _buffering;

  /// Getting ready to show its first frame. Not while it waits for a free
  /// player: then it just shows the thumbnail.
  bool get isLoading =>
      !_failed &&
      !_hasFirstFrame &&
      _demands.isNotEmpty &&
      (_starting || _lease != null);
  Duration get duration => _duration;
  bool get muted => _muted;
  bool get isRemote => source.startsWith('http');

  /// The video reached its end (only without looping).
  Stream<void> get completed => _completed.stream;

  /// How much of the video has downloaded; only for 4chan videos.
  ValueListenable<double?>? get downloadProgress =>
      isRemote && _resolveSource == null
      ? VideoServer.instance.progressOf(source)
      : null;

  set muted(bool value) {
    _muted = value;
    _applyVolume();
    notifyListeners();
  }

  /// [owner] shows the video and wants it playing, with sound if [audible].
  void want(Object owner, {bool audible = false}) {
    final bool isNew = !_demands.containsKey(owner);
    _demands[owner] = audible;
    if (isNew) {
      _userPaused = false;
    }
    _applyVolume();
    _sync();
  }

  void unwant(Object owner) {
    if (_demands.remove(owner) == null) {
      return;
    }
    _applyVolume();
    _sync();
  }

  /// Downloads the video ahead of time, without a player.
  void prefetch() {
    if (isRemote && _resolveSource == null) {
      unawaited(VideoServer.instance.prefetch(source));
    }
  }

  void setRate(double rate) {
    _rate = rate;
    _lease?.player.setRate(rate).catchError((_) {});
  }

  // mpv's loop-file, which seeks back to the file's start. Looping the
  // playlist reloads the file each time, and every load starts at
  // [Media.start]: a resumed video then looped back to where it resumed.
  PlaylistMode get _playlistMode =>
      _loop ? PlaylistMode.single : PlaylistMode.none;

  void setLoop(bool loop) {
    _loop = loop;
    _lease?.player.setPlaylistMode(_playlistMode).catchError((_) {});
  }

  void togglePlay() {
    final Player? player = _lease?.player;
    if (_playing) {
      _userPaused = true;
      player?.pause().catchError((_) {});
      return;
    }
    _userPaused = false;
    if (player != null && _opened) {
      // A finished video (without looping) starts over.
      if (player.state.completed) {
        player.seek(Duration.zero).catchError((_) {});
      }
      player.play().catchError((_) {});
    } else {
      _sync();
    }
  }

  /// Plays it from the start when it's shown again after finishing.
  void restartIfFinished() {
    final Player? player = _lease?.player;
    if (player != null && player.state.completed) {
      player.seek(Duration.zero).catchError((_) {});
    }
  }

  void release() {
    if (--_refs > 0) {
      return;
    }
    _all.remove(source);
    VideoPlayers.instance.removeListener(_sync);
    _token++;
    _pauseTimer?.cancel();
    _detach();
    _lease?.release();
    _lease = null;
    unawaited(_completed.close());
    position.dispose();
    scrubPosition.dispose();
    dispose();
  }

  // ---------------------------
  // Scrubbing: the picture follows the finger
  // ---------------------------

  void scrubStart() {
    final Player? player = _lease?.player;
    if (player == null || !_opened) {
      return;
    }
    _scrubbing = true;
    _playingBeforeScrub = _playing;
    scrubPosition.value = position.value;
    player.pause().catchError((_) {});
  }

  void scrubTo(Duration target) {
    if (!_scrubbing) {
      return;
    }
    scrubPosition.value = _clamp(target);
    _seekTarget = scrubPosition.value;
    unawaited(_pumpSeeks());
  }

  Future<void> scrubEnd() async {
    if (!_scrubbing) {
      return;
    }
    final Duration? target = scrubPosition.value;
    _seekTarget = target;
    await _pumpSeeks();
    _scrubbing = false;
    if (target != null) {
      position.value = target;
    }
    scrubPosition.value = null;
    if (_playingBeforeScrub && !_userPaused && _demands.isNotEmpty) {
      _lease?.player.play().catchError((_) {});
    }
  }

  /// Seeks to the latest target, one seek at a time, so mpv isn't flooded
  /// but always ends up where the finger is.
  Future<void> _pumpSeeks() async {
    if (_seeking) {
      return;
    }
    _seeking = true;
    try {
      while (_seekTarget != null) {
        final Duration target = _seekTarget!;
        _seekTarget = null;
        try {
          await _lease?.player.seek(target);
        } catch (_) {}
      }
    } finally {
      _seeking = false;
    }
  }

  Duration _clamp(Duration value) {
    if (value < Duration.zero) {
      return Duration.zero;
    }
    if (_duration > Duration.zero && value > _duration) {
      return _duration;
    }
    return value;
  }

  // ---------------------------
  // Player
  // ---------------------------

  void _applyVolume() {
    final bool audible = _demands.values.any((audible) => audible);
    _lease?.player.setVolume(audible || !_muted ? 100 : 0).catchError((_) {});
  }

  /// Brings the player in line with who wants the video. Also runs when
  /// [VideoPlayers] freed a player or the app is back from the background.
  void _sync() {
    final VideoLease? lease = _lease;
    final bool wanted = _demands.isNotEmpty;

    if (!wanted) {
      if (lease != null && lease.wanted && !_pauseTimerActive) {
        _pauseTimer = Timer(_pauseGrace, () {
          if (_demands.isEmpty && _lease == lease) {
            lease.wanted = false;
            lease.player.pause().catchError((_) {});
          }
        });
      }
      return;
    }

    _pauseTimer?.cancel();
    if (lease == null) {
      unawaited(_start());
      return;
    }
    lease.wanted = true;
    if (!_hasFirstFrame && !(_firstFrameTimer?.isActive ?? false)) {
      _armFirstFrameTimer(lease);
    }
    if (_opened && !_userPaused && !_scrubbing && !lease.player.state.playing) {
      lease.player.play().catchError((_) {});
    }
  }

  bool get _pauseTimerActive => _pauseTimer?.isActive ?? false;

  Future<String> _mediaSource() async {
    final MediaSourceResolver? resolve = _resolveSource;
    if (resolve != null) {
      return resolve(source);
    }
    if (isRemote) {
      return VideoServer.instance.source(source);
    }
    return source;
  }

  Future<void> _start() async {
    if (_starting || _failed || _lease != null || _demands.isEmpty) {
      return;
    }
    _starting = true;
    final int token = ++_token;

    try {
      final String media = await _mediaSource();
      if (token != _token || _demands.isEmpty) {
        return;
      }
      // Not before the first await: want() runs during builds.
      notifyListeners();

      final VideoLease? lease = VideoPlayers.instance.acquire(
        onEvicted: _onEvicted,
        width: _width,
        height: _height,
      );
      // Every player is busy; _sync runs again when one is freed.
      if (lease == null) {
        _starting = false;
        notifyListeners();
        return;
      }
      lease.wanted = true;
      _lease = lease;
      _attach(lease, token);
      notifyListeners();

      final Player player = lease.player;
      _applyVolume();
      await player.setRate(_rate);
      await player.setPlaylistMode(_playlistMode);
      // mpv starts there itself: a seek right after open() is dropped while
      // the stream is still loading, which restarted videos from the top.
      await player.open(
        Media(media, start: _resumeAt > Duration.zero ? _resumeAt : null),
        play: false,
      );
      if (token != _token) {
        return;
      }
      _opened = true;
      if (_demands.isNotEmpty && !_userPaused && _resumePlaying) {
        await player.play();
      }
      _resumePlaying = true;
    } catch (_) {
      if (token == _token) {
        _fail();
      }
    } finally {
      if (token == _token) {
        _starting = false;
      }
    }
  }

  void _attach(VideoLease lease, int token) {
    final Player player = lease.player;
    bool current() => token == _token && _lease == lease;

    lease.controller.waitUntilFirstFrameRendered.then((_) {
      if (current()) {
        _firstFrameTimer?.cancel();
        _retried = false;
        _hasFirstFrame = true;
        notifyListeners();
      }
    });
    _armFirstFrameTimer(lease);

    Duration lastPosition = Duration.zero;
    _subs
      ..add(
        player.stream.playing.listen((bool playing) {
          if (current() && playing != _playing) {
            _playing = playing;
            notifyListeners();
          }
        }),
      )
      ..add(
        player.stream.buffering.listen((bool buffering) {
          if (current() && buffering != _buffering) {
            _buffering = buffering;
            notifyListeners();
          }
        }),
      )
      ..add(
        player.stream.duration.listen((Duration duration) {
          if (current() && duration != _duration) {
            _duration = duration;
            notifyListeners();
          }
        }),
      )
      ..add(
        player.stream.position.listen((Duration value) {
          if (!current() || _scrubbing) {
            return;
          }
          if ((value - lastPosition).abs() >= _positionStep ||
              value < lastPosition) {
            lastPosition = value;
            position.value = value;
          }
        }),
      )
      ..add(
        player.stream.completed.listen((bool completed) {
          if (current() && completed) {
            _completed.add(null);
          }
        }),
      );
  }

  void _armFirstFrameTimer(VideoLease lease) {
    _firstFrameTimer?.cancel();
    _progressMark = downloadProgress?.value;
    _firstFrameTimer = Timer(_firstFrameTimeout, () {
      if (_lease != lease || _hasFirstFrame || _demands.isEmpty) {
        return;
      }
      // Still arriving over a slow connection: give it another round.
      final double? progress = downloadProgress?.value;
      if (progress != null && progress != _progressMark && progress < 1) {
        _armFirstFrameTimer(lease);
        return;
      }
      _fail();
    });
  }

  void _detach() {
    _opened = false;
    _firstFrameTimer?.cancel();
    for (final StreamSubscription<Object?> sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
  }

  /// [VideoPlayers] took the player (for another video, or because the app
  /// went to the background): continue where it was when it's wanted again.
  void _onEvicted() {
    final VideoLease? lease = _lease;
    if (lease == null) {
      return;
    }
    if (_hasFirstFrame) {
      _resumeAt = lease.player.state.position;
      _resumePlaying = !_userPaused;
    }
    _token++;
    _starting = false;
    _detach();
    _lease = null;
    _hasFirstFrame = false;
    _playing = false;
    _buffering = false;
    notifyListeners();
  }

  /// It didn't play: a fresh player gets one more go, then it waits for
  /// [retry].
  void _fail() {
    final VideoLease? lease = _lease;
    _token++;
    _starting = false;
    _detach();
    _lease = null;
    lease?.release();
    _hasFirstFrame = false;
    _playing = false;

    if (!_retried) {
      _retried = true;
      notifyListeners();
      _sync();
      return;
    }
    _failed = true;
    notifyListeners();
  }

  /// Tries again, downloading the video again (the copy may be broken).
  Future<void> retry() async {
    if (isRemote && _resolveSource == null) {
      await VideoServer.instance.evict(source);
    }
    _failed = false;
    _retried = false;
    notifyListeners();
    _sync();
  }
}

/// Shows a [MediaVideo]: its thumbnail until the first frame, then the
/// video, with download progress or a retry button over it.
class MediaVideoView extends StatelessWidget {
  const MediaVideoView({
    super.key,
    required this.video,
    required this.thumbnail,
    this.fit = BoxFit.contain,
    this.aspectRatio,
    this.indicatorSize = 26,
    this.wakelock = false,
  });

  final MediaVideo video;
  final Widget thumbnail;
  final BoxFit fit;

  /// Sizes the video inside the available space (for [BoxFit.contain]).
  final double? aspectRatio;
  final double indicatorSize;

  /// Keeps the screen on while it plays. The lock is global and each view
  /// toggles it, so only the fullscreen viewer takes it.
  final bool wakelock;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: video,
      builder: (context, _) {
        final VideoController? controller = video.controller;
        Widget? surface;
        if (controller != null) {
          surface = Video(
            controller: controller,
            fit: fit,
            controls: NoVideoControls,
            // Not black: the bars around the video show what's behind it
            // (the blurred thumbnail in fullscreen).
            fill: Colors.transparent,
            wakelock: wakelock,
            // VideoPlayers already handles the background.
            pauseUponEnteringBackgroundMode: false,
          );
          final double? ratio = aspectRatio;
          if (ratio != null) {
            surface = Center(
              child: AspectRatio(aspectRatio: ratio, child: surface),
            );
          }
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            thumbnail,
            if (surface != null)
              AnimatedOpacity(
                opacity: video.hasFirstFrame ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: surface,
              ),
            if (video.failed)
              Center(
                child: GestureDetector(
                  onTap: video.retry,
                  child: Container(
                    padding: EdgeInsets.all(indicatorSize * 0.4),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      CupertinoIcons.arrow_counterclockwise,
                      color: Colors.white,
                      size: indicatorSize * 0.8,
                    ),
                  ),
                ),
              )
            else if (video.isLoading ||
                (video.hasFirstFrame && video.isBuffering))
              Center(
                child: _LoadingIndicator(video: video, size: indicatorSize),
              ),
          ],
        );
      },
    );
  }
}

/// Download progress while the video arrives, then a spinner.
class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator({required this.video, required this.size});

  final MediaVideo video;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ValueListenable<double?>? progress = video.downloadProgress;
    if (progress == null) {
      return CupertinoActivityIndicator(radius: size / 2.4);
    }
    return ValueListenableBuilder<double?>(
      valueListenable: progress,
      builder: (context, value, _) {
        if (value == null || value >= 1 || video.hasFirstFrame) {
          return CupertinoActivityIndicator(radius: size / 2.4);
        }
        return SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            value: value,
            strokeWidth: 3,
            color: Colors.white,
            backgroundColor: Colors.white24,
          ),
        );
      },
    );
  }
}

/// Corner radius of inline videos; the zoom into fullscreen rounds it off.
const double mediaInlineRadius = 12;
