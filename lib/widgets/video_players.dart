import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 4chan caps webms at a few MB and videos play from a downloaded file, so
/// a small demuxer cache is plenty; media_kit's default is 32 MB per player.
const int _mediaBufferBytes = 8 * 1024 * 1024;

/// Every video player in the app comes from here, and at most [maxPlayers]
/// exist at once. Each mpv player has its own
/// decoder, threads and video surface; with a dozen alive (visible,
/// preloaded and pooled), scrolling through videos lagged.
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

  static const int maxPlayers = 3;

  // How much more a video must be wanted to take a wanted player, so two
  // videos about as visible don't take it from each other while scrolling.
  static const double _takeOverMargin = 0.25;

  // Least recently wanted first.
  final List<VideoLease> _leases = <VideoLease>[];
  bool _inBackground = false;
  bool _notifyScheduled = false;
  // Someone was refused a player and waits for a notification.
  bool _waiting = false;
  // Lives as long as the app.
  // ignore: unused_field
  late final AppLifecycleListener _lifecycleListener;

  /// Whether [acquire] would hand out a player for a video wanted with
  /// [priority].
  bool canAcquire(double priority) {
    if (!_inBackground &&
        (_leases.length < maxPlayers || _victimFor(priority) != null)) {
      return true;
    }
    _waiting = true;
    return false;
  }

  /// A player for a video of [width] x [height] (when known) wanted with
  /// [priority] (see [VideoLease.priority]), or null if all [maxPlayers]
  /// are wanted about as much or more (or the app is in the background).
  /// [onEvicted] runs when the player is taken away; it's disposed after.
  VideoLease? acquire({
    required VoidCallback onEvicted,
    required double priority,
    int? width,
    int? height,
  }) {
    if (!canAcquire(priority)) {
      return null;
    }
    if (_leases.length >= maxPlayers) {
      _victimFor(priority)!._evict();
    }

    final Player player = Player(
      configuration: const PlayerConfiguration(bufferSize: _mediaBufferBytes),
    );
    _waitForStreams(player);
    final bool knownSize = width != null && height != null;
    final VideoController controller = VideoController(
      player,
      // Sized up front on iOS: media_kit's iOS video output otherwise works
      // the size out while rendering, which can lock up.
      configuration: VideoControllerConfiguration(
        width: Platform.isIOS && knownSize ? width : null,
        height: Platform.isIOS && knownSize ? height : null,
      ),
    );
    final VideoLease lease = VideoLease._(
      this,
      player,
      controller,
      onEvicted,
      Platform.isIOS && knownSize
          ? _firstFrameOnIOS(player)
          : controller.waitUntilFirstFrameRendered,
    );
    _leases.add(lease);
    return lease;
  }

  /// The least recently used lease nobody wants, else the wanted one with
  /// the lowest priority if [priority] is clearly higher; null if none.
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

  /// When [player] shows its first frame. media_kit's iOS output reports
  /// that as soon as it has a size, and it has one from the start (above):
  /// before mpv has even opened the video, which then showed as a black
  /// box instead of its thumbnail while loading. mpv configures its video
  /// output for the first decoded frame, right before drawing it.
  static Future<void> _firstFrameOnIOS(Player player) {
    final Completer<void> shown = Completer<void>();
    final PlatformPlayer platform = player.platform!;
    if (platform is NativePlayer) {
      platform
          .observeProperty('vo-configured', (String value) async {
            if (value == 'yes' && !shown.isCompleted) {
              shown.complete();
            }
          })
          .catchError((_) {});
    }
    return shown.future;
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
      // Whoever is still refused says so again.
      _waiting = false;
      notifyListeners();
    });
  }
}

/// A player handed out by [VideoPlayers]; give it back with [release].
class VideoLease {
  VideoLease._(
    this._manager,
    this.player,
    this.controller,
    this._onEvicted,
    this.firstFrame,
  );

  final VideoPlayers _manager;
  final Player player;
  final VideoController controller;
  final VoidCallback _onEvicted;

  /// Completes once the video's first frame shows.
  final Future<void> firstFrame;
  double _priority = 0;
  bool _released = false;

  bool get isReleased => _released;

  /// How much the holder wants it: 0 when it doesn't play it and isn't
  /// about to, otherwise how much of the video is on screen (0 to 1, more
  /// for fullscreen). A wanted lease is only taken for a video wanted
  /// clearly more.
  double get priority => _priority;

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
      // It can be taken now; tell anyone waiting for a player.
      _manager._notifySoon();
    } else {
      _manager._wantedLess();
    }
  }

  bool get wanted => _priority > 0;

  void release() {
    if (_released) {
      return;
    }
    _released = true;
    _manager._forget(this);
    unawaited(_dispose());
  }

  void _evict() {
    if (_released) {
      return;
    }
    _released = true;
    _manager._forget(this);
    _onEvicted();
    unawaited(_dispose());
  }

  // Pausing first stops mpv's playback threads before the teardown.
  Future<void> _dispose() async {
    try {
      await player.pause();
    } catch (_) {}
    try {
      await player.dispose();
    } catch (_) {}
  }
}
