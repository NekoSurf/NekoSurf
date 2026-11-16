import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chan/board/favorite_model.dart';
import 'package:flutter_chan/bookmarks/bookmarks_model.dart';
import 'package:flutter_chan/chan/http_client.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/history/history_model.dart';
import 'package:flutter_chan/history/thread_copies.dart';
import 'package:flutter_chan/history/watched_posts_model.dart';
import 'package:flutter_chan/home/routes.dart';
import 'package:flutter_chan/offline/offline_threads.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/thread/thread_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Reading a thread to the end, leaving, and coming back as replies come.
void main() {
  // The posts 4chan has for the thread, as each visit finds it.
  final List<Map<String, Object>> served = <Map<String, Object>>[];

  void post(int no, {int? answers}) {
    final String quote = answers == null
        ? ''
        : '<a href="#p$answers" class="quotelink">&gt;&gt;$answers</a><br>';
    served.add(<String, Object>{
      'no': no,
      if (no != 1) 'resto': 1,
      if (no == 1) 'sub': 'Title',
      // Long enough that a screen holds only a few.
      'com':
          '${quote}Post $no<br>${List.filled(6, 'Some words to read.').join('<br>')}',
    });
  }

  final Directory dir = Directory.systemTemp.createTempSync('thread_resume');

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => dir.path,
        );
    // httpClient is made on first use, here, around this one.
    http.runWithClient(
      () => httpClient,
      () => MockClient(
        (http.Request request) async =>
            http.Response(jsonEncode(<String, Object>{'posts': served}), 200),
      ),
    );
  });

  tearDownAll(() => dir.deleteSync(recursive: true));

  late SharedPreferences prefs;
  late SettingsProvider settings;
  late WatchedPostsProvider watched;

  setUp(() async {
    served.clear();
    final OfflineThreads appOffline = OfflineThreads.instance;
    final ThreadCopies appCopies = ThreadCopies.instance;
    final Directory files = dir.createTempSync();
    OfflineThreads.instance = OfflineThreads(
      () async => Directory('${files.path}/offline'),
    );
    ThreadCopies.instance = ThreadCopies(
      () async => Directory('${files.path}/copies'),
    );
    addTearDown(() {
      OfflineThreads.instance = appOffline;
      ThreadCopies.instance = appCopies;
    });

    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    settings = SettingsProvider(prefs);
    watched = WatchedPostsProvider(prefs);
    addTearDown(watched.dispose);
  });

  Widget app() => MultiProvider(
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
      ChangeNotifierProvider<OfflineThreads>.value(
        value: OfflineThreads.instance,
      ),
    ],
    child: MaterialApp(
      home: ThreadPage(post: Post(board: 'g', no: 1)),
      onGenerateRoute: generateRoute,
    ),
  );

  // Answers arrive in real time, off the test's clock.
  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    expect(find.text('Title'), findsWidgets);
  }

  Future<void> readToTheEnd(WidgetTester tester) async {
    for (int i = 0; i < 40; i++) {
      await tester.drag(
        find.byType(ScrollablePositionedList),
        const Offset(0, -300),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  }

  String? place() => watched.threadMemory(1)?.topPath;

  testWidgets('comes back to the end of what was read after a restart', (
    tester,
  ) async {
    for (int no = 1; no <= 20; no++) {
      post(no, answers: no == 1 ? null : 1);
    }
    await open(tester);
    await readToTheEnd(tester);
    await leave(tester);

    // Hours later, replies to post 2, which was read long ago.
    for (int no = 21; no <= 30; no++) {
      post(no, answers: 2);
    }
    await open(tester);
    await readToTheEnd(tester);
    final String? left = place();
    expect(left, startsWith('new:'));
    await leave(tester);

    // Nothing new: back where it was left.
    await open(tester);
    expect(place(), left);
    await leave(tester);

    // Something new, and what was at the bottom was read: it's in the
    // thread, and the new posts are at the bottom, opened at.
    for (int no = 31; no <= 35; no++) {
      post(no, answers: 3);
    }
    await open(tester);
    expect(place(), 'context:31');
    await leave(tester);
  });

  testWidgets('comes back to what came in while it was open', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    for (int no = 1; no <= 20; no++) {
      post(no, answers: no == 1 ? null : 1);
    }
    await open(tester);
    await readToTheEnd(tester);

    // Replies to post 2 come while it's open.
    for (int no = 21; no <= 30; no++) {
      post(no, answers: 2);
    }
    // Pulling at the end checked for new posts already: wait for the next
    // check, a while after one that found none.
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 20));
      await settle(tester);
    }
    // Listed below what was there, as they came after it.
    expect(watched.threadMemory(1)?.newestPost, 30);
    await readToTheEnd(tester);
    final String? left = place();
    expect(left, startsWith('new:'));
    await leave(tester);

    await open(tester);
    expect(place(), left);
    await leave(tester);
  });
}
