import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_chan/media/video_server.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for 4chan's image server: serves [bytes] in slow chunks,
/// honours ranges, and can drop the first connection halfway or stall.
class _Upstream {
  _Upstream(
    this.bytes, {
    this.dropFirstAfter,
    this.stallAfter,
    this.chunkDelay = const Duration(milliseconds: 5),
  });

  final Uint8List bytes;
  final int? dropFirstAfter;
  // Sends no more than this until [resume]; at 0, not even its headers.
  final int? stallAfter;
  final Duration chunkDelay;
  late final HttpServer server;
  int requests = 0;
  final List<String?> ranges = <String?>[];
  bool _dropped = false;
  final Completer<void> _resumed = Completer<void>();

  void resume() => _resumed.complete();

  String get url => 'http://127.0.0.1:${server.port}/b/1700000000000.webm';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
  }

  Future<void> _handle(HttpRequest request) async {
    requests++;
    final String? range = request.headers.value(HttpHeaders.rangeHeader);
    ranges.add(range);
    int start = 0;
    int end = bytes.length - 1;
    final Match? match = RegExp(r'bytes=(\d+)-(\d+)?').firstMatch(range ?? '');
    if (match != null) {
      start = int.parse(match.group(1)!);
      end = int.tryParse(match.group(2) ?? '') ?? end;
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/${bytes.length}',
      );
    }
    request.response.contentLength = end - start + 1;

    const int chunk = 64 * 1024;
    for (int at = start; at <= end; at += chunk) {
      final int? drop = dropFirstAfter;
      if (drop != null && !_dropped && at - start >= drop) {
        _dropped = true;
        // Ends short of the promised length: the client sees a cut-off.
        try {
          await request.response.close();
        } catch (_) {}
        return;
      }
      final int? stall = stallAfter;
      if (stall != null && at - start >= stall) {
        await _resumed.future;
      }
      request.response.add(bytes.sublist(at, min(at + chunk, end + 1)));
      await request.response.flush();
      await Future<void>.delayed(chunkDelay);
    }
    await request.response.close();
  }
}

Uint8List _video(int length) {
  final Random random = Random(1);
  return Uint8List.fromList(
    List<int>.generate(length, (_) => random.nextInt(256)),
  );
}

Future<(HttpClientResponse, Uint8List)> _get(
  String url, {
  String? range,
}) async {
  final HttpClient client = HttpClient();
  final HttpClientRequest request = await client.getUrl(Uri.parse(url));
  if (range != null) {
    request.headers.set(HttpHeaders.rangeHeader, range);
  }
  final HttpClientResponse response = await request.close();
  final BytesBuilder body = await response.fold(
    BytesBuilder(),
    (BytesBuilder body, List<int> chunk) => body..add(chunk),
  );
  client.close();
  return (response, body.takeBytes());
}

