import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_chan/services/video_server.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for 4chan's image server: serves [bytes] in slow chunks,
/// honours ranges, and can drop the first connection halfway.
class _Upstream {
  _Upstream(this.bytes, {this.dropFirstAfter});

  final Uint8List bytes;
  final int? dropFirstAfter;
  late final HttpServer server;
  int requests = 0;
  final List<String?> ranges = <String?>[];
  bool _dropped = false;

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
      request.response.add(bytes.sublist(at, min(at + chunk, end + 1)));
      await request.response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 5));
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

    final (HttpClientResponse response, Uint8List body) = await _get(local);
    expect(response.statusCode, HttpStatus.ok);
    expect(body, bytes);

    // Give the download a moment to rename its file.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final String cached = await videos.source(upstream.url);
    expect(cached, isNot(startsWith('http')));
    expect(File(cached).readAsBytesSync(), bytes);
    expect(videos.progressOf(upstream.url).value, 1);
    expect(upstream.requests, 1);
    await upstream.server.close(force: true);
  });

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

  test('answers ranges, and fetches ones far ahead from upstream', () async {
    final Uint8List bytes = _video(4 * 1024 * 1024);
    final _Upstream upstream = _Upstream(bytes);
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

    // The end (where webm keeps its seek index): straight from upstream.
    final int from = bytes.length - 4096;
    final (HttpClientResponse far, Uint8List farBody) = await _get(
      local,
      range: 'bytes=$from-',
    );
    expect(far.statusCode, HttpStatus.partialContent);
    expect(farBody, bytes.sublist(from));
    expect(upstream.ranges, contains('bytes=$from-${bytes.length - 1}'));
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
}
