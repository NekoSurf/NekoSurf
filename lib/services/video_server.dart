import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_chan/API/http_client.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Serves videos to mpv from a local HTTP server while it caches them.
///
/// mpv opens `http://127.0.0.1:<port>/<id>` and gets bytes as soon as they
/// arrive from 4chan, so playback starts right away instead of after the
/// download, while the same download fills a file on disk. Once that file
/// is complete, videos play from it directly: a video seen before starts
/// instantly and never downloads twice. Preloading starts the download
/// without a player.
///
/// The download goes where the player reads: scrubbing past what has
/// arrived moves it there, and what it skipped is filled in after.
///
/// Videos someone is watching ([watch]) download first. Every other
/// download (preloads, and videos scrolled away from or covered by the
/// fullscreen viewer) is held while a watched one is still arriving, then
/// continues in the background, two at a time: on a slow connection the
/// video on screen gets all of it instead of a sixth.
///
/// A dropped download continues from where it stopped (HTTP ranges), with
/// a longer back-off when 4chan's image server rate-limits (429).
class VideoServer {
  VideoServer._() {
    // iOS may close listening sockets in the background, and no player
    // exists then anyway (VideoPlayers); open a fresh one on next use.
    AppLifecycleListener(onHide: _closeServer);
  }

  /// Caches into [dir], without following the app's lifecycle.
  @visibleForTesting
  VideoServer.forTesting(Directory dir) : _dir = Future<Directory>.value(dir);

  static final VideoServer instance = VideoServer._();

  static const int defaultMaxCacheBytes = 300 * 1024 * 1024;

  /// Beyond this, the least recently watched videos are deleted.
  int _maxCacheBytes = defaultMaxCacheBytes;

  /// Sets [_maxCacheBytes], deleting what's now beyond it.
  Future<void> setMaxCacheBytes(int bytes) async {
    if (bytes == _maxCacheBytes) {
      return;
    }
    _maxCacheBytes = bytes;
    await _pruneSoon();
  }

  // Downloads nobody watches, at once.
  static const int _maxBackground = 2;
  // Scrolling on queues new prefetches; the oldest are dropped.
  static const int _maxQueued = 6;

  final Map<String, _Download> _downloads = <String, _Download>{};
  final Map<String, String> _ids = <String, String>{};
  final Map<String, ValueNotifier<double?>> _progress =
      <String, ValueNotifier<double?>>{};
  final Map<String, ValueNotifier<List<(double, double)>>> _loaded =
      <String, ValueNotifier<List<(double, double)>>>{};
  final Set<String> _watched = <String>{};
  // Videos being saved or shared, waiting for their download; they go first
  // like watched ones. Counted, as one may be saved and shared at once.
  final Map<String, int> _awaited = <String, int>{};
  // Background downloads waiting their turn, next first.
  final List<_Download> _queued = <_Download>[];

  Future<HttpServer>? _server;
  Future<Directory>? _dir;

  /// Stops serving; for tests.
  @visibleForTesting
  void close() => _closeServer();

  /// What mpv should open for [url]: the cached file if it's complete,
  /// otherwise a local stream of the download, which starts now. [url]
  /// counts as watched from now on, until [unwatch].
  Future<String> source(String url) async {
    _watched.add(url);
    final File file = await _fileFor(url);
    if (file.existsSync() && !_downloads.containsKey(url)) {
      _progressOf(url).value = 1;
      _loadedOf(url).value = _all;
      _touch(file);
      return file.path;
    }

    final _Download download = _downloadFor(url, file);
    _schedule();
    final HttpServer server = await (_server ??= _openServer());
    return 'http://127.0.0.1:${server.port}/${download.id}';
  }

  /// [url] is on screen and playing (again): its download goes first.
  void watch(String url) {
    if (_watched.add(url)) {
      _schedule();
    }
  }

  /// Nobody watches [url] anymore: its download continues in the
  /// background, after the watched ones.
  void unwatch(String url) {
    if (_watched.remove(url)) {
      _schedule();
    }
  }

