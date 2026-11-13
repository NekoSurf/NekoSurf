import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' show mpv_event_id;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 4chan caps webms at a few MB and videos play from a downloaded file, so
/// a small demuxer cache is plenty; media_kit's default is 32 MB per player.
const int _mediaBufferBytes = 8 * 1024 * 1024;

/// Every video player in the app comes from here, and at most [_maxPlayers]
/// exist at once. Each mpv player has its own
/// decoder, threads and video surface; with a dozen alive (visible,
/// preloaded and pooled), scrolling through videos lagged.
///
/// On iOS, a player given back is kept and handed to the next video
/// instead of being disposed. Creating an mpv player and tearing one down
/// both block the UI thread (mpv starts up there, and its GL context is
/// freed there), so with a new player for every video, scrolling stuttered
/// each time a video came on screen once all were in use. Android's video
/// output never reports a reused player's first frame, so there each video
/// still gets a new one.
///
/// A holder gives its lease a [VideoLease.priority] while it plays or is
/// about to: how much of the video is on screen, or more for fullscreen.
/// When a new player is needed and none is free, the least recently used
/// lease that isn't wanted is evicted: its holder is told and falls back to
/// the thumbnail. If every lease is wanted, the one shown least is evicted
/// for a video shown clearly more, so the videos most on screen play.
/// Otherwise [acquire] returns null; the caller waits for this to notify
/// that a player was freed or is wanted less.
///
/// While the app is in the background there are no players at all: iOS can
/// break their decoders there, and players still alive when iOS tears the
/// app down make mpv crash.
class VideoPlayers extends ChangeNotifier {
  VideoPlayers._() {
    _lifecycleListener = AppLifecycleListener(
      onInactive: _pauseWhileInactive,
      onResume: _playAfterInactive,
      onHide: _releaseAll,
      onShow: () {
        _inBackground = false;
        _notifySoon();
      },
    );
  }

  static final VideoPlayers instance = VideoPlayers._();

  // Four, so a thread showing four short videos at once plays them all.
  static const int _maxPlayers = 4;

  // How much more a video must be wanted to take a wanted player, so two
  // videos about as visible don't take it from each other while scrolling.
  static const double _takeOverMargin = 0.25;

  // Least recently wanted first.
  final List<VideoLease> _leases = <VideoLease>[];
  // Players nobody holds, ready for the next video once stopped.
  final List<_PooledPlayer> _free = <_PooledPlayer>[];
  bool _inBackground = false;
  bool _notifyScheduled = false;
  // Someone was refused a player and waits for a notification.
  bool _waiting = false;
  // Lives as long as the app.
  // ignore: unused_field
  late final AppLifecycleListener _lifecycleListener;

  /// Videos pause while the app isn't active (in the app switcher, say),
  /// as the app is covered there ("Hide in the app switcher"); the app
  /// sets it from that setting.
  bool pausesWhileInactive = false;

  // Paused by [_pauseWhileInactive], to play again when the app's back.
  final Set<VideoLease> _pausedWhileInactive = <VideoLease>{};

  void _pauseWhileInactive() {
    if (!pausesWhileInactive) {
      return;
    }
    for (final VideoLease lease in _leases) {
      if (lease.player.state.playing) {
        _pausedWhileInactive.add(lease);
        lease.player.pause().catchError((_) {});
      }
    }
  }

  void _playAfterInactive() {
    for (final VideoLease lease in _pausedWhileInactive) {
      // Not if it went meanwhile, as all do in the background.
      if (_leases.contains(lease)) {
        lease.player.play().catchError((_) {});
      }
    }
    _pausedWhileInactive.clear();
  }

  bool canAcquire(double priority) {
    if (!_inBackground &&
        (_leases.length < _maxPlayers || _victimFor(priority) != null)) {
      return true;
    }
    _waiting = true;
    return false;
  }

  /// A player for a video of [width] x [height] (when known) wanted with
  /// [priority] (see [VideoLease.priority]), or null if all [_maxPlayers]
  /// are wanted about as much or more (or the app is in the background).
  /// [onEvicted] runs when the player is taken away, before it's stopped
  /// for the next video (or disposed).
  VideoLease? acquire({
    required VoidCallback onEvicted,
    required double priority,
    int? width,
    int? height,
  }) {
    if (!canAcquire(priority)) {
      return null;
    }
    if (_leases.length >= _maxPlayers) {
      _victimFor(priority)!._evict();
    }

    final bool knownSize = width != null && height != null;
    final _PooledPlayer pooled;
    final bool byOutput;
    ({int? width, int? height})? resize;
    if (_free.isNotEmpty) {
      // Only on iOS (see [_giveBack]).
      pooled = _free.removeAt(0);
      // Sized when this lease opens its video, not now: the video it was
      // taken from may still be on screen, showing it.
      resize = (
        width: knownSize ? width : null,
        height: knownSize ? height : null,
      );
      // Its own first frame was reported long ago, for its first video.
      byOutput = true;
    } else {
      final Player player = Player(
        configuration: const PlayerConfiguration(bufferSize: _mediaBufferBytes),
      );
      _waitForStreams(player);
      final VideoController controller = VideoController(
        player,
        // Sized up front on iOS: media_kit's iOS video output otherwise works
        // the size out while rendering, which can lock up.
        configuration: VideoControllerConfiguration(
          width: Platform.isIOS && knownSize ? width : null,
          height: Platform.isIOS && knownSize ? height : null,
        ),
      );
      pooled = _PooledPlayer(player, controller);
      byOutput = Platform.isIOS && knownSize;
    }
    final VideoLease lease = VideoLease._(
      this,
      pooled,
      onEvicted,
      byOutput: byOutput,
      resize: resize,
    ).._priority = priority;
    _leases.add(lease);
    return lease;
  }

