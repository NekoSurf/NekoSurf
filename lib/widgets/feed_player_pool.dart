import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// A pooled entry: a pre-created Player + VideoController that can be
/// lent to a FeedVideoPlayer for a specific source URL and returned when
/// the widget disposes or scrolls offscreen.
class _PoolEntry {
  _PoolEntry() {
    player = Player();
    controller = VideoController(player);
  }

  late final Player player;
  late final VideoController controller;

  /// The source URL this entry is currently lent for, or null if idle.
  String? lentSource;

  bool get isIdle => lentSource == null;
}

class FeedPlayerPoolLease {
  FeedPlayerPoolLease._({
    required this.player,
    required this.controller,
    required this.source,
    required FeedPlayerPool pool,
  }) : _pool = pool;

  final Player player;
  final VideoController controller;
  final String source;
  final FeedPlayerPool _pool;
  bool _returned = false;

  /// Return this lease to the pool. Safe to call multiple times.
  Future<void> release() async {
    if (_returned) {
      return;
    }
    _returned = true;
    await _pool._returnLease(this);
  }
}

/// Pre-creates [poolSize] media_kit Player instances and lends them
/// to callers by source URL. Reclaims them on [FeedPlayerPoolLease.release].
///
/// Leases are not re-used across different sources without a full stop/open
/// cycle – the pool only eliminates the ~50-100ms `Player()` constructor
/// penalty.
class FeedPlayerPool {
  FeedPlayerPool({int poolSize = 6}) {
    for (int i = 0; i < poolSize; i++) {
      _entries.add(_PoolEntry());
    }
  }

  final List<_PoolEntry> _entries = [];
  bool _disposed = false;

  // ------------------------------------------------------------------
  // Public API
  // ------------------------------------------------------------------

  /// Attempt to acquire a pool slot for [source].
  ///
  /// Returns a lease if a slot is available, or null if all slots are
  /// currently lent out. The caller must always call [FeedPlayerPoolLease.release]
  /// when done.
  FeedPlayerPoolLease? acquire({required String source}) {
    if (_disposed) {
      return null;
    }

    // Find an idle slot.
    for (final entry in _entries) {
      if (entry.isIdle) {
        entry.lentSource = source;
        return FeedPlayerPoolLease._(
          player: entry.player,
          controller: entry.controller,
          source: source,
          pool: this,
        );
      }
    }

    return null;
  }

  /// Dispose all pool entries. Call once when the parent page is disposed.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;

    for (final entry in _entries) {
      try {
        await entry.player.pause();
        await entry.player.dispose();
      } catch (_) {}
    }
    _entries.clear();
  }

  // ------------------------------------------------------------------
  // Internal
  // ------------------------------------------------------------------

  Future<void> _returnLease(FeedPlayerPoolLease lease) async {
    if (_disposed) {
      return;
    }

    for (final entry in _entries) {
      if (entry.lentSource == lease.source && entry.player == lease.player) {
        entry.lentSource = null;
        // Pause and rewind so the next borrower starts from the beginning.
        // Do NOT call player.stop() — it invalidates VideoController's internal
        // ValueNotifiers (width/height), causing a "used after disposed" crash
        // when the next Video widget mounts and tries to subscribe to them.
        try {
          await entry.player.pause();
          await entry.player.seek(Duration.zero);
        } catch (_) {}
        return;
      }
    }
  }
}
