import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/history/thread_copies.dart';
import 'package:flutter_chan/media/image_cache.dart';
import 'package:flutter_chan/media/video_server.dart';
import 'package:flutter_chan/saved/downloads.dart';
import 'package:path_provider/path_provider.dart';

/// A thread saved for offline: its images and videos, each with its
/// thumbnail. Its text is the copy [ThreadCopies] keeps of it.
class OfflineThread {
  OfflineThread({
    required this.board,
    required this.no,
    required this.title,
    required this.savedAt,
    required this.files,
    required this.bytes,
    required this.missing,
    this.com,
    this.thumbnailName,
  });

  factory OfflineThread.fromJson(Map<String, dynamic> json) => OfflineThread(
    board: json['board'] as String,
    no: json['no'] as int,
    title: json['title'] as String? ?? '',
    com: json['com'] as String?,
    thumbnailName: json['thumb'] as String?,
    savedAt: DateTime.fromMillisecondsSinceEpoch(json['saved'] as int),
    files: (json['files'] as Map<String, dynamic>).cast<String, String>(),
    bytes: json['bytes'] as int? ?? 0,
    missing: json['missing'] as int? ?? 0,
  );

  final String board;
  final int no;
  final String title;
  final String? com;

  /// The opening post's thumbnail, to show the thread in a list.
  final String? thumbnailName;
  final DateTime savedAt;

  /// Each file's name in the thread's folder, by its address on 4chan.
  final Map<String, String> files;

  /// What the files take up.
  final int bytes;

  /// How many files couldn't be downloaded the last time it was saved.
  final int missing;

  String get key => '$board/$no';

  /// How many images and videos it has, without their thumbnails.
  int get mediaCount =>
      files.keys.where((url) => !url.endsWith('s.jpg')).length;

  /// What's known of the thread's opening post.
  Post toPost() => Post.remembered(
    board: board,
    no: no,
    sub: title.isEmpty ? null : title,
    com: com,
    thumbnailName: thumbnailName,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'board': board,
    'no': no,
    'title': title,
    'com': com,
    'thumb': thumbnailName,
    'saved': savedAt.millisecondsSinceEpoch,
    'files': files,
    'bytes': bytes,
    'missing': missing,
  };
}

/// What saving a thread for offline came to.
typedef OfflineSaveResult = ({int saved, int failed});

/// The threads saved for offline, kept in a folder each until they're
/// removed, so they open with their images and videos without a connection.
/// Images and videos are looked up here first ([fileFor]).
class OfflineThreads extends ChangeNotifier {
  @visibleForTesting
  OfflineThreads(this._root);

  /// The app's; tests make their own.
  static OfflineThreads instance = OfflineThreads(
    () async => Directory(
      '${(await getApplicationSupportDirectory()).path}/offline_threads',
    ),
  );

  final Future<Directory> Function() _root;

  /// Files being downloaded at once.
  static const int _parallel = 2;

  static const String _manifest = 'thread.json';

  final Map<String, OfflineThread> _threads = <String, OfflineThread>{};

  /// Every saved file's path, by its address on 4chan.
  final Map<String, String> _paths = <String, String>{};

  /// How far along each thread being saved is, from 0 to 1.
  final Map<String, double> _saving = <String, double>{};

  /// Newest first.
  List<OfflineThread> get threads =>
      _threads.values.toList()..sort((a, b) => b.savedAt.compareTo(a.savedAt));

  /// What every saved thread takes up.
  int get bytes => _threads.values.fold(0, (int sum, t) => sum + t.bytes);

  static String keyOf(String board, int no) => '$board/$no';

  OfflineThread? thread(String board, int no) => _threads[keyOf(board, no)];

  bool isSaved(String board, int no) => _threads.containsKey(keyOf(board, no));

  /// How far along saving [board]'s [no] is, from 0 to 1, while it's saved.
  double? savingProgress(String board, int no) => _saving[keyOf(board, no)];

  /// The saved copy of what's at [url] on 4chan, if a saved thread has it.
  File? fileFor(String url) {
    final String? path = _paths[url];
    return path == null ? null : File(path);
  }

  Future<Directory> _folderOf(String board, int no) async =>
      Directory('${(await _root()).path}/${board}_$no');

  /// Whether what was saved before has been read ([load]): until then, which
  /// threads are saved isn't known.
  bool get isLoaded => _loaded;
  bool _loaded = false;

  /// Reads what was saved before. Meant for launch.
  Future<void> load() async {
    try {
      await _read();
      _loaded = true;
    } catch (e) {
      debugPrint('Could not read the threads saved for offline: $e');
    }
    notifyListeners();
  }

  Future<void> _read() async {
    final Directory root = await _root();
    if (!await root.exists()) {
      return;
    }
    await for (final FileSystemEntity entity in root.list()) {
      if (entity is! Directory) {
        continue;
      }
      final File manifest = File('${entity.path}/$_manifest');
      try {
        final OfflineThread thread = OfflineThread.fromJson(
          json.decode(await manifest.readAsString()) as Map<String, dynamic>,
        );
        if (_threads.containsKey(thread.key) ||
            _saving.containsKey(thread.key)) {
          continue;
        }
        _add(thread, entity);
      } catch (_) {
        // A save that never got as far as its first files.
        if (!_saving.keys.any(
          (key) => entity.path.endsWith('/${key.replaceFirst('/', '_')}'),
        )) {
          await entity.delete(recursive: true);
        }
      }
    }
  }