  VideoLease? _victimFor(double priority) {
    VideoLease? victim;
    for (final VideoLease lease in _leases) {
      if (victim == null || lease._priority < victim._priority) {
        victim = lease;
      }
    }
    if (victim != null &&
        victim.wanted &&
        victim._priority > priority - _takeOverMargin) {
      return null;
    }
    return victim;
  }

  /// Lets [player] wait for a stream from VideoServer as long as mpv
  /// usually would. media_kit gives up after 5 s, but the server stalls a
  /// stream whenever its download waits (held for a video being watched,
  /// or a slow connection); mpv then reconnected over and over, and after a
  /// few minutes gave up mid-video. The server closes the stream itself if
  /// the download fails.
  static void _waitForStreams(Player player) {
    final PlatformPlayer platform = player.platform!;
    if (platform is NativePlayer) {
      platform.setProperty('network-timeout', '60').catchError((_) {});
    }
  }

  void _touch(VideoLease lease) {
    if (_leases.remove(lease)) {
      _leases.add(lease);
    }
  }

  void _wantedLess() {
    if (_waiting) {
      _notifySoon();
    }
  }

  void _forget(VideoLease lease) {
    if (_leases.remove(lease)) {
      _notifySoon();
    }
  }

  void _releaseAll() {
    _inBackground = true;
    _pausedWhileInactive.clear();
    for (final VideoLease lease in List<VideoLease>.of(_leases)) {
      lease._evict();
    }
    for (final _PooledPlayer pooled in _free) {
      unawaited(pooled.dispose());
    }
    _free.clear();
  }

  /// Keeps [pooled] for the next video on iOS, or disposes it: on Android,
  /// in the background (where there are no players) or when it [broke].
  void _giveBack(_PooledPlayer pooled, {required bool broke}) {
    if (!Platform.isIOS || _inBackground || broke) {
      unawaited(pooled.dispose());
      return;
    }
    pooled.recycle();
    _free.add(pooled);
  }

  // Leases are often released from dispose(), where listeners must not
  // rebuild other widgets yet.
  void _notifySoon() {
    if (_notifyScheduled) {
      return;
    }
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      _waiting = false;
      notifyListeners();
    });
  }
}

/// A player handed out by [VideoPlayers]; give it back with [release].
class VideoLease {
  VideoLease._(
    this._manager,
    this._pooled,
    this._onEvicted, {
    required bool byOutput,
    ({int? width, int? height})? resize,
  }) : _byOutput = byOutput,
       _resize = resize;

  /// The size a reused player takes for this lease's video, set as it opens.
  final ({int? width, int? height})? _resize;

  final VideoPlayers _manager;
  final _PooledPlayer _pooled;
  final VoidCallback _onEvicted;

  // The first frame is when mpv has drawn the video opened here (see
  // [_PooledPlayer.watchOutput]); otherwise media_kit's.
  final bool _byOutput;
  final Completer<void> _output = Completer<void>();
  double _priority = 0;
  bool _released = false;

  Player get player => _pooled.player;
  VideoController get controller => _pooled.controller;

  /// Completes when the video [open] opened shows its first frame.
  Future<void> get firstFrame => _byOutput
      ? _output.future
      : _pooled.controller.waitUntilFirstFrameRendered;

  /// Opens [media] paused, after [setUp]. A reused player first finishes
  /// what its last holder still had running and stops that video. Skipped
  /// (false) once this lease is given back: the player may be another
  /// video's by then.
  Future<bool> open(
    Media media, {
    required Future<void> Function(Player player) setUp,
  }) async {
    bool opened = false;
    await _pooled.run(() async {
      if (_released) {
        return;
      }
      await _pooled.listening;
      if (_resize case final ({int? width, int? height}) size) {
        // Once the video it was taken from has drawn without it: resized
        // sooner, that one flashed as it went, in the fullscreen viewer.
        await WidgetsBinding.instance.endOfFrame;
        if (_released) {
          return;
        }
        await controller
            .setSize(width: size.width, height: size.height)
            .catchError((_) {});
      }
      opened = true;
      await setUp(player);
      if (_byOutput) {
        _pooled.watchOutput(_output);
      }
      await player.open(media, play: false);
    });
    return opened;
  }

