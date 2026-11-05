import 'dart:async';

import 'package:flutter/material.dart';
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
import 'package:flutter_chan/pages/thread/thread_replied_to.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  });
}
