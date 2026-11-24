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
/// A player given back is kept and handed to the next video instead of
/// being disposed. Creating an mpv player and tearing one down both block
/// the UI thread (mpv starts up there, and its GL context is freed there),
/// so with a new player for every video, scrolling stuttered each time a
/// video came on screen once all were in use.
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
  /// Players made by [create]; [sizesUpFront] says whether a player's
  /// output is sized for its video before it opens it, and [reuses] whether
  /// a player given back is kept for the next video. The app's own is
  /// [instance]; tests make theirs.
  @visibleForTesting
  VideoPlayers({
    required PlayerOutput Function({int? width, int? height}) create,
    required this.sizesUpFront,
    required bool reuses,
  }) : _create = create,
       _reuses = reuses {
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

  static VideoPlayers? _instance;

  static VideoPlayers get instance => _instance ??= VideoPlayers(
    create: MpvPlayerOutput.create,
    // media_kit's iOS output otherwise works the size out while rendering,
    // asking mpv for it from its render thread, which can lock up. Its
    // Android output can't be sized (and sizes itself from the video).
    sizesUpFront: Platform.isIOS,
    reuses: Platform.isIOS || _reusesOnAndroid,
  );

  @visibleForTesting
  static set instance(VideoPlayers players) => _instance = players;

  /// Android reuses players too since a video's first frame comes from
  /// mpv's own events ([_PooledPlayer.watchOutput]): before that it came
  /// from media_kit's output, which reports one only for a player's first
  /// video, so a reused player never showed. Checked against media_kit's
  /// Android output, not yet on a phone; false gives each video a new
  /// player there again.
  static const bool _reusesOnAndroid = true;

  // Four, so a thread showing four short videos at once plays them all.
  static const int _maxPlayers = 4;

  // How much more a video must be wanted to take a wanted player, so two
  // videos about as visible don't take it from each other while scrolling.
  static const double _takeOverMargin = 0.25;

  final PlayerOutput Function({int? width, int? height}) _create;
  final bool _reuses;

  /// Whether a player's output is sized for its video before it opens it,
  /// from the size its holder knows: a holder that doesn't know it should
  /// find it out first if it can.
  final bool sizesUpFront;

  // Least recently wanted first.
  final List<VideoLease> _leases = <VideoLease>[];
  // Players nobody holds, ready for the next video once stopped.
  final List<_PooledPlayer> _free = <_PooledPlayer>[];
  bool _inBackground = false;
  bool _notifyScheduled = false;
  // Someone was refused a player and waits for a notification.
  bool _waiting = false;
  late final AppLifecycleListener _lifecycleListener;

  /// How many players exist, held or free.
  @visibleForTesting
  int get playerCount => _leases.length + _free.length;

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

    final bool sized = sizesUpFront && width != null && height != null;
    final _PooledPlayer pooled;
    final bool byOutput;
    ({int? width, int? height})? resize;
    if (_free.isNotEmpty) {
      pooled = _free.removeAt(0);
      if (sizesUpFront) {
        // Sized when this lease opens its video, not now: the video it was
        // taken from may still be on screen, showing it.
        resize = (width: sized ? width : null, height: sized ? height : null);
      }
      // Its output's first frame was reported long ago, for its first video.
      byOutput = true;
    } else {
      pooled = _PooledPlayer(
        _create(width: sized ? width : null, height: sized ? height : null),
      );
      // media_kit's iOS output reports a first frame as soon as it has a
      // size, which it has from the start when sized up front.
      byOutput = sized;
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

  /// Keeps [pooled] for the next video, or disposes it: when players
  /// aren't reused, in the background (where there are no players) or when
  /// it [broke].
  void _giveBack(_PooledPlayer pooled, {required bool broke}) {
    if (!_reuses || _inBackground || broke) {
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

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
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
  VideoController get controller => _pooled.output.controller;

  /// Completes when the video [open] opened shows its first frame.
  Future<void> get firstFrame =>
      _byOutput ? _output.future : _pooled.output.firstFrame;

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
        await _pooled.output
            .setSize(size.width, size.height)
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

/// A player and the output that draws its video, as [VideoPlayers] uses
/// them: mpv's through media_kit ([MpvPlayerOutput]), or a test's.
abstract interface class PlayerOutput {
  Player get player;

  /// What views show the video with.
  VideoController get controller;

  /// Runs [onRestart] each time mpv restarts playback, which it does once
  /// the first frame after opening a video (or seeking) is drawn, paused
  /// or not. Done once it listens.
  Future<void> listenForRestarts(void Function() onRestart);

  /// The output's own first frame, which it reports for its first video.
  Future<void> get firstFrame;

  /// Sizes the output; null for the video's own size.
  Future<void> setSize(int? width, int? height);

  Future<void> dispose();
}

/// An mpv player and its video output, through media_kit.
class MpvPlayerOutput implements PlayerOutput {
  MpvPlayerOutput._(this.player, this.controller);

  /// Sized up front to [width] x [height], if given.
  factory MpvPlayerOutput.create({int? width, int? height}) {
    final Player player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: _mediaBufferBytes,
        // The app sets iPhone's audio up itself (VideoAudio): mpv set it
        // up for playback as each video loaded, which stopped other apps'
        // music for muted videos in threads.
        iosManageAudioSession: false,
      ),
    );
    _waitForStreams(player);
    return MpvPlayerOutput._(
      player,
      VideoController(
        player,
        configuration: VideoControllerConfiguration(
          width: width,
          height: height,
        ),
      ),
    );
  }

  @override
  final Player player;

  @override
  final VideoController controller;

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

  @override
  Future<void> listenForRestarts(void Function() onRestart) {
    final PlatformPlayer? platform = player.platform;
    if (platform is! NativePlayer) {
      return Future<void>.value();
    }
    return platform
        .observeEvent(mpv_event_id.MPV_EVENT_PLAYBACK_RESTART, (_) async {
          onRestart();
        })
        .catchError((_) {});
  }

  @override
  Future<void> get firstFrame => controller.waitUntilFirstFrameRendered;

  @override
  Future<void> setSize(int? width, int? height) =>
      controller.setSize(width: width, height: height);

  @override
  Future<void> dispose() => player.dispose();
}

/// A player and its video output, kept alive across the videos it plays.
///
/// What a holder does to set it up and open its video ([VideoLease.open])
/// and stopping that video for the next one ([recycle]) run one after
/// another ([run]): a holder that lost the player while still opening its
/// video would otherwise open it into the next one's.
class _PooledPlayer {
  _PooledPlayer(this.output) {
    _videoParams = player.stream.videoParams.listen(_onVideoParams);
    listening = output.listenForRestarts(() {
      _restarted = true;
      _checkOutput();
    });
  }

  final PlayerOutput output;

  Player get player => output.player;

  late final StreamSubscription<VideoParams> _videoParams;

  /// Done once mpv's playback restarts reach this (see [watchOutput]).
  late final Future<void> listening;

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
  /// before mpv has even opened the video; and its Android output reports
  /// one only for a player's first video.
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
      await output.dispose();
    } catch (_) {}
  }
}
