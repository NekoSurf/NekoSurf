import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_chan/chan/http_client.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/history/thread_copies.dart';
import 'package:flutter_chan/media/image_cache.dart';
import 'package:flutter_chan/media/video_server.dart';
import 'package:flutter_chan/offline/offline_threads.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<String> asked = <String>[];
  Set<String> failing = <String>{};

  setUpAll(() {
    // httpClient is made on first use, here, around this one.
    http.runWithClient(
      () => httpClient,
      () => MockClient((http.Request request) async {
        final String url = request.url.toString();
        asked.add(url);
        return failing.contains(url)
            ? http.Response('', 404)
            : http.Response('bytes of $url', 200);
      }),
    );
  });

  late Directory dir;
  late OfflineThreads offline;
  late ThreadCopies before;

  setUp(() {
    asked.clear();
    failing = <String>{};
    dir = Directory.systemTemp.createTempSync('offline_threads_test');
    // The caches ask where to keep their files.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall call) async => dir.path,
        );
    offline = OfflineThreads(() async => Directory('${dir.path}/offline'));
    before = ThreadCopies.instance;
    ThreadCopies.instance = ThreadCopies(
      () async => Directory('${dir.path}/copies'),
    );
  });

  tearDown(() {
    ThreadCopies.instance = before;
    dir.deleteSync(recursive: true);
  });

  final List<Post> thread = <Post>[
    Post(board: 'g', no: 1, sub: 'Cats', tim: 100, ext: '.jpg'),
    Post(board: 'g', no: 2, resto: 1, com: 'No file'),
    Post(board: 'g', no: 3, resto: 1, tim: 300, ext: '.webm'),
  ];
  const String image = 'https://i.4cdn.org/g/100.jpg';
  const String imageThumb = 'https://i.4cdn.org/g/100s.jpg';
  const String video = 'https://i.4cdn.org/g/300.webm';
  const String videoThumb = 'https://i.4cdn.org/g/300s.jpg';

  test('saves each image and video with its thumbnail, and the text', () async {
    final List<double?> progress = <double?>[];
    offline.addListener(() => progress.add(offline.savingProgress('g', 1)));

    final OfflineSaveResult result = await offline.save(thread);

    expect(result, (saved: 4, failed: 0));
    expect(asked.toSet(), {image, imageThumb, video, videoThumb});
    expect(offline.fileFor(video)!.readAsStringSync(), 'bytes of $video');
    expect(offline.fileFor('https://i.4cdn.org/g/999.jpg'), isNull);

    final OfflineThread saved = offline.thread('g', 1)!;
    expect(saved.title, 'Cats');
    expect(saved.mediaCount, 2);
    expect(saved.missing, 0);
    expect(saved.bytes, greaterThan(0));
    expect(offline.isSaved('g', 1), isTrue);
    // Along the way, then done.
    expect(progress, contains(1.0));
    expect(offline.savingProgress('g', 1), isNull);

    final ThreadCopy? copy = await ThreadCopies.instance.read('g', 1);
    expect(copy!.posts.length, 3);
  });

  test('what is saved shows from the phone', () async {
    await offline.save(thread);
    final OfflineThreads app = OfflineThreads.instance;
    OfflineThreads.instance = offline;
    addTearDown(() => OfflineThreads.instance = app);

    expect(thumbnailImage(imageThumb), isA<FileImage>());
    expect(fullImage(image), isA<FileImage>());
    expect(
      await VideoServer.instance.source(video),
      offline.fileFor(video)!.path,
    );
    expect(fullImage('https://i.4cdn.org/g/999.jpg'), isNot(isA<FileImage>()));
  });

  test('saved again, it fetches only what is new or failed', () async {
    failing = {video};
    expect(await offline.save(thread), (saved: 3, failed: 1));
    expect(offline.thread('g', 1)!.missing, 1);

    asked.clear();
    failing = <String>{};
    final OfflineSaveResult result = await offline.save(<Post>[
      ...thread,
      Post(board: 'g', no: 4, resto: 1, tim: 400, ext: '.png'),
    ]);

    expect(result, (saved: 6, failed: 0));
    expect(asked.toSet(), {
      video,
      'https://i.4cdn.org/g/400.png',
      'https://i.4cdn.org/g/400s.jpg',
    });
    expect(offline.thread('g', 1)!.missing, 0);
  });

  test('is still there after the app restarts', () async {
    await offline.save(thread);
    // A save that never got as far as its first files.
    Directory('${dir.path}/offline/g_9').createSync(recursive: true);

    final OfflineThreads restarted = OfflineThreads(
      () async => Directory('${dir.path}/offline'),
    );
    await restarted.load();

    expect(restarted.threads.map((t) => t.key), ['g/1']);
    expect(restarted.fileFor(image)!.existsSync(), isTrue);
    expect(Directory('${dir.path}/offline/g_9').existsSync(), isFalse);
  });

  test('removing it deletes its files', () async {
    await offline.save(thread);
    final File file = offline.fileFor(image)!;

    await offline.remove('g', 1);

    expect(offline.isSaved('g', 1), isFalse);
    expect(offline.fileFor(image), isNull);
    expect(file.existsSync(), isFalse);
    expect(offline.threads, isEmpty);
  });
}
