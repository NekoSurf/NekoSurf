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
/// A holder marks its lease [VideoLease.wanted] while it plays or is about
/// to. When a new player is needed and none is free, the least recently
/// used lease that isn't wanted is evicted: its holder is told and falls
/// back to the thumbnail. If every lease is wanted, [acquire] returns null;
/// the caller waits for this to notify that a player was freed or is no
/// longer wanted.
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

  // Least recently wanted first.
  final List<VideoLease> _leases = <VideoLease>[];
  bool _inBackground = false;
  bool _notifyScheduled = false;
  // Lives as long as the app.
  // ignore: unused_field
  late final AppLifecycleListener _lifecycleListener;

  /// A player for a video of [width] x [height] (when known), or null if
  /// all [maxPlayers] are wanted (or the app is in the background).
  /// [onEvicted] runs when the player is taken away; it's disposed after.
  VideoLease? acquire({
    required VoidCallback onEvicted,
    int? width,
    int? height,
  }) {
    if (_inBackground) {
      return null;
    }

    if (_leases.length >= maxPlayers) {
      final int victim = _leases.indexWhere((lease) => !lease._wanted);
      if (victim < 0) {
        return null;
      }
      _leases[victim]._evict();
    }

    final Player player = Player(
      configuration: const PlayerConfiguration(bufferSize: _mediaBufferBytes),
    );
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
    final VideoLease lease = VideoLease._(this, player, controller, onEvicted);
    _leases.add(lease);
    return lease;
  }

  void _touch(VideoLease lease) {
    if (_leases.remove(lease)) {
      _leases.add(lease);
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
      notifyListeners();
    });
  }
}

/// A player handed out by [VideoPlayers]; give it back with [release].
class VideoLease {
  VideoLease._(this._manager, this.player, this.controller, this._onEvicted);

  final VideoPlayers _manager;
  final Player player;
  final VideoController controller;
  final VoidCallback _onEvicted;
  bool _wanted = false;
  bool _released = false;

  bool get isReleased => _released;

  /// Whether the holder is playing it or about to; wanted leases are never
  /// evicted for someone else.
  bool get wanted => _wanted;

  set wanted(bool value) {
    final bool was = _wanted;
    _wanted = value;
    if (value) {
      _manager._touch(this);
    } else if (was && !_released) {
      // It can be taken now; tell anyone waiting for a player.
      _manager._notifySoon();
    }
  }

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
