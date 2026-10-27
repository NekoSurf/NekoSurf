import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 4chan caps webms at a few MB, so a small demuxer cache still holds the
/// whole file; media_kit's default (32 MB ahead + 32 MB behind) per player
/// adds up fast with a dozen players alive.
const int _mediaBufferBytes = 8 * 1024 * 1024;

Player createMediaPlayer() {
  return Player(
    configuration: const PlayerConfiguration(bufferSize: _mediaBufferBytes),
  );
}

/// Whether [player]'s current playlist entry is [url].
bool playerHasMedia(Player player, String url) {
  final Playlist playlist = player.state.playlist;
  final int index = playlist.index;
  return index >= 0 &&
      index < playlist.medias.length &&
      playlist.medias[index].uri == url;
}

class RecycledPlayer {
  RecycledPlayer(this.player, this.controller);

  final Player player;
  final VideoController controller;
}

/// Reuses released players for the next video instead of disposing them,
/// so preload-window shifts don't pay the native `Player()` constructor cost.
///
/// Idle players keep their last video loaded (paused), which doubles as a
/// small in-memory cache: asking for a URL an idle player still holds hands
/// that player back, so reopening a video skips the download entirely.
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

  /// Prefers an idle player that already has [url] loaded; otherwise takes
  /// the least recently released one, keeping recent videos around longest.
  RecycledPlayer acquire({String? url}) {
    final int match = url == null
        ? -1
        : _idle.indexWhere((entry) => playerHasMedia(entry.player, url));
    final RecycledPlayer entry = match >= 0
        ? _idle.removeAt(match)
        : _idle.isNotEmpty
        ? _idle.removeAt(0)
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

    if (_disposed) {
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
    // Evict the oldest: the video just released is the likeliest to reopen.
    while (_idle.length > maxIdle) {
      unawaited(_dispose(_idle.removeAt(0)));
    }
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
    final Player player = createMediaPlayer();
    return RecycledPlayer(player, VideoController(player));
  }

  Future<void> _dispose(RecycledPlayer entry) async {
    try {
      await entry.player.dispose();
    } catch (_) {}
  }
}