/// Waits for [condition], or fails after a few seconds.
Future<void> _until(bool Function() condition) async {
  final Stopwatch waited = Stopwatch()..start();
  while (!condition()) {
    if (waited.elapsed > const Duration(seconds: 5)) {
      fail('Timed out');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late Directory dir;
  late VideoServer videos;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('video_server_test');
    videos = VideoServer.forTesting(dir);
  });

  tearDown(() {
    videos.close();
    dir.deleteSync(recursive: true);
  });

  test('streams the video while caching it, then plays it from disk', () async {
    final Uint8List bytes = _video(2 * 1024 * 1024);
    final _Upstream upstream = _Upstream(bytes);
    await upstream.start();

    final String local = await videos.source(upstream.url);
    expect(local, startsWith('http://127.0.0.1:'));
    // Named like its file in the cache.
    expect(Uri.parse(local).pathSegments, ['b_1700000000000.webm']);
    expect(await videos.cachedFile(upstream.url), isNull);

    final (HttpClientResponse response, Uint8List body) = await _get(local);
    expect(response.statusCode, HttpStatus.ok);
    expect(body, bytes);

    // Give the download a moment to rename its file.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final String cached = await videos.source(upstream.url);
    expect(cached, isNot(startsWith('http')));
    expect(File(cached).readAsBytesSync(), bytes);
    expect((await videos.cachedFile(upstream.url))?.path, cached);
    expect(videos.progressOf(upstream.url).value, 1);
    expect(upstream.requests, 1);

    // A player that asks again gets the file.
    final (HttpClientResponse again, Uint8List againBody) = await _get(local);
    expect(again.statusCode, HttpStatus.ok);
    expect(againBody, bytes);
    await upstream.server.close(force: true);
  });

  test('serves nothing from outside the cache', () async {
    final File outside = File('${dir.path}_outside.webm')
      ..writeAsBytesSync(_video(1024));
    addTearDown(outside.deleteSync);
    final _Upstream upstream = _Upstream(_video(1024));
    await upstream.start();
    final Uri local = Uri.parse(await videos.source(upstream.url));

    for (final String path in <String>[
      '/b_1.webm',
      '/..%2F${outside.uri.pathSegments.last}',
    ]) {
      final (HttpClientResponse response, _) = await _get(
        local.replace(path: path).toString(),
      );
      expect(response.statusCode, HttpStatus.notFound, reason: path);
    }
    await upstream.server.close(force: true);
  });

  test('lets go of a stream when the player hangs up mid-video', () async {
    final Uint8List bytes = _video(1024 * 1024);
    final _Upstream upstream = _Upstream(bytes, stallAfter: 256 * 1024);
    await upstream.start();
    final String local = await videos.source(upstream.url);

    // The player has what arrived before the download stalled.
    final HttpClient client = HttpClient();
    final HttpClientResponse response = await (await client.getUrl(
      Uri.parse(local),
    )).close();
    int received = 0;
    final StreamSubscription<List<int>> reading = response.listen(
      (List<int> chunk) => received += chunk.length,
      onError: (Object _) {},
    );
    await _until(() => received == 256 * 1024);
    expect(videos.openStreams, 1);

    // Then hangs up, as mpv does when it seeks or reconnects.
    await reading.cancel();
    client.close(force: true);
    await _until(() => videos.openStreams == 0);
    expect(videos.progressOf(upstream.url).value, 0.25);

    // The download carries on without it.
    upstream.resume();
    while (await videos.cachedFile(upstream.url) == null) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect((await videos.cachedFile(upstream.url))!.readAsBytesSync(), bytes);
    expect(videos.openStreams, 0);
    await upstream.server.close(force: true);
  });

  test(
    'lets go of a stream when the player hangs up before it starts',
    () async {
      final Uint8List bytes = _video(512 * 1024);
      final _Upstream upstream = _Upstream(bytes, stallAfter: 0);
      await upstream.start();
      final String local = await videos.source(upstream.url);

      // 4chan hasn't answered yet, so neither has the server.
      final HttpClient client = HttpClient();
      final HttpClientRequest request = await client.getUrl(Uri.parse(local));
      unawaited(request.close().then((_) {}, onError: (Object _) {}));
      await _until(() => videos.openStreams == 1);

      client.close(force: true);
      await _until(() => videos.openStreams == 0);
      expect(videos.progressOf(upstream.url).value, isNull);

      upstream.resume();
      while (await videos.cachedFile(upstream.url) == null) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect((await videos.cachedFile(upstream.url))!.readAsBytesSync(), bytes);
      await upstream.server.close(force: true);
    },
  );

  test('hands out the first bytes before the download is done', () async {
    final Uint8List bytes = _video(2 * 1024 * 1024);
    final _Upstream upstream = _Upstream(bytes);
    await upstream.start();

    final String local = await videos.source(upstream.url);
    final HttpClient client = HttpClient();
    final HttpClientResponse response = await (await client.getUrl(
      Uri.parse(local),
    )).close();
    final List<int> first = await response.first;

    expect(first, isNotEmpty);
    expect(videos.progressOf(upstream.url).value, lessThan(1));
    client.close(force: true);
    await upstream.server.close(force: true);
  });

  test('answers ranges, and moves the download to one far ahead', () async {
    final Uint8List bytes = _video(4 * 1024 * 1024);
    final _Upstream upstream = _Upstream(
      bytes,
      chunkDelay: const Duration(milliseconds: 20),
    );
    await upstream.start();

    final String local = await videos.source(upstream.url);

    // Near the start: served from the download.
    final (HttpClientResponse near, Uint8List nearBody) = await _get(
      local,
      range: 'bytes=1000-1999',
    );
    expect(near.statusCode, HttpStatus.partialContent);
    expect(
      near.headers.value(HttpHeaders.contentRangeHeader),
      'bytes 1000-1999/${bytes.length}',
    );
    expect(nearBody, bytes.sublist(1000, 2000));

    // Far ahead (scrubbing forward, or webm's seek index at the end): the
    // download goes there instead of on from the start.
    final int from = bytes.length - 1024 * 1024;
    final (HttpClientResponse far, Uint8List farBody) = await _get(
      local,
      range: 'bytes=$from-',
    );
    expect(far.statusCode, HttpStatus.partialContent);
    expect(farBody, bytes.sublist(from));
    expect(upstream.ranges, contains('bytes=$from-${bytes.length - 1}'));
    final List<(double, double)> loaded = videos.loadedOf(upstream.url).value;
    expect(loaded, hasLength(2));
    expect(loaded.first.$1, 0);
    expect(loaded.last, (from / bytes.length, 1.0));

    // Then it fills in what it skipped.
    while (await videos.cachedFile(upstream.url) == null) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect((await videos.cachedFile(upstream.url))!.readAsBytesSync(), bytes);
    expect(videos.loadedOf(upstream.url).value, [(0.0, 1.0)]);
    await upstream.server.close(force: true);
  });

  test('goes where scrubbing settles, not everywhere on the way', () async {
    final Uint8List bytes = _video(4 * 1024 * 1024);
    final _Upstream upstream = _Upstream(
      bytes,
      chunkDelay: const Duration(milliseconds: 20),
    );
    await upstream.start();
    final String local = await videos.source(upstream.url);
    await _get(local, range: 'bytes=0-999');

    // One seek after another, as while dragging the slider.
    final HttpClient client = HttpClient();
    Future<HttpClientResponse> seek(int at) async {
      final HttpClientRequest request = await client.getUrl(Uri.parse(local));
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$at-');
      return request.close();
    }

    const int mb = 1024 * 1024;
    final HttpClientResponse first = await seek(mb);
    await first.first;
    // Never answered: the download doesn't stop there.
    unawaited(seek(2 * mb).then((_) {}, onError: (_) {}));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final HttpClientResponse last = await seek(3 * mb);
    expect((await last.first).first, bytes[3 * mb]);

    expect(upstream.ranges, contains('bytes=$mb-${bytes.length - 1}'));
    expect(upstream.ranges, contains('bytes=${3 * mb}-${bytes.length - 1}'));
    expect(
      upstream.ranges.where(
        (range) => range?.startsWith('bytes=${2 * mb}-') ?? false,
      ),
      isEmpty,
    );
    client.close(force: true);
    await upstream.server.close(force: true);
  });

  test('continues a dropped download where it stopped', () async {
    final Uint8List bytes = _video(1024 * 1024);
    final _Upstream upstream = _Upstream(bytes, dropFirstAfter: 300 * 1024);
    await upstream.start();

    final String local = await videos.source(upstream.url);
    final (HttpClientResponse response, Uint8List body) = await _get(local);
    expect(response.statusCode, HttpStatus.ok);
    expect(body, bytes);
    // The retry asked only for the rest.
    expect(upstream.ranges.last, startsWith('bytes='));
    expect(upstream.ranges.last, isNot('bytes=0-'));
    await upstream.server.close(force: true);
  });

  test('holds a preload while a watched video arrives', () async {
    final Uint8List bytes = _video(1024 * 1024);
    final _Upstream upstream = _Upstream(
      bytes,
      chunkDelay: const Duration(milliseconds: 20),
    );
    await upstream.start();
    final String preloaded = upstream.url.replaceFirst('.webm', 'p.webm');

    await videos.prefetch(preloaded);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await _get(await videos.source(upstream.url));
    expect(videos.progressOf(preloaded).value, lessThan(0.6));

    // Then it continues where it stopped.
    while (await videos.cachedFile(preloaded) == null) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect((await videos.cachedFile(preloaded))!.readAsBytesSync(), bytes);
    expect(upstream.ranges.whereType<String>(), [
      isNot(startsWith('bytes=0-')),
    ]);
    await upstream.server.close(force: true);
  });

  test('continues a video nobody watches after the watched ones', () async {
    final Uint8List bytes = _video(1024 * 1024);
    final _Upstream upstream = _Upstream(
      bytes,
      chunkDelay: const Duration(milliseconds: 20),
    );
    await upstream.start();
    final String scrolledPast = upstream.url.replaceFirst('.webm', 'a.webm');

    // Its player keeps reading while the download is held.
    final Future<(HttpClientResponse, Uint8List)> reading = _get(
      await videos.source(scrolledPast),
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));
    videos.unwatch(scrolledPast);
    await _get(await videos.source(upstream.url));
    expect(videos.progressOf(scrolledPast).value, lessThan(0.6));

    final (HttpClientResponse response, Uint8List body) = await reading;
    expect(response.statusCode, HttpStatus.ok);
    expect(body, bytes);
    await upstream.server.close(force: true);
  });

  test(
    'saving waits for the download that is arriving, not a second one',
    () async {
      final Uint8List bytes = _video(1024 * 1024);
      final _Upstream upstream = _Upstream(
        bytes,
        chunkDelay: const Duration(milliseconds: 20),
      );
      await upstream.start();

      // Watched, then scrolled away from: held behind another watched video.
      final String saved = upstream.url.replaceFirst('.webm', 's.webm');
      unawaited(_get(await videos.source(saved)));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      videos.unwatch(saved);
      final Future<(HttpClientResponse, Uint8List)> other = _get(
        await videos.source(upstream.url),
      );
      expect(await videos.cachedFile(saved), isNull);

      // Saving it puts it first again, and hands over its finished file.
      final File? file = await videos.downloadedFile(saved);
      expect(file?.readAsBytesSync(), bytes);
      expect(
        upstream.ranges.where((String? range) => range == null).length,
        2,
        reason: 'one request each, none for the save',
      );
      await other;
      await upstream.server.close(force: true);
    },
  );

  test('saving hears how much of the download has arrived', () async {
    final Uint8List bytes = _video(1024 * 1024);
    final _Upstream upstream = _Upstream(
      bytes,
      chunkDelay: const Duration(milliseconds: 10),
    );
    await upstream.start();
    unawaited(_get(await videos.source(upstream.url)));

    final List<double?> heard = <double?>[];
    final File? file = await videos.downloadedFile(
      upstream.url,
      onProgress: heard.add,
    );

    expect(file?.readAsBytesSync(), bytes);
    final List<double> known = heard.whereType<double>().toList();
    expect(known.length, greaterThan(3));
    expect(known, orderedEquals([...known]..sort()));
    expect(known.last, 1);
    await upstream.server.close(force: true);
  });

  test('saving a video nobody downloads finds nothing to wait for', () async {
    expect(await videos.downloadedFile('http://127.0.0.1:1/b/1.webm'), isNull);
  });

  test('reports, trims and clears the cache', () async {
    final Uint8List bytes = _video(512 * 1024);
    final _Upstream upstream = _Upstream(bytes);
    await upstream.start();
    final List<String> urls = [
      for (int i = 0; i < 3; i++) upstream.url.replaceFirst('.webm', '$i.webm'),
    ];

    for (final String url in urls) {
      await _get(await videos.source(url));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(await videos.cacheSize(), 3 * bytes.length);

    // Room for two: the least recently watched goes.
    final ValueListenable<double?> shown = videos.progressOf(urls.first);
    final List<double?> heard = <double?>[];
    void hear() => heard.add(shown.value);
    shown.addListener(hear);
    final ValueListenable<List<(double, double)>> unheard = videos.loadedOf(
      urls.first,
    );
    await videos.setMaxCacheBytes(2 * bytes.length);
    expect(await videos.cacheSize(), 2 * bytes.length);
    // What listens hears it's gone; what doesn't is let go.
    expect(heard, [null]);
    expect(videos.progressOf(urls.first), same(shown));
    expect(videos.loadedOf(urls.first), isNot(same(unheard)));
    expect(videos.loadedOf(urls.first).value, isEmpty);
    shown.removeListener(hear);
    expect(await videos.source(urls.first), startsWith('http'));
    expect(await videos.source(urls.last), isNot(startsWith('http')));

    await videos.clearCache();
    expect(await videos.cacheSize(), lessThan(bytes.length));
    expect(videos.progressOf(urls.last).value, isNull);
    await upstream.server.close(force: true);
  });
}
