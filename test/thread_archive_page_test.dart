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
import 'package:shared_preferences/shared_preferences.dart';

/// What the archives answer, by host; 4chan has deleted every thread.
final Map<String, String> _archives = <String, String>{};

void main() {
  final Directory files = Directory.systemTemp.createTempSync(
    'thread_archive_page',
  );

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => files.path,
        );
    // httpClient is made on first use, here, around this one.
    http.runWithClient(
      () => httpClient,
      () => MockClient(
        (http.Request request) async => request.url.host == 'a.4cdn.org'
            ? http.Response('', 404)
            : http.Response(
                _archives[request.url.host] ?? '{"error":"Thread not found."}',
                200,
              ),
      ),
    );
  });

  tearDownAll(() => files.deleteSync(recursive: true));

  late SharedPreferences prefs;
  late SettingsProvider settings;
  late WatchedPostsProvider watched;

  setUp(() async {
    _archives.clear();
    final ThreadCopies appCopies = ThreadCopies.instance;
    final OfflineThreads appOffline = OfflineThreads.instance;
    final Directory dir = files.createTempSync();
    ThreadCopies.instance = ThreadCopies(
      () async => Directory('${dir.path}/copies'),
    );
    OfflineThreads.instance = OfflineThreads(
      () async => Directory('${dir.path}/offline'),
    );
    addTearDown(() {
      ThreadCopies.instance = appCopies;
      OfflineThreads.instance = appOffline;
    });

    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    settings = SettingsProvider(prefs);
    watched = WatchedPostsProvider(prefs);
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
      ChangeNotifierProvider<OfflineThreads>.value(
        value: OfflineThreads.instance,
      ),
    ],
    child: MaterialApp(home: home, onGenerateRoute: generateRoute),
  );

  // Answers arrive in real time, off the UI isolate.
  Future<void> waitUntil(WidgetTester tester, bool Function() done) async {
    for (int i = 0; i < 100 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(done(), isTrue);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  }

  testWidgets('a deleted thread can be found in an archive', (tester) async {
    _archives['arch.b4k.dev'] = jsonEncode(<String, Object>{
      '100': <String, Object>{
        'op': <String, Object>{
          'num': '100',
          'subnum': '0',
          'timestamp': 1795059910,
          'title': 'Kept',
          'comment': 'First words',
        },
        'posts': <String, Object>{
          '101': <String, Object>{
            'num': '101',
            'subnum': '0',
            'timestamp': 1795060000,
            'comment': '>>100\nA reply',
          },
        },
      },
    });

    await tester.pumpWidget(app(ThreadPage(post: Post(board: 'g', no: 100))));
    await waitUntil(
      tester,
      () => find.text('Look in Archives').evaluate().isNotEmpty,
    );
    expect(find.text('Thread not found'), findsOneWidget);

    await tester.tap(find.text('Look in Archives'));
    await waitUntil(tester, () => find.text('A reply').evaluate().isNotEmpty);
    expect(find.text('First words'), findsOneWidget);
    expect(find.text('Deleted · from b4k'), findsOneWidget);
    // Found again in the history, and kept to open next time.
    expect(
      Provider.of<HistoryProvider>(
        tester.element(find.text('A reply')),
        listen: false,
      ).threads.map((t) => t.no),
      [100],
    );
    await finish(tester);

    // Opened again, it says where it came from.
    _archives.clear();
    await tester.pumpWidget(app(ThreadPage(post: Post(board: 'g', no: 100))));
    await waitUntil(tester, () => find.text('A reply').evaluate().isNotEmpty);
    expect(find.text('Deleted · from b4k'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('says so when no archive has it', (tester) async {
    await tester.pumpWidget(app(ThreadPage(post: Post(board: 'g', no: 100))));
    await waitUntil(
      tester,
      () => find.text('Look in Archives').evaluate().isNotEmpty,
    );

    await tester.tap(find.text('Look in Archives'));
    await waitUntil(
      tester,
      () => find.text('None of the archives have it').evaluate().isNotEmpty,
    );
    expect(find.text('Thread not found'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('with every archive of the board off, 4chan is offered', (
    tester,
  ) async {
    await settings.archivesOff.set({'archived.moe'});
    await tester.pumpWidget(
      app(ThreadPage(post: Post(board: 'nope', no: 100))),
    );
    await waitUntil(
      tester,
      () => find.text('Thread not found').evaluate().isNotEmpty,
    );
    expect(find.text('Open on 4chan'), findsOneWidget);
    expect(find.text('Look in Archives'), findsNothing);
    await finish(tester);
  });

  testWidgets('an archive that is off is not asked', (tester) async {
    await settings.archivesOff.set({'desuarchive.org', 'archived.moe'});
    await tester.pumpWidget(app(ThreadPage(post: Post(board: 'g', no: 100))));
    await waitUntil(
      tester,
      () => find.text('Look in Archives').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('Look in Archives'));
    // b4k, the one left, says so by name.
    await waitUntil(
      tester,
      () => find.text("b4k doesn't have it").evaluate().isNotEmpty,
    );
    await finish(tester);
  });
}