  void _add(OfflineThread thread, Directory folder) {
    _threads[thread.key] = thread;
    for (final MapEntry<String, String> file in thread.files.entries) {
      _paths[file.key] = '${folder.path}/${file.value}';
    }
  }

  void _drop(String key) {
    final OfflineThread? thread = _threads.remove(key);
    if (thread != null) {
      thread.files.keys.forEach(_paths.remove);
    }
  }

  /// Saves the thread [posts] make up for offline: its text, and each image
  /// and video with its thumbnail. Saved again, it adds what's new and tries
  /// what failed before. What's seen already is copied from the caches.
  Future<OfflineSaveResult> save(List<Post> posts) async {
    if (posts.isEmpty) {
      return (saved: 0, failed: 0);
    }
    final Post op = posts.first;
    final String key = keyOf(op.board, op.no);
    if (_saving.containsKey(key)) {
      return (saved: 0, failed: 0);
    }
    _saving[key] = 0;
    notifyListeners();
    try {
      return await _save(op, posts);
    } finally {
      _saving.remove(key);
      notifyListeners();
    }
  }

  Future<OfflineSaveResult> _save(Post op, List<Post> posts) async {
    final String key = keyOf(op.board, op.no);
    unawaited(ThreadCopies.instance.keep(op.board, op.no, posts));
    final Directory folder = await _folderOf(op.board, op.no);
    await folder.create(recursive: true);

    final List<String> urls = <String>[
      for (final Post post in posts)
        if (post.hasFile) ...[post.fileUrl, post.thumbnailUrl],
    ];
    final Map<String, String> files = <String, String>{
      for (final MapEntry<String, String> file
          in (_threads[key]?.files ?? const <String, String>{}).entries)
        if (File('${folder.path}/${file.value}').existsSync())
          file.key: file.value,
    };
    final List<String> left = <String>[
      for (final String url in urls)
        if (!files.containsKey(url)) url,
    ];

    int failed = 0;
    int done = urls.length - left.length;
    // How far along each file being downloaded is.
    final Map<String, double> partly = <String, double>{};
    void report() {
      if (!_saving.containsKey(key)) {
        return;
      }
      final double progress = urls.isEmpty
          ? 1
          : (done + partly.values.fold(0.0, (a, b) => a + b)) / urls.length;
      final double whole = (progress.clamp(0, 1) * 100).floor() / 100;
      if (whole != _saving[key]) {
        _saving[key] = whole;
        notifyListeners();
      }
    }

    Future<void> worker() async {
      while (left.isNotEmpty) {
        final String url = left.removeAt(0);
        final String name = Uri.parse(url).pathSegments.last;
        final File file = File('${folder.path}/$name');
        try {
          final File? cached =
              await VideoServer.instance.cachedFile(url) ??
              await cachedImageFile(url);
          if (cached != null &&
              cached.path != file.path &&
              cached.existsSync()) {
            await cached.copy(file.path);
          } else {
            await downloadFile(
              url,
              file,
              onProgress: (double? progress) {
                partly[url] = progress ?? 0;
                report();
              },
            );
          }
          files[url] = name;
          // Shows from here at once, like the rest once it's done.
          _paths[url] = file.path;
        } catch (e) {
          debugPrint('Could not save $url for offline: $e');
          failed++;
        }
        partly.remove(url);
        done++;
        report();
        // Every so often, so what's saved isn't lost if the app is closed.
        if (done % 10 == 0) {
          await _write(op, folder, files, failed: failed + left.length);
        }
      }
    }

    report();
    await Future.wait([
      for (int i = 0; i < min(_parallel, max(1, left.length)); i++) worker(),
    ]);
    await _write(op, folder, files, failed: failed);
    return (saved: files.length, failed: failed);
  }

  Future<void> _write(
    Post op,
    Directory folder,
    Map<String, String> files, {
    required int failed,
  }) async {
    int bytes = 0;
    for (final String name in files.values) {
      try {
        bytes += await File('${folder.path}/$name').length();
      } catch (_) {}
    }
    final OfflineThread thread = OfflineThread(
      board: op.board,
      no: op.no,
      title: op.title,
      com: op.com,
      thumbnailName: op.thumbnailName,
      savedAt: DateTime.now(),
      files: Map<String, String>.of(files),
      bytes: bytes,
      missing: failed,
    );
    try {
      final File manifest = File('${folder.path}/$_manifest');
      final File partial = File('${manifest.path}.part');
      await partial.writeAsString(json.encode(thread.toJson()), flush: true);
      await partial.rename(manifest.path);
    } catch (e) {
      debugPrint('Could not note what was saved for offline: $e');
    }
    _add(thread, folder);
    notifyListeners();
  }

  /// Deletes [board]'s [no] and its files.
  Future<void> remove(String board, int no) async {
    _drop(keyOf(board, no));
    notifyListeners();
    try {
      final Directory folder = await _folderOf(board, no);
      if (await folder.exists()) {
        await folder.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Could not delete the thread saved for offline: $e');
    }
  }

  /// Deletes every thread saved for offline, but ones being saved now.
  Future<void> removeAll() async {
    for (final OfflineThread thread in threads) {
      if (!_saving.containsKey(thread.key)) {
        await remove(thread.board, thread.no);
      }
    }
  }
}
