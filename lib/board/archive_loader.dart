import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_chan/chan/api.dart';
import 'package:flutter_chan/chan/post.dart';

/// Loads archived threads' opening posts one at a time, at most one request
/// per second as 4chan's API rules ask.
///
/// Rows [want] their thread when they're built and [unwant] it when they're
/// scrolled away, so the queue only ever holds what's on (or near) the
/// screen. Loaded posts stay cached for as long as the loader lives.
class ArchivePreviewLoader extends ChangeNotifier {
  ArchivePreviewLoader(this._board);

  final String _board;

  static const Duration _spacing = Duration(seconds: 1);

  final Map<int, Post> _loaded = <int, Post>{};
  final Set<int> _failed = <int>{};
  final List<int> _queue = <int>[];
  bool _running = false;
  bool _disposed = false;

  Post? post(int no) => _loaded[no];

  /// Gone from 4chan (archives are pruned) or failed to load.
  bool hasFailed(int no) => _failed.contains(no);

  Iterable<Post> get loadedPosts => _loaded.values;

  void want(int no) {
    if (_loaded.containsKey(no) ||
        _failed.contains(no) ||
        _queue.contains(no)) {
      return;
    }
    _queue.add(no);
    unawaited(_pump());
  }

  void unwant(int no) {
    _queue.remove(no);
  }

  void retry(int no) {
    if (_failed.remove(no)) {
      notifyListeners();
      want(no);
    }
  }

  Future<void> _pump() async {
    if (_running) {
      return;
    }
    _running = true;

    try {
      // First in, first out: rows are built top to bottom, and rows that
      // scrolled away have already withdrawn their request.
      while (_queue.isNotEmpty && !_disposed) {
        final int no = _queue.removeAt(0);
        final Stopwatch elapsed = Stopwatch()..start();

        try {
          final List<Post> posts = await fetchThread(_board, no);
          if (posts.isEmpty) {
            _failed.add(no);
          } else {
            _loaded[no] = posts.first;
          }
        } catch (_) {
          _failed.add(no);
        }

        if (_disposed) {
          return;
        }
        notifyListeners();

        final Duration wait = _spacing - elapsed.elapsed;
        if (wait > Duration.zero) {
          await Future<void>.delayed(wait);
        }
      }
    } finally {
      _running = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _queue.clear();
    super.dispose();
  }
}
