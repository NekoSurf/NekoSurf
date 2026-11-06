import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/media/video_players.dart';
import 'package:flutter_chan/media/video_server.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

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
  MediaVideo._(this.source, this._width, this._height) {
    VideoPlayers.instance.addListener(_sync);
  }

  static final Map<String, MediaVideo> _all = <String, MediaVideo>{};

  /// The shared video for [source], a 4chan address or a file on the phone;
  /// give it back with [release]. The first to obtain it says how it starts.
  static MediaVideo obtain(
    String source, {
    int? width,
    int? height,
    bool muted = true,
  }) {
    final MediaVideo video = _all.putIfAbsent(source, () {
      return MediaVideo._(source, width, height).._muted = muted;
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
  final int? _width;
  final int? _height;
  int _refs = 0;

  // Who wants it playing, and whether they want sound.
  final Map<Object, bool> _demands = <Object, bool>{};
  // How much of it each of them shows.
  final Map<Object, double> _shown = <Object, double>{};
  bool _userPaused = false;
  // Without sound unless someone wants it audible (fullscreen) or the user
  // unmutes the inline video.
  bool _muted = true;
  double _rate = 1;
  bool _loop = true;

  VideoLease? _lease;
  // Told to VideoServer, whose download for a watched video goes first.
  bool _watched = false;
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

  Duration get shownPosition => scrubPosition.value ?? position.value;

  Listenable get progressChanged =>
      Listenable.merge([scrubPosition, position, loaded]);

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

  // 4chan videos, which stream through VideoServer.
  bool get _served => source.startsWith('http');

  /// The video reached its end (only without looping).
  Stream<void> get completed => _completed.stream;

  /// How much of the video has downloaded; only for 4chan videos.
  ValueListenable<double?>? get downloadProgress =>
      _served ? VideoServer.instance.progressOf(source) : null;

  /// Which parts of the video are here, as (start, end) fractions of it:
  /// behind the position on progress bars, like a stream's buffer. More
  /// than one after scrubbing ahead of the download.
  ValueListenable<List<(double, double)>> get loaded =>
      _served ? VideoServer.instance.loadedOf(source) : _allLoaded;

  static final ValueNotifier<List<(double, double)>> _allLoaded =
      ValueNotifier<List<(double, double)>>(const [(0, 1)]);

  set muted(bool value) {
    _muted = value;
    _applyVolume();
    notifyListeners();
  }

  /// [owner] shows the video and wants it playing, with sound if [audible].
  /// [shown] is how much of it is on screen, from 0 to 1: with more videos
  /// on screen than players, the ones shown most play.
  void want(Object owner, {bool audible = false, double shown = 1}) {
    final bool? wasAudible = _demands[owner];
    _demands[owner] = audible;
    _shown[owner] = shown;
    if (wasAudible == null) {
      _userPaused = false;
    }
    if (wasAudible != audible) {
      _applyVolume();
    }
    _sync();
  }

  void unwant(Object owner) {
    _shown.remove(owner);
    if (_demands.remove(owner) == null) {
      return;
    }
    _applyVolume();
    _sync();
  }

  /// For [VideoPlayers]: fullscreen first, then the more of it is shown.
  double get _priority {
    double priority = 0;
    for (final MapEntry<Object, bool> demand in _demands.entries) {
      priority = max(priority, demand.value ? 2 : _shown[demand.key] ?? 1);
    }
    return priority;
  }

  void prefetch() {
    if (_served) {
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
      restartIfFinished();
      player.play().catchError((_) {});
    } else {
      _sync();
    }
  }

  void restartIfFinished() {
    final Player? player = _lease?.player;
    if (player != null && player.state.completed) {
      player.seek(Duration.zero).catchError((_) {});
    }
  }

  void release(Object owner) {
    unwant(owner);
    if (--_refs > 0) {
      return;
    }
    _all.remove(source);
    VideoPlayers.instance.removeListener(_sync);
    _token++;
    _pauseTimer?.cancel();
    _setWatched(false);
    _detach();
    _lease?.release();
    _lease = null;
    unawaited(_completed.close());
    position.dispose();
    scrubPosition.dispose();
    dispose();
  }

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
      if ((_watched || (lease?.wanted ?? false)) && !_pauseTimerActive) {
        _pauseTimer = Timer(_pauseGrace, () {
          if (_demands.isNotEmpty) {
            return;
          }
          _setWatched(false);
          if (lease != null && _lease == lease) {
            lease.priority = 0;
            lease.player.pause().catchError((_) {});
          }
        });
      }
      return;
    }

    _pauseTimer?.cancel();
    _setWatched(true);
    if (lease == null) {
      unawaited(_start());
      return;
    }
    lease.priority = _priority;
    if (!_hasFirstFrame && !(_firstFrameTimer?.isActive ?? false)) {
      _armFirstFrameTimer(lease);
    }
    if (_opened && !_userPaused && !_scrubbing && !lease.player.state.playing) {
      lease.player.play().catchError((_) {});
    }
  }

  bool get _pauseTimerActive => _pauseTimer?.isActive ?? false;

  void _setWatched(bool watched) {
    if (!_served || watched == _watched) {
      return;
    }
    _watched = watched;
    if (watched) {
      VideoServer.instance.watch(source);
    } else {
      VideoServer.instance.unwatch(source);
    }
  }

  Future<String> _mediaSource() async =>
      _served ? VideoServer.instance.source(source) : source;

  Future<void> _start() async {
    if (_starting || _failed || _lease != null || _demands.isEmpty) {
      return;
    }
    // Every player plays a video shown about as much or more; _sync runs
    // again when that changes.
    if (!VideoPlayers.instance.canAcquire(_priority)) {
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
        priority: _priority,
        width: _width,
        height: _height,
      );
      // Taken meanwhile; _sync runs again when one is freed.
      if (lease == null) {
        _starting = false;
        notifyListeners();
        return;
      }
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
    } catch (error) {
      if (token == _token) {
        debugPrint('Video failed to open [$source]: $error');
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

    lease.firstFrame.then((_) {
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
      )
      ..add(
        // Only logged: some are bogus (see _firstFrameTimeout), but they
        // explain a video that then doesn't play.
        player.stream.error.listen((String error) {
          if (current()) {
            debugPrint('mpv error [$source]: $error');
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
      debugPrint(
        'Video showed no frame within '
        '${_firstFrameTimeout.inSeconds}s [$source]',
      );
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

  void _onEvicted() {
    final VideoLease? lease = _lease;
    if (lease == null) {
      return;
    }
    if (_hasFirstFrame) {
      _resumeAt = lease.player.state.position;
      _resumePlaying = !_userPaused;
    }
    _dropPlayer();
    notifyListeners();
  }

  void _dropPlayer() {
    _token++;
    _starting = false;
    _detach();
    _lease = null;
    _hasFirstFrame = false;
    _playing = false;
    _buffering = false;
  }

  void _fail() {
    final VideoLease? lease = _lease;
    _dropPlayer();
    lease?.release();

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
    if (_served) {
      await VideoServer.instance.evict(source);
    }
    _failed = false;
    _retried = false;
    notifyListeners();
    _sync();
  }
}

class MediaVideoView extends StatelessWidget {
  const MediaVideoView({
    super.key,
    required this.video,
    required this.thumbnail,
    this.fit = BoxFit.contain,
    this.indicatorSize = 26,
    this.wakelock = false,
  });

  final MediaVideo video;
  final Widget thumbnail;
  final BoxFit fit;
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

        return Stack(
          fit: StackFit.expand,
          children: [
            thumbnail,
            if (controller != null)
              AnimatedOpacity(
                opacity: video.hasFirstFrame ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: Video(
                  controller: controller,
                  fit: fit,
                  // No controls: media_kit's NoVideoControls is an untyped null.
                  controls: null,
                  // Not black: the bars around the video show what's behind it
                  // (the blurred thumbnail in fullscreen).
                  fill: Colors.transparent,
                  wakelock: wakelock,
                  // VideoPlayers already handles the background.
                  pauseUponEnteringBackgroundMode: false,
                ),
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
              Center(child: _LoadingIndicator(size: indicatorSize)),
          ],
        );
      },
    );
  }
}

/// A spinner, once loading or buffering takes a moment: a video that
/// starts right away (from the cache, or on a fast connection) goes
/// straight from its thumbnail to playing. Download progress showed here
/// too, but the video starts long before the download is done, so it only
/// flashed by; once it plays, the progress bar shows what has loaded.
class _LoadingIndicator extends StatefulWidget {
  const _LoadingIndicator({required this.size});

  final double size;

  @override
  State<_LoadingIndicator> createState() => _LoadingIndicatorState();
}

class _LoadingIndicatorState extends State<_LoadingIndicator> {
  static const Duration _delay = Duration(milliseconds: 300);

  bool _shown = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_delay, () => setState(() => _shown = true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: const Duration(milliseconds: 150),
      child: CupertinoActivityIndicator(radius: widget.size / 2.4),
    );
  }
}
