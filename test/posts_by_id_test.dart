import 'package:flutter/material.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/history/watched_posts_model.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/thread/posts_by_id_page.dart';
import 'package:flutter_chan/thread/thread_posts.dart';
import 'package:flutter_chan/thread/thread_replies.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _quoteOf(int id) => '<a href="#p$id" class="quotelink">&gt;&gt;$id</a>';

/// A post quoting [quotes], with words saying which it is.
Post _post(int no, {String? id, List<int> quotes = const <int>[2]}) => Post(
  board: 'g',
  no: no,
  time: 1700000000,
  id: id,
  com: [
    for (final int quote in quotes) _quoteOf(quote),
    'Words of $no',
  ].join('<br>'),
);

void main() {
  late SettingsProvider settings;
  late WatchedPostsProvider watched;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    settings = SettingsProvider(prefs);
    watched = WatchedPostsProvider(prefs, settings);
    addTearDown(watched.dispose);
  });

  final Post root = _post(2, quotes: const <int>[1]);
  final ThreadPosts thread = ThreadPosts(
    board: 'g',
    number: 1,
    posts: [
      _post(1, quotes: const <int>[]),
      root,
      _post(3, id: 'Same'),
      _post(4, id: 'Other'),
      _post(5, id: 'Same'),
      _post(6, id: 'Same', quotes: const <int>[5]),
    ],
  );

  test("a thread knows each ID's posts, oldest first", () {
    expect(
      {
        for (final MapEntry<String, List<Post>> entry
            in thread.postsById.entries)
          entry.key: [for (final Post post in entry.value) post.no],
      },
      {
        'Same': [3, 5, 6],
        'Other': [4],
      },
    );
  });

  testWidgets('an ID says how many posts it has, and opens them', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<WatchedPostsProvider>.value(value: watched),
        ],
        child: MaterialApp(
          home: ThreadReplies(post: root, thread: thread),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.textContaining('ID:Same (3)', findRichText: true),
      findsNWidgets(3),
    );
    // One post is no news.
    expect(find.textContaining('ID:Other (', findRichText: true), findsNothing);

    await tester.tapOnText(find.textRange.ofSubstring('ID:Same (3)').first);
    await tester.pumpAndSettle();

    expect(find.byType(PostsByIdPage), findsOneWidget);
    expect(find.text('ID:Same'), findsOneWidget);
    expect(find.text('3 posts'), findsOneWidget);
    for (final int no in [3, 5, 6]) {
      expect(find.text('Words of $no'), findsOneWidget, reason: '$no');
    }
    expect(find.text('Words of 4'), findsNothing);
  });
}
