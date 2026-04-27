import 'dart:io';

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

  static int get _poolSize => Platform.isIOS ? 3 : 4;

  final List<_PoolSlot> _slots = [];
  bool _initialized = false;
  bool _disposed = false;

  void _ensureInitialized() {
    if (_initialized || _disposed) return;
    _initialized = true;
    for (int i = 0; i < _poolSize; i++) {
      final player = Player();
      // PlaylistMode is a player-level property that persists across open()
      // calls, so setting it once here is sufficient.
      player.setPlaylistMode(PlaylistMode.loop);
      _slots.add(_PoolSlot(player: player, controller: VideoController(player)));
    }
  }

  /// Acquires a pool slot for [key] with [resolvedUrl] opened on the player.
  ///
  /// * If a slot already owns [key] with the same URL it is returned
  ///   immediately (no open() call needed).
  /// * Otherwise the LRU inactive slot is evicted, [resolvedUrl] is opened on
  ///   it, and it is returned.
  /// * Returns `null` when the pool is exhausted (all slots actively in use by
  ///   different widgets — very rare when pool size ≥ number of visible posts).
  Future<_PoolSlot?> acquire(String key, String resolvedUrl) async {
    _ensureInitialized();
    if (_disposed) return null;

    // Fast path: this key already owns a slot.
    for (final slot in _slots) {
      if (slot.ownerKey == key) {
        slot.isActive = true;
        slot.lastUsedAt = DateTime.now();
        if (slot.loadedUrl != resolvedUrl) {
          try {
            await slot.player.pause();
            await slot.player.open(Media(resolvedUrl), play: false);
            slot.loadedUrl = resolvedUrl;
          } catch (_) {
            // Ignore open races on URL change.
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
    // choosing the same one before our open() completes.
    candidate.ownerKey = key;
    candidate.isPendingAcquire = true;
    candidate.lastUsedAt = DateTime.now();

    try {
      await candidate.player.pause();
      await candidate.player.open(Media(resolvedUrl), play: false);
      candidate.loadedUrl = resolvedUrl;
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
