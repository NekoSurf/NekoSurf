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

/// A thread saved for offline: its text, and its images and videos, each
/// with its thumbnail, all in a folder of its own.
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
    this.unfinished = false,
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
    unfinished: json['unfinished'] as bool? ?? false,
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

  /// Whether saving it was cut short, as when the app was closed meanwhile:
  /// it carries on at the next launch.
  final bool unfinished;

  String get key => '$board/$no';

  /// How many images and videos it has, without their thumbnails.
  int get mediaCount =>
      files.values.toSet().where((name) => !name.endsWith('s.jpg')).length;

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
    if (unfinished) 'unfinished': true,
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

  /// The thread's text, as [encodeThreadCopy] writes it.
  static const String _text = 'posts.json';

  final Map<String, OfflineThread> _threads = <String, OfflineThread>{};

  /// Every saved file's path, by its address on 4chan.
  final Map<String, String> _paths = <String, String>{};

  /// Every saved file's path, by its name (`<tim>.jpg`, `<tim>s.jpg`), which
  /// is the same on 4chan and the archives: a thread read from an archive
  /// finds the files saved from 4chan, and the other way round.
  final Map<String, String> _byName = <String, String>{};

  static String _nameOf(String url) =>
      Uri.tryParse(url)?.pathSegments.lastOrNull ?? url;

  /// How far along each thread being saved is, from 0 to 1.
  final Map<String, double> _saving = <String, double>{};

  /// Newest first.
  List<OfflineThread> get threads =>
      _threads.values.toList()..sort((a, b) => b.savedAt.compareTo(a.savedAt));

  /// What every saved thread takes up.
  int get bytes => bytesOf(_threads.values);

  /// What [threads] take up.
  static int bytesOf(Iterable<OfflineThread> threads) =>
      threads.fold(0, (int sum, OfflineThread t) => sum + t.bytes);

  static String keyOf(String board, int no) => '$board/$no';

  OfflineThread? thread(String board, int no) => _threads[keyOf(board, no)];

  bool isSaved(String board, int no) => _threads.containsKey(keyOf(board, no));

  /// How far along saving [board]'s [no] is, from 0 to 1, while it's saved.
  double? savingProgress(String board, int no) => _saving[keyOf(board, no)];

  /// The threads being saved now (`board/number`), listed or not yet.
  Iterable<String> get savingKeys => _saving.keys;

  /// The saved copy of what's at [url], on 4chan or an archive, if a saved
  /// thread has it.
  File? fileFor(String url) {
    final String? path = _paths[url] ?? _byName[_nameOf(url)];
    return path == null ? null : File(path);
  }

  /// Whether some file of [posts] isn't saved yet, as for new posts in a
  /// thread saved before they came.
  bool lacksFilesOf(List<Post> posts) => posts.any(
    (Post post) =>
        post.hasFile &&
        (fileFor(post.fileUrl) == null || fileFor(post.thumbnailUrl) == null),
  );

  /// The text of [board]'s [no] as it was last saved; null if there's none,
  /// as for a thread saved before the text was kept with it.
  Future<ThreadCopy?> text(String board, int no) async {
    try {
      final File file = File('${(await _folderOf(board, no)).path}/$_text');
      if (!await file.exists()) {
        return null;
      }
      return await compute(decodeThreadCopy, (
        body: await file.readAsString(),
        board: board,
      ));
    } catch (e) {
      debugPrint('Could not read the text saved for offline: $e');
      return null;
    }
  }

  Future<Directory> _folderOf(String board, int no) async =>
      Directory('${(await _root()).path}/${board}_$no');

  /// Whether what was saved before has been read ([load]): until then, which
  /// threads are saved isn't known.
  bool get isLoaded => _loaded;
  bool _loaded = false;

  /// Reads what was saved before, and carries on with saves cut short.
  /// Meant for launch.
  Future<void> load() async {
    try {
      await _read();
      _loaded = true;
    } catch (e) {
      debugPrint('Could not read the threads saved for offline: $e');
    }
    notifyListeners();
    for (final OfflineThread thread in threads) {
      if (thread.unfinished) {
        unawaited(_resume(thread));
      }
    }
  }

  Future<void> _resume(OfflineThread thread) async {
    final ThreadCopy? saved = await text(thread.board, thread.no);
    if (saved != null && saved.posts.isNotEmpty) {
      await save(saved.posts, copiedAt: saved.savedAt, source: saved.source);
    }
  }

  /// Folders without a list of what's in them are left alone this long:
  /// a save may be starting there.
  static const Duration _unlistedGrace = Duration(days: 1);

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
      if (!await manifest.exists()) {
        // A save that never got as far as its first files, long ago.
        final bool saving = _saving.keys.any(
          (key) => entity.path.endsWith('/${key.replaceFirst('/', '_')}'),
        );
        final DateTime changed = (await entity.stat()).modified;
        if (!saving && DateTime.now().difference(changed) > _unlistedGrace) {
          await entity.delete(recursive: true);
        }
        continue;
      }
      try {
        final OfflineThread thread = OfflineThread.fromJson(
          json.decode(await manifest.readAsString()) as Map<String, dynamic>,
        );
        if (_threads.containsKey(thread.key) ||
            _saving.containsKey(thread.key)) {
          continue;
        }
        _add(thread, entity);
      } catch (e) {
        // Kept as it is, files and all: maybe a later version can read it.
        debugPrint('Could not read ${manifest.path}: $e');
      }
    }
  }

  void _add(OfflineThread thread, Directory folder) {
    final OfflineThread? before = _threads[thread.key];
    if (before != null) {
      _forget(before);
    }
    _threads[thread.key] = thread;
    for (final MapEntry<String, String> file in thread.files.entries) {
      final String path = '${folder.path}/${file.value}';
      _paths[file.key] = path;
      _byName[file.value] = path;
    }
  }

  void _forget(OfflineThread thread) {
    final String folder = '/${thread.board}_${thread.no}/';
    for (final MapEntry<String, String> file in thread.files.entries) {
      if (_paths[file.key]?.contains(folder) ?? false) {
        _paths.remove(file.key);
      }
      if (_byName[file.value]?.contains(folder) ?? false) {
        _byName.remove(file.value);
      }
    }
  }

  void _drop(String key) {
    final OfflineThread? thread = _threads.remove(key);
    if (thread != null) {
      _forget(thread);
    }
  }

  /// Saves the thread [posts] make up for offline: its text, and each image
  /// and video with its thumbnail. Saved again, it adds what's new, tries
  /// what failed before and lets go of the files of posts no longer there.
  /// What's seen already is copied from the caches. [posts] loaded at
  /// [copiedAt], from the archive named [source], are kept as such.
  Future<OfflineSaveResult> save(
    List<Post> posts, {
    DateTime? copiedAt,
    String? source,
  }) async {
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
      return await _save(op, posts, copiedAt: copiedAt, source: source);
    } finally {
      _saving.remove(key);
      notifyListeners();
    }
  }

  Future<OfflineSaveResult> _save(
    Post op,
    List<Post> posts, {
    DateTime? copiedAt,
    String? source,
  }) async {
    final String key = keyOf(op.board, op.no);
    final DateTime savedAt = copiedAt ?? DateTime.now();
    unawaited(
      ThreadCopies.instance.keep(
        op.board,
        op.no,
        posts,
        savedAt: savedAt,
        source: source,
      ),
    );
    final Directory folder = await _folderOf(op.board, op.no);
    await folder.create(recursive: true);
    await _writeText(folder, (posts: posts, savedAt: savedAt, source: source));

    final List<String> urls = <String>[
      for (final Post post in posts)
        if (post.hasFile) ...[post.fileUrl, post.thumbnailUrl],
    ];
    final Set<String> wanted = urls.map(_nameOf).toSet();
    final Map<String, String> files = <String, String>{
      for (final MapEntry<String, String> file
          in (_threads[key]?.files ?? const <String, String>{}).entries)
        if (wanted.contains(file.value) &&
            File('${folder.path}/${file.value}').existsSync())
          file.key: file.value,
    };
    // Files of posts no longer in the thread go with them.
    for (final String name
        in (_threads[key]?.files.values ?? const <String>[]).toSet()) {
      if (!wanted.contains(name)) {
        try {
          await File('${folder.path}/$name').delete();
        } catch (_) {}
      }
    }
    // The same file from another server (4chan, an archive) is there once.
    final Set<String> here = files.values.toSet();
    final List<String> left = <String>[];
    for (final String url in urls) {
      if (files.containsKey(url)) {
        continue;
      }
      if (here.contains(_nameOf(url))) {
        files[url] = _nameOf(url);
      } else {
        left.add(url);
      }
    }

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
        // Every so often, so what's saved isn't lost if the app is closed;
        // what's left is fetched at the next launch, if it's closed.
        if (done % 10 == 0) {
          await _write(
            op,
            folder,
            files,
            failed: failed + left.length + partly.length,
            unfinished: true,
          );
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

  Future<void> _writeText(Directory folder, ThreadCopy text) async {
    try {
      final String encoded = await compute(encodeThreadCopy, text);
      final File file = File('${folder.path}/$_text');
      final File partial = File('${file.path}.part');
      await partial.writeAsString(encoded, flush: true);
      await partial.rename(file.path);
    } catch (e) {
      debugPrint('Could not keep the text saved for offline: $e');
    }
  }

  Future<void> _write(
    Post op,
    Directory folder,
    Map<String, String> files, {
    required int failed,
    bool unfinished = false,
  }) async {
    int bytes = 0;
    for (final String name in files.values.toSet()) {
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
      unfinished: unfinished,
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

  /// Deletes every thread saved for offline that [where] picks (all if it's
  /// left out), but ones being saved now.
  Future<void> removeAll({bool Function(OfflineThread thread)? where}) async {
    for (final OfflineThread thread in threads) {
      if (!_saving.containsKey(thread.key) && (where?.call(thread) ?? true)) {
        await remove(thread.board, thread.no);
      }
    }
  }
}
