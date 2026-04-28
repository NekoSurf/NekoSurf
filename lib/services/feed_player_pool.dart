import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class _PoolSlot {
  _PoolSlot({required this.player, required this.controller});

  final Player player;
  final VideoController controller;

  String? ownerKey;
  String? loadedUrl;
  bool isActive = false;
  bool isPendingAcquire = false;
  DateTime lastUsedAt = DateTime.fromMillisecondsSinceEpoch(0);
}

/// A fixed-size pool of long-lived [Player] + [VideoController] pairs shared
/// across all [FeedVideoPlayer] widgets.
///
/// iOS supports at most ~2–3 simultaneous hardware decode sessions. Sharing a
/// pool keeps the live native player count at [_poolSize] regardless of how
/// many video posts are in the thread list, preventing OOM crashes from
/// excessive simultaneous AVPlayer / mpv_handle allocations.
class FeedPlayerPool {
  FeedPlayerPool._();

  static final FeedPlayerPool instance = FeedPlayerPool._();

  static int get _poolSize => 4;

  final List<_PoolSlot> _slots = [];
  bool _initialized = false;
  bool _disposed = false;
  Future<void> _acquireLock = Future<void>.value();

  Future<T> _withAcquireLock<T>(Future<T> Function() action) async {
    final previous = _acquireLock;
    final completer = Completer<void>();
    _acquireLock = completer.future;

    await previous;
    try {
      return await action();
    } finally {
      completer.complete();
    }
  }

  void _ensureInitialized() {
    if (_initialized || _disposed) return;
    _initialized = true;
    for (int i = 0; i < _poolSize; i++) {
      final player = Player();
      // PlaylistMode is a player-level property that persists across open()
      // calls, so setting it once here is sufficient.
      player.setPlaylistMode(PlaylistMode.loop);
      _slots.add(
        _PoolSlot(player: player, controller: VideoController(player)),
      );
    }
  }

  /// Acquires a pool slot for [key].
  ///
  /// * If a slot already owns [key] with the same URL it is returned
  ///   immediately (no open() call needed).
  /// * Otherwise the LRU inactive slot is evicted (player paused) and returned
  ///   with `loadedUrl == null`.  The caller is responsible for calling
  ///   [player.open()] on the returned slot — keeping open() outside of the
  ///   pool's internal lock prevents iOS AVAudioSession reconfiguration from
  ///   interrupting the other already-playing pool players (media-kit #964).
  /// * Returns `null` when the pool is exhausted (all slots actively in use by
  ///   different widgets — very rare when pool size ≥ number of visible posts).
  Future<_PoolSlot?> acquire(String key, String resolvedUrl) async {
    return _withAcquireLock(() async {
      _ensureInitialized();
      if (_disposed) return null;

      // Fast path: this key already owns a slot.
      for (final slot in _slots) {
        if (slot.ownerKey == key) {
          slot.isActive = true;
          slot.lastUsedAt = DateTime.now();
          if (slot.loadedUrl != resolvedUrl) {
            // URL changed; pause the player so the caller can safely open the
            // new source.  We don't call open() here — that is the caller's job.
            try {
              await slot.player.pause();
              slot.loadedUrl = null;
            } catch (_) {
              // Ignore pause races.
            }
          }
          return slot;
        }
      }

      // Find the least-recently-used inactive slot that is not being acquired.
      _PoolSlot? candidate;
      for (final slot in _slots) {
        if (!slot.isActive && !slot.isPendingAcquire) {
          if (candidate == null ||
              slot.lastUsedAt.isBefore(candidate.lastUsedAt)) {
            candidate = slot;
          }
        }
      }

      if (candidate == null) return null; // pool exhausted

      // Reserve the slot immediately to prevent a concurrent acquire from
      // choosing the same one.
      candidate.ownerKey = key;
      candidate.isPendingAcquire = true;
      candidate.lastUsedAt = DateTime.now();

      try {
        // Pause the previous video but do NOT call open() here.  Opening media
        // inside acquire() was the original design but it triggers an iOS
        // AVAudioSession reconfiguration even with play:false, which briefly
        // interrupts all other active pool players.  The caller opens the media
        // on the returned slot right before play(), outside this critical section.
        await candidate.player.pause();
        candidate.loadedUrl = null;
        candidate.isActive = true;
      } catch (_) {
        // Revert reservation so the slot becomes eligible again.
        candidate.ownerKey = null;
        candidate.loadedUrl = null;
        candidate.isActive = false;
        candidate.isPendingAcquire = false;
        return null;
      }

      candidate.isPendingAcquire = false;
      return candidate;
    });
  }

  /// Returns whether the slot for [key] currently has [url] opened on its
  /// player.  Used by [FeedVideoPlayer] to skip a redundant [Player.open]
  /// call when the slot already has the correct media loaded.
  bool isMediaLoaded(String key, String url) {
    for (final slot in _slots) {
      if (slot.ownerKey == key) {
        return slot.loadedUrl == url;
      }
    }
    return false;
  }

  /// Records that [url] has been successfully opened on the slot for [key].
  /// Called by [FeedVideoPlayer] after a successful [Player.open] so the pool
  /// can skip the open on fast-path re-acquisitions.
  void markMediaLoaded(String key, String url) {
    for (final slot in _slots) {
      if (slot.ownerKey == key) {
        slot.loadedUrl = url;
        return;
      }
    }
  }

  /// Marks the slot owned by [key] as inactive.
  ///
  /// The player is kept alive and the slot remains associated with [key] for
  /// fast re-acquisition when the widget scrolls back into view.  The caller
  /// is responsible for pausing the player before calling release.
  void release(String key) {
    for (final slot in _slots) {
      if (slot.ownerKey == key) {
        slot.isActive = false;
        slot.lastUsedAt = DateTime.now();
        return;
      }
    }
  }

  /// Pauses all pool players (e.g. when the fullscreen player opens).
  Future<void> pauseAll() async {
    for (final slot in _slots) {
      try {
        await slot.player.pause();
      } catch (_) {
        // Ignore pause races.
      }
    }
  }

  /// Disposes all pool players. Should be called once on app shutdown.
  Future<void> dispose() async {
    _disposed = true;
    for (final slot in _slots) {
      try {
        await slot.player.dispose();
      } catch (_) {
        // Ignore dispose races.
      }
    }
    _slots.clear();
  }
}