  /// How much the holder wants it: 0 once nothing shows the video (it may
  /// play on briefly, but is free to take), otherwise how much of the
  /// video is on screen (0 to 1, more for fullscreen). A wanted lease is
  /// only taken for a video wanted clearly more.
  set priority(double value) {
    final double was = _priority;
    _priority = value;
    if (value > 0) {
      _manager._touch(this);
    }
    if (_released || value >= was) {
      return;
    }
    if (value == 0) {
      _manager._notifySoon();
    } else {
      _manager._wantedLess();
    }
  }

  bool get wanted => _priority > 0;

  /// Gives the player back; if it [broke] (it showed nothing), it's
  /// disposed rather than handed to the next video.
  void release({bool broke = false}) {
    if (_released) {
      return;
    }
    _released = true;
    _manager._forget(this);
    _manager._giveBack(_pooled, broke: broke);
  }

  void _evict() {
    if (_released) {
      return;
    }
    _released = true;
    _manager._forget(this);
    _onEvicted();
    _manager._giveBack(_pooled, broke: false);
  }
}

/// A player and its video output, kept alive across the videos it plays.
///
/// What a holder does to set it up and open its video ([VideoLease.open])
/// and stopping that video for the next one ([recycle]) run one after
/// another ([run]): a holder that lost the player while still opening its
/// video would otherwise open it into the next one's.
class _PooledPlayer {
  _PooledPlayer(this.player, this.controller) {
    _videoParams = player.stream.videoParams.listen(_onVideoParams);
    final PlatformPlayer platform = player.platform!;
    if (platform is NativePlayer) {
      listening = platform
          .observeEvent(mpv_event_id.MPV_EVENT_PLAYBACK_RESTART, (_) async {
            _restarted = true;
            _checkOutput();
          })
          .catchError((_) {});
    }
  }

  final Player player;
  final VideoController controller;

  late final StreamSubscription<VideoParams> _videoParams;

  /// Done once mpv's playback restarts reach this (see [watchOutput]).
  Future<void> listening = Future<void>.value();

  Completer<void>? _output;
  // Since [watchOutput]: mpv decoded the video's first frame, and restarted
  // playback with it.
  bool _decoded = false;
  bool _restarted = false;
  Future<void> _last = Future<void>.value();

  void _onVideoParams(VideoParams params) {
    if ((params.dw ?? 0) > 0) {
      _decoded = true;
      _checkOutput();
    }
  }

  void _checkOutput() {
    final Completer<void>? output = _output;
    if (output != null && _decoded && _restarted && !output.isCompleted) {
      output.complete();
    }
  }

  /// Runs [step] once every step before it is done.
  Future<void> run(Future<void> Function() step) {
    final Future<void> done = _last.then((_) => step());
    _last = done.catchError((Object _) {});
    return done;
  }

  /// Completes [output] once the video opened next shows its first frame:
  /// mpv has decoded it (it has video-params) and restarted playback with
  /// it (playback-restart), which it does only once that frame is drawn,
  /// paused or not. Both come with mpv's events, in either order.
  ///
  /// Not video-params alone: mpv sets them as the first frame leaves the
  /// decoder, which can be well before it's drawn (a resumed video is
  /// decoded on to where it was, and mpv's output is set up and drawn
  /// through the UI thread, busy while scrolling). Shown by then, the
  /// player was black, or still showed the video it played before.
  ///
  /// Not media_kit's first frame either: its iOS output reports one as soon
  /// as it has a size, which it has from the start when sized up front,
  /// before mpv has even opened the video.
  ///
  /// Nor by reading mpv's state from Dart (as observeProperty does), which
  /// waits for mpv on the UI thread while mpv may wait on it to draw: on
  /// iPhone, that froze the app for 200 ms.
  void watchOutput(Completer<void> output) {
    _output = output;
    _decoded = false;
    _restarted = false;
  }

  /// Stops the video it played, once its holder's steps are done. What
  /// mpv still has to say about that video arrives before the next one's
  /// first frame is watched for: setting the next one up waits for mpv's
  /// replies, which come after it.
  void recycle() {
    _output = null;
    unawaited(
      run(() async {
        try {
          await player.pause();
          await player.stop();
        } catch (_) {}
      }),
    );
  }

  // Pausing first stops mpv's playback threads before the teardown.
  Future<void> dispose() async {
    unawaited(_videoParams.cancel());
    try {
      await player.pause();
    } catch (_) {}
    try {
      await player.dispose();
    } catch (_) {}
  }
}
