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

  static const int _maxCacheBytes = 300 * 1024 * 1024;
  static const int _maxPrefetches = 2;
  // Scrolling on queues new prefetches; the oldest are dropped.
  static const int _maxQueued = 6;

  // Seeking far ahead of the download (webm keeps its seek index at the
  // end) is fetched from 4chan directly instead of waiting for it.
  static const int _aheadThreshold = 512 * 1024;

  final Map<String, _Download> _downloads = <String, _Download>{};
  final Map<String, String> _ids = <String, String>{};
  final Map<String, ValueNotifier<double?>> _progress =
      <String, ValueNotifier<double?>>{};
  final List<_Download> _queued = <_Download>[];
  int _prefetching = 0;

  Future<HttpServer>? _server;
  Future<Directory>? _dir;

  /// Stops serving; for tests.
  @visibleForTesting
  void close() => _closeServer();

  /// What mpv should open for [url]: the cached file if it's complete,
  /// otherwise a local stream of the download, which starts now.
  Future<String> source(String url) async {
    final File file = await _fileFor(url);
    if (file.existsSync() && !_downloads.containsKey(url)) {
      _progressOf(url).value = 1;
      _touch(file);
      return file.path;
    }

    final _Download download = _downloadFor(url, file);
    _queued.remove(download);
    download.start();
    final HttpServer server = await (_server ??= _openServer());
    return 'http://127.0.0.1:${server.port}/${download.id}';
  }

  /// Starts downloading [url] in the background, so it starts from disk.
  Future<void> prefetch(String url) async {
    final File file = await _fileFor(url);
    if (file.existsSync() || _downloads.containsKey(url)) {
      return;
    }
    final _Download download = _downloadFor(url, file);
    if (_prefetching < _maxPrefetches) {
      _prefetching++;
      download.prefetch = true;
      download.start();
    } else {
      _queued.add(download);
      while (_queued.length > _maxQueued) {
        final _Download dropped = _queued.removeAt(0);
        if (!dropped.started && _downloads[dropped.url] == dropped) {
          _downloads.remove(dropped.url);
        }
      }
    }
  }

  /// How much of [url] has arrived, from 0 to 1; null while unknown.
  ValueListenable<double?> progressOf(String url) => _progressOf(url);

  /// Forgets [url]'s cached copy (e.g. one that wouldn't play), so it's
  /// downloaded again next time.
  Future<void> evict(String url) async {
    _downloads.remove(url)?.cancel();
    _progressOf(url).value = null;
    try {
      final File file = await _fileFor(url);
      if (file.existsSync()) {
        await file.delete();
      }
    } catch (_) {}
  }

  _Download _downloadFor(String url, File file) {
    return _downloads.putIfAbsent(url, () {
      final String id = _ids[url] ??= '${_ids.length}';
      return _Download(
        id: id,
        url: url,
        file: file,
        progress: _progressOf(url),
        onDone: (_Download download) {
          if (_downloads[url] == download) {
            _downloads.remove(url);
          }
          if (download.prefetch) {
            _prefetching--;
            _startQueued();
          }
        },
      );
    });
  }

  void _startQueued() {
    while (_prefetching < _maxPrefetches && _queued.isNotEmpty) {
      final _Download next = _queued.removeAt(0);
      if (_downloads[next.url] != next || next.started) {
        continue;
      }
      _prefetching++;
      next.prefetch = true;
      next.start();
    }
  }

  ValueNotifier<double?> _progressOf(String url) =>
      _progress.putIfAbsent(url, () => ValueNotifier<double?>(null));

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
    final List<String> segments = Uri.parse(url).pathSegments;
    final String name = segments.isEmpty
        ? url.hashCode.toRadixString(16)
        : segments.join('_');
    return File('${dir.path}/$name');
  }

  Future<Directory> _openDir() async {
    final Directory temp = await getTemporaryDirectory();
    final Directory dir = Directory('${temp.path}/video_cache');
    await dir.create(recursive: true);
    unawaited(_prune(dir));
    return dir;
  }

  /// Deletes the least recently watched videos beyond [_maxCacheBytes], and
  /// leftovers of downloads that never finished.
  Future<void> _prune(Directory dir) async {
    try {
      final List<File> files = <File>[];
      for (final File file in dir.listSync().whereType<File>()) {
        if (file.path.endsWith('.part')) {
          await file.delete();
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
    response.headers.contentType = ContentType('video', 'webm');
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

    if (start > download.received + _aheadThreshold) {
      await _proxy(request, download.url, start, end, total);
      return;
    }

    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.contentType = ContentType('video', 'webm');
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

    // Send what's on disk, then follow the download until [end].
    final RandomAccessFile reader = await download.part.open();
    int sent = start;
    try {
      while (sent <= end) {
        final int available = min(download.received, end + 1);
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

  /// Fetches a range ahead of the download straight from 4chan.
  Future<void> _proxy(
    HttpRequest request,
    String url,
    int start,
    int end,
    int total,
  ) async {
    final HttpResponse response = request.response;
    final http.Request upstream = http.Request('GET', Uri.parse(url))
      ..headers[HttpHeaders.rangeHeader] = 'bytes=$start-$end';
    final http.StreamedResponse reply = await httpClient.send(upstream);

    response.statusCode = HttpStatus.partialContent;
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.contentType = ContentType('video', 'webm');
    response.headers.set(
      HttpHeaders.contentRangeHeader,
      'bytes $start-$end/$total',
    );
    response.contentLength = end - start + 1;
    if (request.method != 'HEAD') {
      await response.addStream(reply.stream);
    }
    await response.close();
  }
}

/// One video being downloaded to `<file>.part`, renamed to [file] when done.
class _Download {
  _Download({
    required this.id,
    required this.url,
    required this.file,
    required this.progress,
    required this.onDone,
  }) : part = File('${file.path}.part');

  static const int _attempts = 5;
  static const Duration _stallTimeout = Duration(seconds: 20);

  final String id;
  final String url;
  final File file;
  final File part;
  final ValueNotifier<double?> progress;
  final void Function(_Download) onDone;

  bool prefetch = false;
  bool started = false;
  bool failed = false;
  bool _cancelled = false;
  int received = 0;
  final Completer<int> _total = Completer<int>();
  Completer<void> _changed = Completer<void>();

  /// The full size, once 4chan has answered.
  Future<int> get totalLength => _total.future;

  /// Completes the next time more bytes arrive, or the download ends.
  Future<void> changed() => _changed.future;

  void _notify() {
    final Completer<void> changed = _changed;
    _changed = Completer<void>();
    changed.complete();
  }

  void start() {
    if (started) {
      return;
    }
    started = true;
    unawaited(_run());
  }

  void cancel() {
    _cancelled = true;
  }

  Future<void> _run() async {
    progress.value = null;
    try {
      // Created empty before anyone learns the size, so readers can open it.
      part.writeAsBytesSync(const <int>[]);
    } catch (_) {}

    for (int attempt = 1; !_cancelled; attempt++) {
      try {
        await _fetch();
        if (_cancelled) {
          break;
        }
        await part.rename(file.path);
        progress.value = 1;
        _finish();
        return;
      } catch (error) {
        if (_cancelled || attempt >= _attempts) {
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
  }

  /// Fetches the rest of the file, continuing after [received].
  Future<void> _fetch() async {
    final http.Request request = http.Request('GET', Uri.parse(url));
    if (received > 0) {
      request.headers[HttpHeaders.rangeHeader] = 'bytes=$received-';
    }
    final http.StreamedResponse response = await httpClient
        .send(request)
        .timeout(_stallTimeout);

    if (response.statusCode == HttpStatus.ok && received > 0) {
      // The server ignored the range: start over.
      received = 0;
      part.writeAsBytesSync(const <int>[]);
    } else if (response.statusCode != HttpStatus.ok &&
        response.statusCode != HttpStatus.partialContent) {
      throw _HttpStatus(response.statusCode);
    }

    final int? length = response.contentLength;
    if (!_total.isCompleted) {
      if (length == null) {
        throw const _HttpStatus(0);
      }
      _total.complete(received + length);
    }
    final int total = await _total.future;

    final IOSink sink = part.openWrite(mode: FileMode.append);
    try {
      await for (final List<int> chunk in response.stream.timeout(
        _stallTimeout,
      )) {
        if (_cancelled) {
          break;
        }
        sink.add(chunk);
        // Readers open the file separately; make the bytes visible first.
        await sink.flush();
        received += chunk.length;
        progress.value = total > 0 ? received / total : null;
        _notify();
      }
    } finally {
      await sink.close();
    }

    if (!_cancelled && received < total) {
      throw StateError('Download ended early: $url');
    }
  }
}

class _HttpStatus implements Exception {
  const _HttpStatus(this.status);

  final int status;

  bool get retryable => status == 429 || status == 0 || status >= 500;

  @override
  String toString() => 'HTTP $status';
}
