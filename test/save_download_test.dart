import 'dart:io';

import 'package:flutter_chan/API/save_videos.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers each request with the next of [statuses], then 200 with [body].
Future<HttpServer> _serve(List<int> statuses, List<int> body) async {
  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  int request = 0;
  server.listen((HttpRequest req) async {
    final int status = request < statuses.length
        ? statuses[request]
        : HttpStatus.ok;
    request++;
    req.response.statusCode = status;
    if (status == HttpStatus.ok) {
      req.response.add(body);
    }
    await req.response.close();
  });
  return server;
}

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('save_download_test');
    downloadRetryDelay = Duration.zero;
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
  });

  test('tries again when 4chan says too many requests', () async {
    final HttpServer server = await _serve([429, 503], [1, 2, 3]);
    final String url = 'http://127.0.0.1:${server.port}/b/1s.jpg';

    expect(await downloadThumbnail('1.webm', url, '${dir.path}/'), '1.jpg');
    expect(File('${dir.path}/1.jpg').readAsBytesSync(), [1, 2, 3]);
    await server.close(force: true);
  });

  test("gives up on what won't change, leaving nothing behind", () async {
    final HttpServer server = await _serve([404, 404], [1]);
    final String url = 'http://127.0.0.1:${server.port}/b/1s.jpg';

    await expectLater(
      downloadThumbnail('1.webm', url, '${dir.path}/'),
      throwsA(isA<HttpException>()),
    );
    expect(dir.listSync(), isEmpty);
    await server.close(force: true);
  });

  test('gives up after three tries', () async {
    final HttpServer server = await _serve([429, 429, 429], [1]);
    final String url = 'http://127.0.0.1:${server.port}/b/1s.jpg';

    await expectLater(
      downloadThumbnail('1.webm', url, '${dir.path}/'),
      throwsA(isA<HttpException>()),
    );
    await server.close(force: true);
  });
}
