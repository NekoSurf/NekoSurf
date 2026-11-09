import 'dart:async';

import 'package:flutter_chan/chan/file_server_limit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';

final Uri _video = Uri.parse('https://i.4cdn.org/wsg/1700000000000.webm');

/// 4chan's file server, refusing everything while [refusing].
class _Server {
  bool refusing = false;
  int requests = 0;

  late final MockClient client = MockClient((Request request) async {
    requests++;
    return Response(
      refusing ? 'Too Many Requests' : 'video',
      refusing ? 429 : 200,
    );
  });
}

void main() {
  late _Server server;
  late FileServerLimit limit;
  late FileServerClient client;

  setUp(() {
    server = _Server();
    limit = FileServerLimit(
      firstWait: const Duration(milliseconds: 100),
      longestWait: const Duration(milliseconds: 300),
    );
    client = FileServerClient(server.client, limit: limit);
  });

  test("only full-size files on 4chan's file server count", () {
    expect(isFullFile(_video), isTrue);
    expect(
      isFullFile(Uri.parse('https://i.4cdn.org/wsg/1700000000000.jpg')),
      isTrue,
    );
    expect(
      isFullFile(Uri.parse('https://i.4cdn.org/wsg/1700000000000s.jpg')),
      isFalse,
    );
    expect(
      isFullFile(Uri.parse('https://a.4cdn.org/wsg/catalog.json')),
      isFalse,
    );
  });

  test(
    'a refused file makes the others wait, then one check lifts it',
    () async {
      server.refusing = true;
      expect((await client.get(_video)).statusCode, 429);
      expect(limit.limited, isTrue);
      expect(server.requests, 1);

      // Asked meanwhile, these wait instead of going out.
      final List<Future<Response>> waiting = [
        for (int i = 0; i < 5; i++) client.get(_video),
      ];
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(server.requests, 1);

      server.refusing = false;
      final List<Response> answers = await Future.wait(waiting);
      expect(answers.map((r) => r.statusCode), everyElement(200));
      expect(limit.limited, isFalse);
      // The check, then the rest once it got through.
      expect(server.requests, 6);
    },
  );

  test('checks go out ever less often while it lasts', () async {
    server.refusing = true;
    final Stopwatch watch = Stopwatch()..start();
    await client.get(_video);
    final List<Duration> checks = [];
    for (int i = 0; i < 3; i++) {
      await client.get(_video);
      checks.add(watch.elapsed);
    }
    // After 100 ms, then 200 ms more, then 300 ms (the longest) more.
    expect(checks[0].inMilliseconds, greaterThanOrEqualTo(100));
    expect((checks[1] - checks[0]).inMilliseconds, greaterThanOrEqualTo(200));
    expect((checks[2] - checks[1]).inMilliseconds, inInclusiveRange(300, 450));
    expect(server.requests, 4);
  });

  test('refusals of requests already out count as one', () async {
    final Completer<void> release = Completer<void>();
    int requests = 0;
    final FileServerClient slow = FileServerClient(
      MockClient((Request request) async {
        requests++;
        await release.future;
        return Response('Too Many Requests', 429);
      }),
      limit: limit,
    );
    final List<Future<Response>> out = [
      for (int i = 0; i < 4; i++) slow.get(_video),
    ];
    await Future<void>.delayed(Duration.zero);
    release.complete();
    await Future.wait(out);
    expect(requests, 4);
    expect(limit.limited, isTrue);

    // Still the first wait, not doubled four times over.
    final Stopwatch watch = Stopwatch()..start();
    server.refusing = false;
    await client.get(_video);
    expect(watch.elapsedMilliseconds, lessThan(200));
    expect(limit.limited, isFalse);
  });

  test(
    "an answer to a request from before it started doesn't lift it",
    () async {
      final Completer<void> release = Completer<void>();
      final FileServerClient slow = FileServerClient(
        MockClient((Request request) async {
          await release.future;
          return Response('video', 200);
        }),
        limit: limit,
      );
      final Future<Response> early = slow.get(_video);
      await Future<void>.delayed(Duration.zero);

      server.refusing = true;
      await client.get(_video);
      release.complete();
      await early;
      expect(limit.limited, isTrue);
    },
  );

  test('images in view fail at once instead of waiting', () async {
    server.refusing = true;
    await client.get(_video);
    final FileServerClient images = FileServerClient(
      server.client,
      limit: limit,
      waitWhileLimited: false,
    );
    await expectLater(
      images.get(_video),
      throwsA(isA<FileServerLimitedException>()),
    );
    expect(server.requests, 1);

    // Thumbnails aren't held back.
    final Response thumbnail = await images.get(
      Uri.parse('https://i.4cdn.org/wsg/1700000000000s.jpg'),
    );
    expect(thumbnail.statusCode, 429);
    expect(server.requests, 2);
  });

  test('a failed check lets the next request check', () async {
    server.refusing = true;
    await client.get(_video);
    final FileServerClient broken = FileServerClient(
      MockClient((Request request) async => throw ClientException('offline')),
      limit: limit,
    );
    await expectLater(broken.get(_video), throwsA(isA<ClientException>()));
    server.refusing = false;
    expect((await client.get(_video)).statusCode, 200);
    expect(limit.limited, isFalse);
  });

  test('listeners hear when it starts and lifts', () async {
    final List<bool> heard = [];
    limit.addListener(() => heard.add(limit.limited));
    server.refusing = true;
    await client.get(_video);
    await client.get(_video);
    server.refusing = false;
    await client.get(_video);
    expect(heard, [true, false]);
  });
}