  /// Starts downloading [url] in the background, so it starts from disk.
  Future<void> prefetch(String url) async {
    final File file = await _fileFor(url);
    if (file.existsSync() || _downloads.containsKey(url)) {
      return;
    }
    _queued.add(_downloadFor(url, file));
    int waiting = _queued.where((download) => !download.started).length;
    for (int i = 0; waiting > _maxQueued && i < _queued.length;) {
      final _Download dropped = _queued[i];
      // Held downloads have their bytes on disk already; they stay.
      if (dropped.started) {
        i++;
        continue;
      }
      _queued.removeAt(i);
      waiting--;
      if (_downloads[dropped.url] == dropped) {
        _downloads.remove(dropped.url);
      }
    }
    _schedule();
  }

  /// How much of [url] has arrived, from 0 to 1; null while unknown.
  ValueListenable<double?> progressOf(String url) => _progressOf(url);

  /// Which parts of [url] have arrived, in order, as (start, end) fractions
  /// of its size: more than one after scrubbing ahead of the download.
  ValueListenable<List<(double, double)>> loadedOf(String url) =>
      _loadedOf(url);

  /// The finished copy of [url] on disk, if it's been watched to the end
  /// of its download; null otherwise (also while it's still arriving).
  Future<File?> cachedFile(String url) async {
    try {
      final File file = await _fileFor(url);
      if (file.existsSync() && !_downloads.containsKey(url)) {
        return file;
      }
    } catch (_) {}
    return null;
  }

  /// The finished copy of [url] on disk, waiting for its download to end
  /// if it's arriving now, so saving a video being watched doesn't fetch it
  /// a second time alongside the player. That download goes first while
  /// this waits, and [onProgress] hears how much of it has arrived (0 to 1,
  /// or null while unknown). Null if it isn't cached or downloading, or its
  /// download failed.
  Future<File?> downloadedFile(
    String url, {
    void Function(double? progress)? onProgress,
  }) async {
    final _Download? download = _downloads[url];
    if (download == null) {
      return cachedFile(url);
    }
    _awaited.update(url, (int n) => n + 1, ifAbsent: () => 1);
    _schedule();
    final ValueNotifier<double?> progress = _progressOf(url);
    void report() => onProgress?.call(progress.value);
    progress.addListener(report);
    report();
    try {
      await download.done;
    } finally {
      progress.removeListener(report);
      final int left = _awaited[url]! - 1;
      if (left == 0) {
        _awaited.remove(url);
      } else {
        _awaited[url] = left;
      }
      _schedule();
    }
    if (download.failed) {
      return null;
    }
    return cachedFile(url);
  }

