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
import 'package:flutter_chan/media/image_cache.dart';
import 'package:flutter_chan/media/video_server.dart';
import 'package:flutter_chan/offline/offline_threads.dart';
import 'package:flutter_chan/offline/offline_threads_page.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/thread/thread_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_platform_interface/sqflite_platform_interface.dart';

// On its own, with the caches made before any test: ones made in a test's
// clock never finish being made once that test is over.
void main() {
  // The caches ask where to keep their files: here, for the whole file.
  final Directory caches = Directory.systemTemp.createTempSync(
    'offline_thread_page_caches',
  );
  const MethodChannel paths = MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => caches.path);

    // The image caches keep their records in sqflite, which a running app
    // sets up: here it says where its files go, and every database is empty.
    SqflitePlatform.initWithDatabaseFactoryMethodChannel();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.tekartik.sqflite'),
          (MethodCall call) async => switch (call.method) {
            'getDatabasesPath' => caches.path,
            'openDatabase' => 1,
            'query' => <String, Object>{
              'columns': <String>[],
              'rows': <Object>[],
            },
            'insert' => 1,
            'update' || 'delete' => 0,
            _ => null,
          },
        );

    // httpClient is made on first use, here, around this one.
    http.runWithClient(
      () => httpClient,
      () => MockClient(
        (http.Request request) async => request.url.host == 'a.4cdn.org'
            ? http.Response(
                '{"posts":[{"no":1,"sub":"Title","com":"Words",'
                '"tim":100,"ext":".jpg"},{"no":2,"resto":1,"com":"A reply"}]}',
                200,
              )
            : http.Response('image', 200),
      ),
    );
    // Made now, outside any test's clock, so each can use them.
    await VideoServer.instance.cachedFile('https://i.4cdn.org/g/0.webm');
    await cachedImageFile('https://i.4cdn.org/g/0.jpg');
  });

  tearDownAll(() => caches.deleteSync(recursive: true));

  late Directory dir;
  late SharedPreferences prefs;
  late SettingsProvider settings;
  late WatchedPostsProvider watched;
  late OfflineThreads offline;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('offline_thread_page_test');
    final OfflineThreads appOffline = OfflineThreads.instance;
    final ThreadCopies appCopies = ThreadCopies.instance;
    offline = OfflineThreads(() async => Directory('${dir.path}/offline'));
    OfflineThreads.instance = offline;
    ThreadCopies.instance = ThreadCopies(
      () async => Directory('${dir.path}/copies'),
    );
    addTearDown(() {
      OfflineThreads.instance = appOffline;
      ThreadCopies.instance = appCopies;
      dir.deleteSync(recursive: true);
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
      ChangeNotifierProvider<OfflineThreads>.value(value: offline),
    ],
    child: MaterialApp(home: home, onGenerateRoute: generateRoute),
  );

  // Answers and files arrive in real time, off the UI isolate.
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

  testWidgets('a thread is saved for offline from its menu', (tester) async {
    await tester.pumpWidget(app(ThreadPage(post: Post(board: 'g', no: 1))));
    // The reply is below the image, out of sight.
    await waitUntil(tester, () => find.text('Words').evaluate().isNotEmpty);

    await tester.tap(find.bySemanticsLabel('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save for Offline'));
    await tester.pump();
    await waitUntil(
      tester,
      () => offline.isSaved('g', 1) && offline.savingProgress('g', 1) == null,
    );
    await tester.pump();

    // Under the title, and in the message that it's done.
    expect(find.text('Saved for offline'), findsWidgets);
    expect(offline.fileFor('https://i.4cdn.org/g/100.jpg'), isNotNull);
    expect(offline.fileFor('https://i.4cdn.org/g/100s.jpg'), isNotNull);

    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.bySemanticsLabel('More'));
    await tester.pumpAndSettle();
    expect(find.text('Update Offline Copy'), findsOneWidget);
    await tester.tap(find.text('Remove Offline Copy'));
    await tester.pumpAndSettle();
    await waitUntil(tester, () => !offline.isSaved('g', 1));
    await finish(tester);
  });

  testWidgets('saved threads are listed, to open or remove', (tester) async {
    await tester.runAsync(
      () => offline.save(<Post>[
        Post(board: 'g', no: 1, sub: 'Cats', tim: 100, ext: '.jpg'),
      ]),
    );

    await tester.pumpWidget(app(const OfflineThreadsPage()));
    await tester.pump();
    expect(find.text('Cats'), findsOneWidget);
    expect(find.textContaining('1 file'), findsOneWidget);

    await tester.longPress(find.text('Cats'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await waitUntil(tester, () => offline.threads.isEmpty);
    await tester.pump();
    expect(find.textContaining('Save a thread for offline'), findsOneWidget);
    await finish(tester);
  });
}
