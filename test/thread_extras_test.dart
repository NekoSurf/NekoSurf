import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chan/board/board_page.dart';
import 'package:flutter_chan/board/favorite_model.dart';
import 'package:flutter_chan/bookmarks/bookmarks_model.dart';
import 'package:flutter_chan/chan/board_link.dart';
import 'package:flutter_chan/chan/http_client.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/chan/post_text.dart';
import 'package:flutter_chan/chan/thread_status.dart';
import 'package:flutter_chan/history/history_model.dart';
import 'package:flutter_chan/history/watched_posts_model.dart';
import 'package:flutter_chan/home/routes.dart';
import 'package:flutter_chan/media/shared_media_viewer.dart';
import 'package:flutter_chan/media/spoiler_cover.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/thread/quoted_post_page.dart';
import 'package:flutter_chan/thread/thread_page.dart';
import 'package:flutter_chan/thread/thread_page_post.dart';
import 'package:flutter_chan/thread/thread_posts.dart';
import 'package:flutter_chan/ui/dash_header.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A pixel, so that images in these tests have something to show.
final ImageProvider<Object> _pixel = MemoryImage(
  Uint8List.fromList(const <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ]),
);

void main() {
  http.Response Function(http.BaseRequest request) answer = (_) =>
      http.Response('[]', 200);

  setUpAll(() {
    // httpClient is made on first use, here, around this one.
    http.runWithClient(
      () => httpClient,
      () => MockClient((http.Request request) async => answer(request)),
    );
  });

  tearDown(() => revealedSpoilers.value = const <int>{});

  group('parseBoardLink', () {
    test('finds the thread and post of a cross-thread quote', () {
      expect(parseBoardLink('/g/thread/10#p12'), (
        board: 'g',
        thread: 10,
        post: 12,
      ));
      expect(parseBoardLink('/g/thread/10/some-title#q12'), (
        board: 'g',
        thread: 10,
        post: 12,
      ));
      expect(parseBoardLink('//boards.4channel.org/g/thread/10'), (
        board: 'g',
        thread: 10,
        post: null,
      ));
    });

    test('finds a board', () {
      for (final String link in [
        '/g/',
        '//boards.4chan.org/g/',
        '/g/catalog#s=linux',
        'https://boards.4chan.org/g/',
      ]) {
        expect(parseBoardLink(link), (
          board: 'g',
          thread: null,
          post: null,
        ), reason: link);
      }
    });

    test('leaves a quote in the same thread, and other sites, alone', () {
      expect(parseBoardLink('#p12'), isNull);
      expect(parseBoardLink('https://example.com/g/'), isNull);
    });
  });

  group('unescape', () {
    test('turns entities into characters', () {
      expect(unescape('&gt;&lt;&amp;&quot;&#039;&#39;&#47;'), '><&"\'\'/');
      expect(unescape('a&nbsp;b'), 'a b');
      expect(unescape('&#x27;&#X27;'), "''");
    });

    test('a backslash is one backslash', () {
      expect(unescape('&#92;'), r'\');
    });

    test('goes over the text once', () {
      expect(unescape('&amp;quot;'), '&quot;');
      expect(unescape('&amp;gt;'), '&gt;');
    });

    test('leaves what it does not know', () {
      expect(unescape('&nope; & &#99999999;'), '&nope; & &#99999999;');
    });
  });

  group('TimeoutClient', () {
    const Duration stall = Duration(milliseconds: 20);

    test('gives up on a server that never answers', () {
      final TimeoutClient client = TimeoutClient(
        MockClient.streaming(
          (_, _) => Completer<http.StreamedResponse>().future,
        ),
        stall: stall,
      );

      expect(
        client.get(Uri.parse('https://a/')),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('gives up on an answer that stops arriving', () {
      final TimeoutClient client = TimeoutClient(
        MockClient.streaming((_, _) async {
          return http.StreamedResponse(
            StreamController<List<int>>().stream,
            200,
          );
        }),
        stall: stall,
      );

      expect(
        client.get(Uri.parse('https://a/')),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('lets an answer through', () async {
      final TimeoutClient client = TimeoutClient(
        MockClient((_) async => http.Response('hello', 200)),
        stall: stall,
      );

      expect((await client.get(Uri.parse('https://a/'))).body, 'hello');
    });
  });

  group('the status of a bookmark', () {
    // A thread that's not in the catalog, so the thread itself is asked.
    void threadAnswers(int status) {
      answer = (http.BaseRequest request) =>
          request.url.path.contains('/thread/')
          ? http.Response('{"posts":[{"no":1,"replies":3}]}', status)
          : http.Response('[]', 200);
    }

    test('is deleted when 4chan says it does not have it', () async {
      threadAnswers(404);
      final ThreadCheck? check = await checkThread('a', 1, exact: true);
      expect(check?.status, ThreadStatus.deleted);
    });

    test('is unknown when 4chan is limiting requests or failing', () async {
      threadAnswers(429);
      expect(await checkThread('b', 1, exact: true), isNull);
      threadAnswers(500);
      expect(await checkThread('c', 1, exact: true), isNull);
    });

    test('is online when it is there', () async {
      threadAnswers(200);
      final ThreadCheck? check = await checkThread('d', 1, exact: true);
      expect(check?.status, ThreadStatus.online);
      expect(check?.replies, 3);
    });
  });

  group('in a thread', () {
    late SharedPreferences prefs;
    late SettingsProvider settings;
    late WatchedPostsProvider watched;

    setUp(() async {
      answer = (_) => http.Response('[]', 200);
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      settings = SettingsProvider(prefs);
      watched = WatchedPostsProvider(prefs, settings);
      addTearDown(watched.dispose);
    });

    Widget app(Widget home) => MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<WatchedPostsProvider>.value(value: watched),
        ChangeNotifierProvider<BookmarksProvider>(
          create: (_) => BookmarksProvider(prefs),
        ),
        ChangeNotifierProvider<FavoriteProvider>(
          create: (_) => FavoriteProvider(prefs),
        ),
        ChangeNotifierProvider<HistoryProvider>(
          create: (_) => HistoryProvider(prefs, settings),
        ),
      ],
      child: MaterialApp(home: home, onGenerateRoute: generateRoute),
    );

    Future<void> pumpPost(WidgetTester tester, Post post) async {
      await tester.pumpWidget(
        app(
          Scaffold(
            body: SingleChildScrollView(
              child: ThreadPagePost(
                post: post,
                thread: ThreadPosts(
                  board: 'g',
                  number: 1,
                  posts: [
                    Post(board: 'g', no: 1, time: 1700000000),
                    post,
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    // Timers of requests that aren't answered in fake time.
    Future<void> finish(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
    }

    group('a quote of another thread', () {
      const String com =
          '<a href="/g/thread/10#p12" class="quotelink">&gt;&gt;12</a>';

      testWidgets('says so', (tester) async {
        await pumpPost(
          tester,
          Post(board: 'g', no: 3, time: 1700000000, com: com),
        );

        expect(
          find.textContaining('>>12 (other thread)', findRichText: true),
          findsOneWidget,
        );
      });

      testWidgets('opens that thread at the post', (tester) async {
        await pumpPost(
          tester,
          Post(board: 'g', no: 3, time: 1700000000, com: com),
        );

        await tester.tapOnText(find.textRange.ofSubstring('>>12'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        final ThreadPage page = tester.widget<ThreadPage>(
          find.byType(ThreadPage),
        );
        expect(page.board, 'g');
        expect(page.thread, 10);
        expect(page.initialPost, 12);
        await finish(tester);
      });
    });

    testWidgets('a link to another board opens it', (tester) async {
      await pumpPost(
        tester,
        Post(
          board: 'g',
          no: 3,
          time: 1700000000,
          com: '<a href="/wsg/" class="quotelink">&gt;&gt;&gt;/wsg/</a>',
        ),
      );

      await tester.tapOnText(find.textRange.ofSubstring('>>>/wsg/'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.widget<BoardPage>(find.byType(BoardPage)).board, 'wsg');
      await finish(tester);
    });

    testWidgets('a quote of a post that is gone says so', (tester) async {
      answer = (_) => http.Response('{"posts":[{"no":1}]}', 200);
      await tester.pumpWidget(
        app(
          QuotedPostPage(
            post: 99,
            thread: ThreadPosts(
              board: 'g',
              number: 1,
              posts: [Post(board: 'g', no: 1, time: 1700000000)],
            ),
          ),
        ),
      );
      // The request is answered in real time, off the UI isolate.
      for (
        int i = 0;
        i < 20 && find.text('Post not found').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }

      expect(find.text('Post not found'), findsOneWidget);
      expect(find.text('Anonymous'), findsNothing);
      await finish(tester);
    });

    testWidgets('code keeps its lines and spacing', (tester) async {
      await pumpPost(
        tester,
        Post(
          board: 'g',
          no: 3,
          time: 1700000000,
          com:
              'Look:<br><pre class="prettyprint">if (a) {<br>  b &amp;&amp; c;<br>}</pre>Nice',
        ),
      );

      final Finder code = find.text('if (a) {\n  b && c;\n}');
      expect(code, findsOneWidget);
      expect(find.text('Look:'), findsOneWidget);
      expect(find.text('Nice'), findsOneWidget);

      String? fontOf(Finder text) =>
          tester.widget<EditableText>(text).style.fontFamily;
      expect(fontOf(code), isNot(fontOf(find.text('Nice'))));
    });

    testWidgets('a post shows its ID, trip and role', (tester) async {
      await pumpPost(
        tester,
        Post(
          board: 'g',
          no: 3,
          time: 1700000000,
          name: 'A &amp; B',
          trip: '!abc',
          capcode: 'mod',
          id: 'Ab12Cd34',
        ),
      );

      for (final String text in ['A & B', '!abc', '## mod', 'ID:Ab12Cd34']) {
        expect(
          find.textContaining(text, findRichText: true),
          findsOneWidget,
          reason: text,
        );
      }
    });

    group('a spoiler', () {
      final Post spoiler = Post(
        board: 'g',
        no: 3,
        time: 1700000000,
        tim: 1700000000123,
        ext: '.jpg',
        w: 100,
        h: 100,
        spoiler: 1,
      );

      testWidgets('is covered until tapped', (tester) async {
        await pumpPost(tester, spoiler);

        expect(find.text('Spoiler'), findsOneWidget);
        expect(find.byType(Image), findsNothing);

        await tester.tap(find.text('Spoiler'));
        await tester.pump();

        expect(find.text('Spoiler'), findsNothing);
        expect(find.byType(Image), findsWidgets);
      });

      test('has no thumbnail to keep', () {
        expect(spoiler.thumbnailName, isNull);
        expect(
          Post(board: 'g', no: 1, tim: 5, ext: '.jpg').thumbnailName,
          '5s.jpg',
        );
        expect(Post(board: 'g', no: 1).thumbnailName, isNull);
      });

      testWidgets('is covered in the viewer too', (tester) async {
        await tester.pumpWidget(
          app(
            SharedMediaViewer(
              items: [
                SharedMediaViewerItem(
                  id: '1',
                  name: 'a.jpg',
                  source: 'a.jpg',
                  isVideo: false,
                  imageProvider: _pixel,
                  spoilerUpload: 5,
                ),
              ],
              index: 0,
              onClose: () {},
              actions: const [],
              onIndexChanged: (_) {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(Image), findsNothing);

        await tester.tap(find.text('Spoiler'));
        await tester.pump();

        expect(find.text('Spoiler'), findsNothing);
        expect(find.byType(Image), findsWidgets);
      });
    });

    group('the data saver', () {
      final Post image = Post(
        board: 'g',
        no: 3,
        time: 1700000000,
        tim: 1700000000123,
        ext: '.jpg',
        w: 100,
        h: 100,
      );

      testWidgets('leaves only the thumbnail', (tester) async {
        await pumpPost(tester, image);
        expect(find.byType(Image), findsNWidgets(2));

        await settings.dataSaver.set(true);
        await tester.pump();

        expect(find.byType(Image), findsOneWidget);
      });

      test('is remembered', () async {
        await settings.dataSaver.set(true);
        expect(SettingsProvider(prefs).dataSaver.value, isTrue);
      });
    });

    testWidgets(
      'pulling the list past its end refreshes the thread, once per pull',
      (tester) async {
        int requests = 0;
        answer = (_) {
          requests++;
          return requests == 1
              ? http.Response(
                  '{"posts":[{"no":1,"sub":"Title","com":"Words"}]}',
                  200,
                )
              : http.Response('', 304);
        };
        int buzzes = 0;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (MethodCall call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              buzzes++;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        // Answers arrive in real time, off the UI isolate.
        Future<void> waitFor(Finder finder) async {
          for (int i = 0; i < 40 && finder.evaluate().isEmpty; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)),
            );
            await tester.pump();
          }
          expect(finder, findsOneWidget);
        }

        await tester.pumpWidget(app(ThreadPage(post: Post(board: 'g', no: 1))));
        await waitFor(find.text('Words').hitTestable());

        Future<void> pull() async {
          final TestGesture gesture = await tester.startGesture(
            tester.getCenter(find.byType(ThreadPage)),
          );
          for (int step = 0; step < 12; step++) {
            await gesture.moveBy(const Offset(0, 40));
            await tester.pump(const Duration(milliseconds: 16));
          }
          await gesture.up();
          // The spinner turns until the answer is in, so nothing settles yet.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          await waitFor(find.text('No new posts'));
          // The spinner shows for at least a moment, in real time here.
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 700)),
          );
          await tester.pump();
          // The message closes by itself.
          await tester.pump(const Duration(seconds: 2));
          await tester.pumpAndSettle();
        }

        await pull();
        expect(requests, 2);
        // One tick when the ring fills, one when it's let go.
        expect(buzzes, 2);

        await pull();
        expect(requests, 3);
        expect(buzzes, 4);
        await finish(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

    testWidgets('an icon button says what it does to VoiceOver', (
      tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        app(
          Scaffold(
            body: DashIconButton(
              label: 'Gallery',
              icon: const Icon(CupertinoIcons.square_grid_3x2),
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(find.bySemanticsLabel('Gallery'), findsOneWidget);
      handle.dispose();
    });
  });
}
