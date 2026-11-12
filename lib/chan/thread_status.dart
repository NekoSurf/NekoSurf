import 'package:flutter_chan/chan/api.dart';
import 'package:flutter_chan/chan/load_errors.dart';
import 'package:flutter_chan/chan/post.dart';

enum ThreadStatus { deleted, archived, online }

/// A thread's status and, when known, its current counts and opening post.
typedef ThreadCheck = ({
  ThreadStatus status,
  int? replies,
  int? images,
  Post? op,
});

class _BoardSnapshot {
  _BoardSnapshot(this.live, this.archived);

  final Map<int, Post> live;

  /// Null when the board has no archive (or it couldn't be loaded).
  final Set<int>? archived;
}

const Duration _snapshotTtl = Duration(minutes: 2);
final Map<String, (DateTime, Future<_BoardSnapshot>)> _snapshots = {};

/// One catalog (plus one archive list) per board answers the status of every
/// bookmarked or recently visited thread on it, instead of downloading each
/// thread's full JSON. Concurrent callers share the same request.
Future<_BoardSnapshot> _boardSnapshot(String board, {bool force = false}) {
  // A forced refresh still shares a request made moments ago, so the many
  // threads of one board checked together hit the network once.
  final cached = _snapshots[board];
  final Duration maxAge = force ? const Duration(seconds: 5) : _snapshotTtl;
  if (cached != null && DateTime.now().difference(cached.$1) < maxAge) {
    return cached.$2;
  }

  final Future<_BoardSnapshot> future = () async {
    final List<Post> catalog = await fetchCatalog(board);
    final List<int>? archived = await fetchArchive(
      board,
    ).then<List<int>?>((threads) => threads).catchError((_) => null);
    return _BoardSnapshot({
      for (final Post op in catalog) op.no: op,
    }, archived?.toSet());
  }();
  _snapshots[board] = (DateTime.now(), future);
  future.catchError((Object _) {
    if (identical(_snapshots[board]?.$2, future)) {
      _snapshots.remove(board);
    }
    return _BoardSnapshot(const {}, null);
  });
  return future;
}

/// What's become of [thread]; null if that can't be told right now, which says
/// nothing about the thread.
///
/// The board's catalog and archive list answer most of these together. With
/// [exact], the thread itself is asked whenever they don't settle it, for an
/// archived thread's final counts too, which is one request per thread.
Future<ThreadCheck?> checkThread(
  String board,
  int thread, {
  bool force = false,
  bool exact = false,
}) async {
  try {
    final _BoardSnapshot snapshot = await _boardSnapshot(board, force: force);
    final Post? op = snapshot.live[thread];
    if (op != null) {
      return (
        status: ThreadStatus.online,
        replies: op.replies,
        images: op.images,
        op: op,
      );
    }
    if (!exact && (snapshot.archived?.contains(thread) ?? false)) {
      return (
        status: ThreadStatus.archived,
        replies: null,
        images: null,
        op: null,
      );
    }
  } catch (_) {
    if (!exact) {
      return null;
    }
  }

  // Deleted, newer than the snapshot, or archived after the archive list was
  // fetched: only the thread itself can tell.
  try {
    final Post op = (await fetchThread(board, thread)).first;
    return (
      status: op.archived == 1 ? ThreadStatus.archived : ThreadStatus.online,
      replies: op.replies,
      images: op.images,
      op: op,
    );
  } on ThreadNotFound {
    return (
      status: ThreadStatus.deleted,
      replies: null,
      images: null,
      op: null,
    );
  } catch (_) {
    return null;
  }
}
