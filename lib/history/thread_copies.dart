import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_chan/bookmarks/bookmarks_model.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/history/history_model.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

/// A thread as it was when it last loaded.
typedef ThreadCopy = ({List<Post> posts, DateTime savedAt});

/// The last loaded copy of each bookmarked thread and each thread in the
/// history, so it can still be read without a connection, or once 4chan has
/// deleted it. Only text: images come from the image cache, if still there.
///
/// Copies go with the bookmark or history entry they belong to
/// ([keepOnly]), so forgetting history forgets them too.
class ThreadCopies {
  ThreadCopies(this._directory);

  /// The app's copies; tests put theirs somewhere else.
  static ThreadCopies instance = ThreadCopies(
    () async => Directory(
      '${(await getApplicationSupportDirectory()).path}/thread_copies',
    ),
  );

  final Future<Directory> Function() _directory;

  /// Writes of the same thread one after another, so an older one can't land
  /// last.
  final Map<String, Future<void>> _writing = <String, Future<void>>{};

  static String _fileName(String board, int thread) => '${board}_$thread.json';

  Future<File> _file(String board, int thread) async =>
      File('${(await _directory()).path}/${_fileName(board, thread)}');

  /// Keeps [posts] as [board]'s [thread], in place of the copy before.
  Future<void> keep(String board, int thread, List<Post> posts) {
    if (posts.isEmpty) {
      return Future<void>.value();
    }
    final String key = _fileName(board, thread);
    final Future<void> write = (_writing[key] ?? Future<void>.value()).then((
      _,
    ) async {
      try {
        final File file = await _file(board, thread);
        await file.parent.create(recursive: true);
        final String encoded = await compute(_encode, (
          posts: posts,
          savedAt: DateTime.now(),
        ));
        // Whole or not at all: a copy cut short can't be read.
        final File partial = File('${file.path}.part');
        await partial.writeAsString(encoded, flush: true);
        await partial.rename(file.path);
      } catch (e) {
        debugPrint('Could not keep a copy of the thread: $e');
      }
    });
    _writing[key] = write;
    unawaited(
      write.whenComplete(() {
        if (identical(_writing[key], write)) {
          _writing.remove(key);
        }
      }),
    );
    return write;
  }

  /// The copy of [board]'s [thread]; null if there's none.
  Future<ThreadCopy?> read(String board, int thread) async {
    try {
      await _writing[_fileName(board, thread)];
      final File file = await _file(board, thread);
      if (!await file.exists()) {
        return null;
      }
      return await compute(_decode, (
        body: await file.readAsString(),
        board: board,
      ));
    } catch (e) {
      debugPrint('Could not read the copy of the thread: $e');
      return null;
    }
  }

  /// Deletes the copies of all threads but [keys] (`board/number`).
  Future<void> keepOnly(Set<String> keys) async {
    try {
      final Directory dir = await _directory();
      if (!await dir.exists()) {
        return;
      }
      final Set<String> kept = <String>{
        for (final String key in keys) '${key.replaceFirst('/', '_')}.json',
      };
      await for (final FileSystemEntity entity in dir.list()) {
        final String name = entity.uri.pathSegments.last;
        // A copy being written is finished first, then goes with the rest.
        if (entity is File && name.endsWith('.json') && !kept.contains(name)) {
          await _writing[name];
          await entity.delete();
        }
      }
    } catch (e) {
      debugPrint('Could not tidy up the copies of threads: $e');
    }
  }
}

String _encode(ThreadCopy copy) => json.encode(<String, dynamic>{
  'saved': copy.savedAt.millisecondsSinceEpoch,
  'posts': <Map<String, dynamic>>[
    for (final Post post in copy.posts) post.toJson(),
  ],
});

ThreadCopy _decode(({String body, String board}) file) {
  final Map<String, dynamic> decoded =
      json.decode(file.body) as Map<String, dynamic>;
  return (
    posts: <Post>[
      for (final dynamic post in decoded['posts'] as List<dynamic>)
        Post.fromJson(post as Map<String, dynamic>, file.board),
    ],
    savedAt: DateTime.fromMillisecondsSinceEpoch(decoded['saved'] as int),
  );
}

/// Keeps [copies] to the threads that are bookmarked or in the history, now
/// and whenever either changes. Returns what stops it.
VoidCallback keepThreadCopiesOf(
  BookmarksProvider bookmarks,
  HistoryProvider history, {
  ThreadCopies? copies,
}) {
  final ThreadCopies kept = copies ?? ThreadCopies.instance;
  Timer? soon;
  Set<String>? last;

  void tidy() {
    final Set<String> keys = <String>{
      for (final bookmark in bookmarks.bookmarks) bookmark.key,
      for (final thread in history.threads) thread.key,
    };
    // History is told of every status check; only a change in what's kept
    // is worth a look at the folder.
    if (last != null && setEquals(last, keys)) {
      return;
    }
    last = keys;
    unawaited(kept.keepOnly(keys));
  }

  void changed() {
    soon?.cancel();
    // History cleared or forgotten on leaving the app: its copies go now,
    // before the app may be suspended.
    if (history.threads.isEmpty) {
      tidy();
    } else {
      soon = Timer(const Duration(seconds: 1), tidy);
    }
  }

  bookmarks.addListener(changed);
  history.addListener(changed);
  tidy();
  return () {
    soon?.cancel();
    bookmarks.removeListener(changed);
    history.removeListener(changed);
  };
}

/// Keeps the copies of threads to what's bookmarked or in the history, for as
/// long as [child] is there (see [keepThreadCopiesOf]).
class KeepThreadCopies extends StatefulWidget {
  const KeepThreadCopies({super.key, required this.child});

  final Widget child;

  @override
  State<KeepThreadCopies> createState() => _KeepThreadCopiesState();
}

class _KeepThreadCopiesState extends State<KeepThreadCopies> {
  late final VoidCallback _stop;

  @override
  void initState() {
    super.initState();
    _stop = keepThreadCopiesOf(
      context.read<BookmarksProvider>(),
      context.read<HistoryProvider>(),
    );
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