  /// Forgets [url]'s cached copy (e.g. one that wouldn't play), so it's
  /// downloaded again next time.
  Future<void> evict(String url) async {
    final _Download? download = _downloads.remove(url);
    if (download != null) {
      _queued.remove(download);
      download.cancel();
      _schedule();
    }
    _progressOf(url).value = null;
    _loadedOf(url).value = const <(double, double)>[];
    try {
      final File file = await _fileFor(url);
      if (file.existsSync()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// How much the finished videos on disk take up, in bytes.
  Future<int> cacheSize() async {
    try {
      final Directory dir = await (_dir ??= _openDir());
      int total = 0;
      for (final File file in dir.listSync().whereType<File>()) {
        if (!file.path.endsWith('.part')) {
          total += file.lengthSync();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Deletes every finished video; ones downloading now carry on. A video
  /// playing from disk keeps playing (its open file outlives the delete).
  Future<void> clearCache() async {
    try {
      final Directory dir = await (_dir ??= _openDir());
      for (final File file in dir.listSync().whereType<File>()) {
        if (!file.path.endsWith('.part')) {
          await file.delete();
        }
      }
    } catch (_) {}
    for (final MapEntry<String, ValueNotifier<double?>> entry
        in _progress.entries) {
      if (!_downloads.containsKey(entry.key)) {
        entry.value.value = null;
        _loadedOf(entry.key).value = const <(double, double)>[];
      }
    }
  }

  _Download _downloadFor(String url, File file) {
    return _downloads.putIfAbsent(url, () {
      final String id = _ids[url] ??= '${_ids.length}';
      return _Download(
        id: id,
        url: url,
        file: file,
        progress: _progressOf(url),
        loaded: _loadedOf(url),
        onDone: (_Download download) {
          if (_downloads[url] == download) {
            _downloads.remove(url);
          }
          _queued.remove(download);
          if (!download.failed) {
            unawaited(_pruneSoon());
          }
          _schedule();
        },
      );
    });
  }

  bool _isWatched(String url) =>
      _watched.contains(url) || _awaited.containsKey(url);

  /// Runs the watched downloads; holds the others while one of those is
  /// still arriving, and otherwise runs [_maxBackground] of them.
  void _schedule() {
    final bool watching = _downloads.keys.any(_isWatched);
    int background = 0;
    for (final _Download download in _downloads.values) {
      if (_isWatched(download.url)) {
        _queued.remove(download);
        download.start();
      } else if (download.active) {
        if (watching || background >= _maxBackground) {
          download.hold();
          // Its bytes are on disk already: it continues first.
          _queued.insert(0, download);
        } else {
          background++;
        }
      }
    }
    if (watching) {
      return;
    }
    while (background < _maxBackground && _queued.isNotEmpty) {
      final _Download next = _queued.removeAt(0);
      if (_downloads[next.url] == next) {
        next.start();
        background++;
      }
    }
  }

  ValueNotifier<double?> _progressOf(String url) =>
      _progress.putIfAbsent(url, () => ValueNotifier<double?>(null));

  static const List<(double, double)> _all = <(double, double)>[(0, 1)];

  ValueNotifier<List<(double, double)>> _loadedOf(String url) => _loaded
      .putIfAbsent(url, () => ValueNotifier<List<(double, double)>>(const []));

  void _touch(File file) {
    try {
      // Pruning goes by age; keep what's still being watched.
      file.setLastModifiedSync(DateTime.now());
    } catch (_) {}
  }

  // ---------------------------
  // Files
  // ---------------------------

  Future<File> _fileFor(String url) async {
    final Directory dir = await (_dir ??= _openDir());
    return File('${dir.path}/${Uri.parse(url).pathSegments.join('_')}');
  }

  Future<Directory> _openDir() async {
    final Directory temp = await getTemporaryDirectory();
    final Directory dir = Directory('${temp.path}/video_cache');
    await dir.create(recursive: true);
    unawaited(_prune(dir, leftovers: true));
    return dir;
  }

  Future<void> _pruneSoon() async {
    final Future<Directory>? dir = _dir;
    if (dir != null) {
      await _prune(await dir);
    }
  }

  /// Deletes the least recently watched videos beyond [_maxCacheBytes], and
  /// with [leftovers], what downloads that never finished left behind.
  Future<void> _prune(Directory dir, {bool leftovers = false}) async {
    try {
      final List<File> files = <File>[];
      for (final File file in dir.listSync().whereType<File>()) {
        if (file.path.endsWith('.part')) {
          if (leftovers) {
            await file.delete();
          }
        } else {
          files.add(file);
        }
      }
      final Map<File, FileStat> stats = {
        for (final File file in files) file: file.statSync(),
      };
      files.sort((a, b) => stats[a]!.modified.compareTo(stats[b]!.modified));

      int total = stats.values.fold(0, (sum, stat) => sum + stat.size);
      for (final File file in files) {
        if (total <= _maxCacheBytes) {
          break;
        }
        total -= stats[file]!.size;
        await file.delete();
      }
    } catch (_) {}
  }

  // ---------------------------
  // Server
  // ---------------------------

  Future<HttpServer> _openServer() async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    server.listen((HttpRequest request) {
      unawaited(_handle(request));
    });
    return server;
  }

  void _closeServer() {
    final Future<HttpServer>? server = _server;
    _server = null;
    server?.then((s) => s.close(force: true)).catchError((_) {});
  }

  Future<void> _handle(HttpRequest request) async {
    final HttpResponse response = request.response;
    try {
      final String id = request.uri.pathSegments.isEmpty
          ? ''
          : request.uri.pathSegments.first;
      _Download? download;
      for (final _Download candidate in _downloads.values) {
        if (candidate.id == id) {
          download = candidate;
          break;
        }
      }

      if (download == null) {
        // Finished meanwhile: serve the file it left behind.
        final String? url = _urlForId(id);
        final File? file = url == null ? null : await _fileFor(url);
        if (file == null || !file.existsSync()) {
          response.statusCode = HttpStatus.notFound;
          await response.close();
          return;
        }
        await _serveFile(request, file);
        return;
      }

      await _serveDownload(request, download);
    } catch (_) {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  String? _urlForId(String id) {
    for (final MapEntry<String, String> entry in _ids.entries) {
      if (entry.value == id) {
        return entry.key;
      }
    }
    return null;
  }

  /// 4chan's videos are webm or mp4; [path] ends like the original.
  static ContentType _contentType(String path) =>
      path.toLowerCase().endsWith('.mp4')
      ? ContentType('video', 'mp4')
      : ContentType('video', 'webm');

  static final RegExp _rangePattern = RegExp(r'^bytes=(\d+)-(\d+)?$');

  static (int, int?)? _parseRange(HttpRequest request) {
    final Match? match = _rangePattern.firstMatch(
      request.headers.value(HttpHeaders.rangeHeader) ?? '',
    );
    if (match == null) {
      return null;
    }
    return (int.parse(match.group(1)!), int.tryParse(match.group(2) ?? ''));
  }

  Future<void> _serveFile(HttpRequest request, File file) async {
    final HttpResponse response = request.response;
    final int length = file.lengthSync();
    final (int, int?)? range = _parseRange(request);
    final int start = range?.$1 ?? 0;
    final int end = min(range?.$2 ?? length - 1, length - 1);

    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.contentType = _contentType(file.path);
    if (range != null) {
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$length',
      );
    }
    response.contentLength = max(0, end - start + 1);
    if (request.method != 'HEAD') {
      await response.addStream(file.openRead(start, end + 1));
    }
    await response.close();
  }

  Future<void> _serveDownload(HttpRequest request, _Download download) async {
    final HttpResponse response = request.response;
    final int total = await download.totalLength;
    if (!download.part.existsSync() && download.file.existsSync()) {
      // Finished while this request waited.
      await _serveFile(request, download.file);
      return;
    }
    final (int, int?)? range = _parseRange(request);
    final int start = range?.$1 ?? 0;
    final int end = min(range?.$2 ?? total - 1, total - 1);

    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.contentType = _contentType(download.url);
    if (range != null) {
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$total',
      );
    }
    response.contentLength = max(0, end - start + 1);
    if (request.method == 'HEAD') {
      await response.close();
      return;
    }

    // Send what's on disk, then follow the download until [end]; it comes
    // here if it's elsewhere.
    download.seek(start);
    final RandomAccessFile reader = await download.part.open();
    int sent = start;
    try {
      while (sent <= end) {
        final int available = min(download.arrivedFrom(sent), end + 1);
        if (available > sent) {
          await reader.setPosition(sent);
          final Uint8List chunk = await reader.read(available - sent);
          if (chunk.isEmpty) {
            break;
          }
          response.add(chunk);
          sent += chunk.length;
          continue;
        }
        if (download.failed) {
          break;
        }
        await download.changed();
      }
    } finally {
      await reader.close();
    }
    await response.close();
  }
}

/// One video being downloaded to `<file>.part`, renamed to [file] when done.
///
/// The fetch follows the player: a reader starting where nothing has
/// arrived, and not just ahead of the fetch, moves it there ([seek]). From
/// the end it comes back for what it skipped, so the file fills in spans.
class _Download {
  _Download({
    required this.id,
    required this.url,
    required this.file,
    required this.progress,
    required this.loaded,
    required this.onDone,
  }) : part = File('${file.path}.part');

  static const int _attempts = 5;
  // A reader starting this little ahead of the fetch waits for it.
  static const int _seekAhead = 256 * 1024;
  // Scrubbing seeks over and over; moves that close together wait a
  // moment, so the fetch goes where it settles, not everywhere on the way.
  static const Duration _seekBurst = Duration(seconds: 1);
  static const Duration _seekSettle = Duration(milliseconds: 250);

  static final RegExp _contentRange = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$');

  final String id;
  final String url;
  final File file;
  final File part;
  final ValueNotifier<double?> progress;
  final ValueNotifier<List<(double, double)>> loaded;
  final void Function(_Download) onDone;

  bool started = false;
  bool failed = false;
  bool _cancelled = false;
  bool _held = false;
  bool _running = false;
  int? _size;
  // Where the media ends, if the video's index follows it (see
  // _trailingIndex); checked once the start of the file is here.
  int? _mediaEnd;
  bool _headChecked = false;
  // What has arrived, as sorted, separate [start, end) byte ranges.
  final List<(int, int)> _spans = <(int, int)>[];
  // The next byte the fetch writes.
  int _at = 0;
  // Where a reader wants the fetch.
  int? _seekTo;
  DateTime? _lastMove;
  final Completer<int> _total = Completer<int>();
  Completer<void> _changed = Completer<void>();
  final Completer<void> _done = Completer<void>();

  /// Completes once the download has finished or failed.
  Future<void> get done => _done.future;

  /// The full size, once 4chan has answered.
  Future<int> get totalLength => _total.future;

  /// Completes the next time more bytes arrive, or the download ends.
  Future<void> changed() => _changed.future;

  void _notify() {
    final Completer<void> changed = _changed;
    _changed = Completer<void>();
    changed.complete();
  }

  /// Downloading, or about to: started and not held.
  bool get active => _running && !_held;

  /// Where the bytes from [position] on stop being there; [position] if
  /// it hasn't arrived.
  int arrivedFrom(int position) {
    for (final (int start, int end) in _spans) {
      if (start <= position && position < end) {
        return end;
      }
    }
    return position;
  }

  /// A reader starts at [position]: the fetch goes there, unless it's
  /// there already or about to be.
  void seek(int position) {
    if (arrivedFrom(position) > position ||
        (_at <= position && position < _at + _seekAhead)) {
      return;
    }
    _seekTo = position;
  }

  /// Starts the download, or continues a held one where it stopped.
  void start() {
    _held = false;
    if (_running || _cancelled) {
      return;
    }
    _running = true;
    // Not right away: watch() runs during builds, where [progress] must not
    // notify yet.
    scheduleMicrotask(() => unawaited(_run()));
  }

  /// Stops fetching for now, keeping what arrived; readers wait for
  /// [start].
  void hold() {
    _held = true;
  }

  void cancel() {
    _cancelled = true;
    if (!_running) {
      // Held or never started: no fetch is left to notice.
      _fail();
    }
  }

  Future<void> _run() async {
    if (!started) {
      started = true;
      progress.value = null;
      loaded.value = const <(double, double)>[];
      try {
        // Created empty before anyone learns the size, so readers can open
        // it.
        part.writeAsBytesSync(const <int>[]);
      } catch (_) {}
    }

    int attempt = 0;
    while (!_cancelled && !_held) {
      try {
        final DateTime? lastMove = _lastMove;
        if (_seekTo != null &&
            lastMove != null &&
            DateTime.now().difference(lastMove) < _seekBurst) {
          await Future<void>.delayed(_seekSettle);
          if (_cancelled || _held) {
            break;
          }
        }
        final int? from = _next();
        if (from == null) {
          await part.rename(file.path);
          _running = false;
          progress.value = 1;
          loaded.value = VideoServer._all;
          _finish();
          return;
        }
        await _fetch(from);
      } catch (error) {
        if (_cancelled || ++attempt >= _attempts) {
          break;
        }
        // 4chan's image server answers bursts with 429; back off longer.
        final bool limited = error is _HttpStatus && error.status == 429;
        if (error is _HttpStatus && !error.retryable) {
          break;
        }
        await Future<void>.delayed(
          Duration(seconds: limited ? 4 * attempt : attempt),
        );
      }
    }

    _running = false;
    if (_held && !_cancelled) {
      // Continues where it stopped on the next start().
      return;
    }
    _fail();
  }

  /// Where to fetch next: where a reader wants it, else the first gap from
  /// where it is, else the first gap; null once all of it is here.
  int? _next() {
    final int? size = _size;
    if (size == null) {
      return 0;
    }
    final int? seek = _seekTo;
    _seekTo = null;
    if (seek != null && arrivedFrom(seek) == seek && seek < size) {
      _lastMove = DateTime.now();
      return seek;
    }
    return _gapFrom(_at, size) ?? _gapFrom(0, size);
  }

  int? _gapFrom(int position, int size) {
    for (final (int start, int end) in _spans) {
      if (position < start) {
        break;
      }
      position = max(position, end);
    }
    return position < size ? position : null;
  }

  void _fail() {
    failed = true;
    if (!_total.isCompleted) {
      _total.completeError(StateError('Download failed: $url'));
      // Nobody may be waiting for it.
      _total.future.catchError((_) => 0);
    }
    _finish();
  }

  void _finish() {
    onDone(this);
    _notify();
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  /// Fetches from [from] up to what has arrived after it, or the end;
  /// returns early if held, cancelled or a reader wants it elsewhere.
  Future<void> _fetch(int from) async {
    _at = from;
    final http.Request request = http.Request('GET', Uri.parse(url));
    final int? size = _size;
    if (size != null) {
      int to = size;
      for (final (int start, _) in _spans) {
        if (start > from) {
          to = start;
          break;
        }
      }
      request.headers[HttpHeaders.rangeHeader] = 'bytes=$from-${to - 1}';
    }
    final http.StreamedResponse response = await httpClient.send(request);

    final int position;
    final int end;
    if (response.statusCode == HttpStatus.ok) {
      // All of it, also when the server ignored the range.
      _setSize(response.contentLength);
      position = 0;
      end = _size!;
    } else if (response.statusCode == HttpStatus.partialContent) {
      final Match? range = _contentRange.firstMatch(
        response.headers[HttpHeaders.contentRangeHeader] ?? '',
      );
      if (range == null) {
        throw const _HttpStatus(0);
      }
      _setSize(int.parse(range.group(3)!));
      position = int.parse(range.group(1)!);
      end = int.parse(range.group(2)!) + 1;
    } else {
      throw _HttpStatus(response.statusCode);
    }

    _at = position;
    bool stopped = false;
    final RandomAccessFile writer = await part.open(mode: FileMode.append);
    try {
      await for (final List<int> chunk in response.stream) {
        if (_cancelled) {
          break;
        }
        // Readers open the file separately and see the bytes once written.
        await writer.setPosition(_at);
        await writer.writeFrom(chunk);
        _arrived(_at, _at + chunk.length);
        _at += chunk.length;
        if (_held || _seekTo != null) {
          // Ends the request; the next one asks for the rest.
          stopped = true;
          break;
        }
      }
    } finally {
      await writer.close();
    }

    if (_at < end && !_cancelled && !stopped) {
      throw StateError('Download ended early: $url');
    }
  }

  void _setSize(int? size) {
    if (_size != null) {
      return;
    }
    if (size == null) {
      throw const _HttpStatus(0);
    }
    _size = size;
    _total.complete(size);
  }

  void _arrived(int start, int end) {
    int i = 0;
    while (i < _spans.length && _spans[i].$2 < start) {
      i++;
    }
    while (i < _spans.length && _spans[i].$1 <= end) {
      start = min(start, _spans[i].$1);
      end = max(end, _spans[i].$2);
      _spans.removeAt(i);
    }
    _spans.insert(i, (start, end));

    final int size = _size!;
    if (!_headChecked &&
        _spans.first.$1 == 0 &&
        _spans.first.$2 >= min(size, _headBytes)) {
      _headChecked = true;
      try {
        final RandomAccessFile head = part.openSync();
        try {
          _mediaEnd = _trailingIndex(head.readSync(_headBytes), size);
        } finally {
          head.closeSync();
        }
      } catch (_) {}
    }
    if (size > 0) {
      final int have = _spans.fold(0, (sum, span) => sum + span.$2 - span.$1);
      progress.value = have / size;
      // The index at the end isn't video: the bar showed it as a sliver of
      // the last seconds.
      final int media = _mediaEnd ?? size;
      loaded.value = <(double, double)>[
        for (final (int from, int to) in _spans)
          if (from < media) (from / media, min(to, media) / media),
      ];
    }
    _notify();
  }

  static const int _headBytes = 4096;

  /// Where the index of a video starts when it comes after the media, as
  /// mpv reads it first: an mp4's moov after its mdat, or a webm's cues
  /// after its clusters. Null if it comes first or [head] doesn't tell.
  static int? _trailingIndex(Uint8List head, int size) {
    final ByteData data = ByteData.sublistView(head);
    if (head.length >= 8 && String.fromCharCodes(head, 4, 8) == 'ftyp') {
      int at = 0;
      while (at + 8 <= head.length) {
        int box = data.getUint32(at);
        final String type = String.fromCharCodes(head, at + 4, at + 8);
        if (box == 1 && at + 16 <= head.length) {
          box = data.getUint64(at + 8);
        }
        if (type == 'moov' || box < 8) {
          return null;
        }
        if (type == 'mdat') {
          return at + box < size ? at + box : null;
        }
        at += box;
      }
      return null;
    }

    // EBML: an element is an ID and a size, both variable-length.
    (int, int)? vint(int at, {bool keepMarker = false}) {
      if (at >= head.length) {
        return null;
      }
      final int first = head[at];
      int length = 1;
      while (length <= 8 && first & (0x80 >> (length - 1)) == 0) {
        length++;
      }
      if (length > 8 || at + length > head.length) {
        return null;
      }
      int value = keepMarker ? first : first & ((0x80 >> (length - 1)) - 1);
      for (int i = 1; i < length; i++) {
        value = (value << 8) | head[at + i];
      }
      return (value, length);
    }

    const int segmentId = 0x18538067;
    const int seekHeadId = 0x114D9B74;
    const int clusterId = 0x1F43B675;
    const int cuesId = 0x1C53BB6B;
    int at = 0;
    int? segment;
    int? cues;
    while (at < head.length) {
      final (int, int)? id = vint(at, keepMarker: true);
      final (int, int)? length = id == null ? null : vint(at + id.$2);
      if (id == null || length == null) {
        break;
      }
      final int body = at + id.$2 + length.$2;
      if (id.$1 == segmentId) {
        // Its children follow; positions in the seek head count from here.
        segment = body;
        at = body;
        continue;
      }
      if (id.$1 == clusterId) {
        // Media first: the cues come after it if they're further on.
        return segment != null && cues != null && cues > at ? cues : null;
      }
      if (id.$1 == seekHeadId && segment != null) {
        // Seek entries: an ID and the position of a top-level element.
        int entry = body;
        while (entry < body + length.$1 && entry < head.length) {
          final (int, int)? seekId = vint(entry, keepMarker: true);
          final (int, int)? seekLength = seekId == null
              ? null
              : vint(entry + seekId.$2);
          if (seekId == null || seekLength == null) {
            break;
          }
          final int seekBody = entry + seekId.$2 + seekLength.$2;
          int? target;
          int? position;
          int field = seekBody;
          while (field < seekBody + seekLength.$1 && field < head.length) {
            final (int, int)? fieldId = vint(field, keepMarker: true);
            final (int, int)? fieldLength = fieldId == null
                ? null
                : vint(field + fieldId.$2);
            if (fieldId == null || fieldLength == null) {
              break;
            }
            final int value = field + fieldId.$2 + fieldLength.$2;
            int number = 0;
            for (
              int i = 0;
              i < fieldLength.$1 && value + i < head.length;
              i++
            ) {
              number = (number << 8) | head[value + i];
            }
            if (fieldId.$1 == 0x53AB) {
              target = number;
            } else if (fieldId.$1 == 0x53AC) {
              position = number;
            }
            field = value + fieldLength.$1;
          }
          if (target == cuesId && position != null) {
            cues = segment + position;
          }
          entry = seekBody + seekLength.$1;
        }
      }
      at = body + length.$1;
    }
    // No cluster within the head: cues past the middle come after it.
    return cues != null && cues > size ~/ 2 && cues < size ? cues : null;
  }
}

class _HttpStatus implements Exception {
  const _HttpStatus(this.status);

  final int status;

  bool get retryable => status == 429 || status == 0 || status >= 500;

  @override
  String toString() => 'HTTP $status';
}
