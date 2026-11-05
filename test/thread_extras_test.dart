import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chan/API/api.dart';
import 'package:flutter_chan/API/archived.dart';
import 'package:flutter_chan/API/http_client.dart';
import 'package:flutter_chan/Models/bookmark_status.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/bookmarks_model.dart';
import 'package:flutter_chan/blocs/favorite_model.dart';
import 'package:flutter_chan/blocs/history_model.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/blocs/watched_posts_model.dart';
import 'package:flutter_chan/enums/enums.dart';
import 'package:flutter_chan/pages/media/shared_media_viewer.dart';
import 'package:flutter_chan/pages/thread/thread_page_post.dart';
import 'package:flutter_chan/pages/thread/thread_replied_to.dart';
import 'package:flutter_chan/pages/thread/thread_rows.dart';
import 'package:flutter_chan/pages/thread/thread_rows_list.dart';
import 'package:flutter_chan/services/string.dart';
import 'package:flutter_chan/widgets/spoiler_cover.dart';
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

  tearDown(resetRevealedSpoilers);

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
      final BookmarkStatus status = await fetchBookmarkStatus('a', '1');
      expect(status.status, ThreadStatus.deleted);
    });

    test('is unknown when 4chan is limiting requests or failing', () async {
      threadAnswers(429);
      await expectLater(
        fetchBookmarkStatus('b', '1'),
        throwsA(isA<ApiException>()),
      );
      threadAnswers(500);
      await expectLater(
        fetchBookmarkStatus('c', '1'),
        throwsA(isA<ApiException>()),
      );
    });

    test('is online when it is there', () async {
      threadAnswers(200);
      final BookmarkStatus status = await fetchBookmarkStatus('d', '1');
      expect(status.status, ThreadStatus.online);
      expect(status.replies?.replies, 3);
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
      watched = WatchedPostsProvider(prefs);
      addTearDown(watched.dispose);
    });

    Widget app(Widget home) => MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeChanger>(
          create: (_) => ThemeChanger(ThemeData.dark()),
        ),
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<WatchedPostsProvider>.value(value: watched),
        ChangeNotifierProvider<BookmarksProvider>(
          create: (_) => BookmarksProvider(prefs),
        ),
        ChangeNotifierProvider<FavoriteProvider>(
          create: (_) => FavoriteProvider(prefs),
        ),
        ChangeNotifierProvider<HistoryProvider>(
          create: (_) => HistoryProvider(prefs),
        ),
      ],
      child: MaterialApp(home: home),
    );

    Future<void> pumpPost(WidgetTester tester, Post post) async {
      await tester.pumpWidget(
        app(
          Scaffold(
            body: SingleChildScrollView(
              child: ThreadPagePost(
                board: 'g',
                thread: 1,
                post: post,
                allPosts: [Post(no: 1, time: 1700000000), post],
                onDismiss: (_) {},
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

    testWidgets('a quote of a post that is gone says so', (tester) async {
      answer = (_) => http.Response('{"posts":[{"no":1}]}', 200);
      await tester.pumpWidget(
        app(
          ThreadRepliesTo(
            post: 99,
            thread: 1,
            board: 'g',
            allPosts: [Post(no: 1, time: 1700000000)],
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

    testWidgets('a post shows its ID, trip and role', (tester) async {
      await pumpPost(
        tester,
        Post(
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
        expect(Post(tim: 5, ext: '.jpg').thumbnailName, '5s.jpg');
        expect(Post().thumbnailName, isNull);
      });

      testWidgets('is covered in the viewer too', (tester) async {
        await tester.pumpWidget(
          app(
            SharedMediaViewer(
              items: [
                SharedMediaViewerItem(
                  id: '1',
                  source: 'a.jpg',
                  isVideo: false,
                  imageProvider: _pixel,
                  spoilerUpload: 5,
                ),
              ],
              initialIndex: 0,
              onClose: () {},
              mediaNameBuilder: (_) => 'a.jpg',
              actions: const [],
              onIndexChanged: (_) {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(InteractiveViewer), findsNothing);

        await tester.tap(find.text('Spoiler'));
        await tester.pump();

        expect(find.byType(InteractiveViewer), findsOneWidget);
      });
    });

    testWidgets(
      'pulling the list past its end asks for a refresh, once per pull',
      (tester) async {
        final GlobalKey<_PullListState> key = GlobalKey();
        await tester.pumpWidget(app(Scaffold(body: _PullList(key: key))));
        await tester.pump();
        await tester.pump();

        Future<void> pull() async {
          final TestGesture gesture = await tester.startGesture(
            tester.getCenter(find.byKey(key)),
          );
          for (int step = 0; step < 12; step++) {
            await gesture.moveBy(const Offset(0, 40));
            await tester.pump(const Duration(milliseconds: 16));
          }
          await gesture.up();
          await tester.pumpAndSettle();
        }

        await pull();
        expect(key.currentState!.pulls, 1);

        await pull();
        expect(key.currentState!.pulls, 2);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  });
}

/// A short list, to pull at the ends of.
class _PullList extends StatefulWidget {
  const _PullList({super.key});

  @override
  State<_PullList> createState() => _PullListState();
}

class _PullListState extends State<_PullList> with ThreadRowsList<_PullList> {
  int pulls = 0;

  final List<Post> _posts = <Post>[
    Post(no: 1, time: 1700000000, com: 'Words'),
    Post(no: 2, time: 1700000000, com: 'Words'),
  ];

  @override
  void initState() {
    super.initState();
    rebuildRows();
  }

  @override
  int get threadNumber => 1;

  @override
  void onPulledPastEnd() => pulls++;

  @override
  List<ThreadRow> buildRows() =>
      buildFlatRows(_posts, replyCounts: const <int, int>{});

  @override
  Widget build(BuildContext context) =>
      buildRowList(context, board: 'g', thread: 1, allPosts: _posts);
}
