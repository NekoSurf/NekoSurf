import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
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
    if (_free.isNotEmpty) {
      // Only on iOS (see [_giveBack]).
      pooled = _free.removeAt(0);
      pooled.controller
          .setSize(
            width: knownSize ? width : null,
            height: knownSize ? height : null,
          )
          .catchError((_) {});
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
  }) : _byOutput = byOutput;

  final VideoPlayers _manager;
  final _PooledPlayer _pooled;
  final VoidCallback _onEvicted;

  // The first frame is when mpv configures its video output for the video
  // opened here (see [_PooledPlayer.watchOutput]); otherwise media_kit's.
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
  }

  final Player player;
  final VideoController controller;

  late final StreamSubscription<VideoParams> _videoParams;
  Completer<void>? _output;
  Future<void> _last = Future<void>.value();

  /// mpv sets video-params once the opened video's first frame is decoded,
  /// as it sets up its video output for it, right before drawing it; the
  /// stop before (and media_kit's open) only clear them.
  ///
  /// Not mpv's vo-configured, which flips at the same moment: media_kit
  /// reads a property watched with observeProperty back from mpv, on the UI
  /// thread, and mpv may only answer once a frame is drawn. On iOS
  /// media_kit draws after a step on the UI thread, which was waiting for
  /// mpv: the app froze until mpv gave up waiting (200 ms), often as a
  /// video showed its first frame. video-params come with mpv's event.
  void _onVideoParams(VideoParams params) {
    final Completer<void>? output = _output;
    if ((params.dw ?? 0) > 0 && output != null && !output.isCompleted) {
      output.complete();
    }
  }

  /// Runs [step] once every step before it is done.
  Future<void> run(Future<void> Function() step) {
    final Future<void> done = _last.then((_) => step());
    _last = done.catchError((Object _) {});
    return done;
  }

  /// Completes [output] when mpv next sets up its video output: for the
  /// first decoded frame of the video opened next, right before drawing
  /// it (see [_onVideoParams]). media_kit's iOS output reports a first
  /// frame as soon as it has a size, which it has from the start when
  /// sized up front: before mpv has even opened the video, which then
  /// showed as a black box instead of its thumbnail while loading.
  void watchOutput(Completer<void> output) {
    _output = output;
  }

  /// Stops the video it played, once its holder's steps are done. What
  /// mpv still has to say about that video arrives while the next one is
  /// set up (its setup waits on mpv), before its first frame is watched
  /// for.
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
