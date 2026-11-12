import 'package:flutter/material.dart';
import 'package:flutter_chan/board/grid_post.dart';
import 'package:flutter_chan/board/list_post.dart';
import 'package:flutter_chan/board/thread_views.dart';
import 'package:flutter_chan/bookmarks/bookmarks_model.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/history/watched_posts_model.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/ui/image_frost.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late WatchedPostsProvider watched;

  Future<void> pumpCard(WidgetTester tester, Widget card) async {
    SharedPreferences.setMockInitialValues({});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final SettingsProvider settings = SettingsProvider(prefs);
    watched = WatchedPostsProvider(prefs, settings);
    addTearDown(watched.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<WatchedPostsProvider>.value(value: watched),
          ChangeNotifierProvider<BookmarksProvider>(
            create: (_) => BookmarksProvider(prefs),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Center(child: SizedBox(width: 185, height: 280, child: card)),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Post thread({int replies = 12, bool sticky = false}) => Post(
    board: 'g',
    no: 123456789,
    time: 1700000000,
    sub: 'A thread',
    replies: replies,
    images: 3,
    sticky: sticky ? 1 : null,
  );

  testWidgets('a grid card shows how many replies are new, once opened', (
    tester,
  ) async {
    await pumpCard(tester, GridPost(post: thread()));
    expect(find.text('+2'), findsNothing, reason: 'never opened');

    watched.noteThreadPosts(123456789, List<int>.generate(11, (i) => i + 1));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('+2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a list card says the same, in words', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpCard(
      tester,
      OverflowBox(maxWidth: 380, child: ListPost(post: thread())),
    );

    watched.noteThreadPosts(123456789, List<int>.generate(11, (i) => i + 1));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('+2 new'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a grid card keeps its number on the image, even when crowded', (
    tester,
  ) async {
    await pumpCard(
      tester,
      GridPost(post: thread(sticky: true), showBoard: true),
    );

    final Rect card = tester.getRect(find.byType(GridPost));
    final Rect number = tester.getRect(find.text('No.123456789'));
    expect(number.top, lessThan(card.center.dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a huge reply count does not overflow next to the new count', (
    tester,
  ) async {
    await pumpCard(tester, GridPost(post: thread(replies: 123456)));
    watched.noteThreadPosts(123456789, const <int>[1, 2]);
    await tester.pump(const Duration(seconds: 3));
    expect(find.textContaining('+'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a crowded tile fits the shorter grid, even on a small phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final SettingsProvider settings = SettingsProvider(prefs);
    watched = WatchedPostsProvider(prefs, settings);
    addTearDown(watched.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<WatchedPostsProvider>.value(value: watched),
          ChangeNotifierProvider<BookmarksProvider>(
            create: (_) => BookmarksProvider(prefs),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                ThreadsView(
                  threads: [thread(sticky: true)],
                  grid: true,
                  showBoard: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final Size tile = tester.getSize(find.byType(GridPost));
    expect(tile.width, 145);
    expect(tile.height, lessThan(145 / 0.82));
  });

  testWidgets('a grid card has no live blur, which makes scrolling stutter', (
    tester,
  ) async {
    await pumpCard(tester, GridPost(post: thread()));

    expect(
      find.descendant(
        of: find.byType(GridPost),
        matching: find.byType(BackdropFilter),
      ),
      findsNothing,
    );
  });

  testWidgets('frosted chips show the image, unless it is a spoiler', (
    tester,
  ) async {
    Post withImage({int? spoiler}) => Post(
      board: 'g',
      no: 1,
      time: 1700000000,
      tim: 1,
      ext: '.jpg',
      spoiler: spoiler,
    );
    Finder tinyImages() => find.descendant(
      of: find.byType(GridPost),
      matching: find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is ResizeImage,
      ),
    );

    await pumpCard(tester, GridPost(post: withImage()));
    expect(tinyImages(), findsNWidgets(3));

    await pumpCard(tester, GridPost(post: withImage(spoiler: 1)));
    expect(tinyImages(), findsNothing);
  });

  testWidgets('a frosted bar is tinted all the way across, not just its text', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 200,
            child: ImageFrost(
              image: null,
              card: Size(200, 260),
              anchor: Alignment.bottomCenter,
              inset: Offset.zero,
              radius: 0,
              tint: Color(0x80000000),
              child: Text('a'),
            ),
          ),
        ),
      ),
    );

    final Finder tint = find.descendant(
      of: find.byType(ImageFrost),
      matching: find.byType(Container),
    );
    expect(tester.getSize(tint).width, 200);
  });
}
