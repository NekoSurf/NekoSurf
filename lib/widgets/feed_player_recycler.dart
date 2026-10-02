import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class RecycledPlayer {
  RecycledPlayer(this.player, this.controller);

  final Player player;
  final VideoController controller;
}

/// Reuses released players for the next video instead of disposing them,
/// so preload-window shifts don't pay the native `Player()` constructor cost.
class FeedPlayerRecycler {
  FeedPlayerRecycler({this.maxIdle = 4}) {
    for (int i = 0; i < maxIdle; i++) {
      _idle.add(_create());
    }
  }

  final int maxIdle;
  final List<RecycledPlayer> _idle = <RecycledPlayer>[];
  final Set<RecycledPlayer> _leased = <RecycledPlayer>{};
  bool _disposed = false;

  RecycledPlayer acquire() {
    final RecycledPlayer entry = _idle.isNotEmpty
        ? _idle.removeLast()
        : _create();
    if (!_disposed) {
      _leased.add(entry);
    }
    return entry;
  }

  Future<void> release(RecycledPlayer entry) async {
    if (!_leased.remove(entry) && !_disposed) {
      return;
    }

    if (_disposed || _idle.length >= maxIdle) {
      await _dispose(entry);
      return;
    }

    // Don't stop(): it invalidates VideoController's notifiers for the next owner.
    try {
      await entry.player.pause();
    } catch (_) {}

    if (_disposed) {
      await _dispose(entry);
      return;
    }
    _idle.add(entry);
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;

    final List<RecycledPlayer> idle = List<RecycledPlayer>.of(_idle);
    _idle.clear();
    _leased.clear();
    await Future.wait(idle.map(_dispose));
  }

  RecycledPlayer _create() {
    final Player player = Player();
    return RecycledPlayer(player, VideoController(player));
  }

  Future<void> _dispose(RecycledPlayer entry) async {
    try {
      await entry.player.dispose();
    } catch (_) {}
  }
}
