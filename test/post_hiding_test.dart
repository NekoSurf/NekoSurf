import 'package:flutter/material.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/history/watched_posts_model.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/thread/post_hiding.dart';
import 'package:flutter_chan/thread/posts_by_id_page.dart';
import 'package:flutter_chan/thread/thread_posts.dart';
import 'package:flutter_chan/thread/thread_replies.dart';
import 'package:flutter_chan/thread/thread_rows.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _quoteOf(int id) => '<a href="#p$id" class="quotelink">&gt;&gt;$id</a>';

/// A reply to 2, with words saying which it is.
Post _reply(
  int no, {
  String? id,
  String? name,
  String? trip,
  String? countryName,
  List<int> quotes = const <int>[2],
}) => Post(
  board: 'g',
  no: no,
  time: 1700000000,
  name: name ?? 'Poster$no',
  id: id,
  trip: trip,
  countryName: countryName,
  com: [
    for (final int quote in quotes) _quoteOf(quote),
    'Words of $no',
  ].join('<br>'),
);

void main() {
  group('a post filter', () {
    test('is stored and read back as it was', () {
      for (final PostFilter filter in [
        PostFilter(PostFilterKind.text, r'crypto|a:b'),
        PostFilter(PostFilterKind.name, 'Bob'),
        PostFilter(PostFilterKind.trip, '!!Abc'),
        PostFilter(PostFilterKind.country, 'United Kingdom'),
      ]) {
        expect(PostFilter.parse(filter.stored), filter);
      }
      expect(PostFilter.parse('nonsense'), isNull);
      expect(PostFilter.parse('colour:red'), isNull);
      expect(PostFilter.parse('name:  '), isNull);
    });

    test('matches text by keyword or regex, in any case', () {
      final Post post = Post(
        board: 'g',
        no: 3,
        sub: 'A Title',
        com: 'Buy CRYPTO now',
      );
      expect(PostFilter(PostFilterKind.text, 'crypto').matches(post), isTrue);
      expect(PostFilter(PostFilterKind.text, r'buy\s+c').matches(post), isTrue);
      expect(PostFilter(PostFilterKind.text, 'title').matches(post), isTrue);
      expect(PostFilter(PostFilterKind.text, 'stocks').matches(post), isFalse);
      // Taken as the words it is, not an error.
      expect(PostFilter(PostFilterKind.text, '(now').matches(post), isFalse);
    });

    test('matches a name, tripcode or country exactly', () {
      final Post post = _reply(
        3,
        name: 'Bob',
        trip: '!!Abc',
        countryName: 'France',
      );
      expect(PostFilter(PostFilterKind.name, 'Bob').matches(post), isTrue);
      expect(PostFilter(PostFilterKind.name, 'bo').matches(post), isFalse);
      expect(PostFilter(PostFilterKind.trip, '!!Abc').matches(post), isTrue);
      expect(PostFilter(PostFilterKind.trip, '!!abc').matches(post), isFalse);
      expect(
        PostFilter(PostFilterKind.country, 'France').matches(post),
        isTrue,
      );
      expect(
        PostFilter(PostFilterKind.country, 'Germany').matches(post),
        isFalse,
      );
    });
  });

  test('what is hidden says why, and never the opening post', () {
    final List<Post> posts = [
      _reply(1, name: 'Bob', quotes: const <int>[]),
      _reply(2, quotes: const <int>[]),
      _reply(3, id: 'Id3'),
      _reply(4, name: 'Bob'),
      _reply(5),
    ];
    final PostHiding hiding = PostHiding(
      filters: [PostFilter(PostFilterKind.name, 'Bob')],
      posts: const <int>{2},
      ids: const <String>{'Id3'},
    );

    expect(hiding.reasonsIn(posts), <int, String>{
      2: 'Hidden by you',
      3: 'Hidden · ID:Id3',
      4: 'Hidden · Bob',
    });
  });

  group('kept on the phone', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('filters, once each', () async {
      final SettingsProvider settings = SettingsProvider(prefs);
      final List<PostFilter> before = settings.postFilters;
      await settings.addPostFilter(PostFilter(PostFilterKind.name, 'Bob'));
      await settings.addPostFilter(PostFilter(PostFilterKind.name, 'Bob'));
      await settings.addPostFilter(PostFilter(PostFilterKind.text, ' x '));
      // A new list, so what lists posts knows to look again.
      expect(identical(settings.postFilters, before), isFalse);

      expect(SettingsProvider(prefs).postFilters, [
        PostFilter(PostFilterKind.name, 'Bob'),
        PostFilter(PostFilterKind.text, 'x'),
      ]);

      await settings.removePostFilter(PostFilter(PostFilterKind.name, 'Bob'));
      expect(SettingsProvider(prefs).postFilters, [
        PostFilter(PostFilterKind.text, 'x'),
      ]);
    });

    test('posts and IDs hidden in a thread', () async {
      final SettingsProvider settings = SettingsProvider(prefs);
      final WatchedPostsProvider watched = WatchedPostsProvider(
        prefs,
        settings,
      );

      watched.setPostHidden(1, 3, hidden: true);
      watched.setIdHidden(1, 'Abc', hidden: true);
      expect(watched.hidingChanges, 2);
      // Hiding what's hidden changes nothing.
      watched.setPostHidden(1, 3, hidden: true);
      expect(watched.hidingChanges, 2);
      // Saves what's waiting to be.
      watched.dispose();

      final WatchedPostsProvider reloaded = WatchedPostsProvider(
        prefs,
        settings,
      );
      addTearDown(reloaded.dispose);
      expect(reloaded.threadMemory(1)!.hiddenPosts, {3});
      expect(reloaded.threadMemory(1)!.hiddenIds, {'Abc'});

      reloaded.setPostHidden(1, 3, hidden: false);
      expect(reloaded.threadMemory(1)!.hiddenPosts, isEmpty);
    });
  });

  group('rows', () {
    // 3 answers 2, and 4 answers 3.
    final List<Post> posts = [
      _reply(1, quotes: const <int>[]),
      _reply(2, quotes: const <int>[1]),
      _reply(3),
      _reply(4, quotes: const <int>[3]),
      _reply(5),
    ];

    test('of a hidden post fold its replies away below it', () {
      final List<ThreadRow> rows = buildNestedRows(
        posts,
        children: buildReplyChildrenIndex(posts),
        hidden: const <int>{1, 3},
        unseen: const <int>{4},
      );

      expect(rows.map((ThreadRow row) => row.post.no), [1, 2, 3, 5]);
      expect(rows[0].hidden, isFalse, reason: 'the opening post');
      expect(rows[2].hidden, isTrue);
      expect(rows[2].collapsed, isFalse);
      expect(rows[2].replyCount, 1);
      expect(rows[2].newReplies, 1);
    });

    test('flat, are hidden one by one, but never the first', () {
      final List<ThreadRow> rows = buildFlatRows(
        posts,
        replyCounts: const <int, int>{},
        hidden: const <int>{1, 3},
      );

      expect(rows.map((ThreadRow row) => row.post.no), [1, 2, 3, 4, 5]);
      expect(
        [for (final ThreadRow row in rows) row.hidden],
        [false, false, true, false, false],
      );
    });
  });

  group('in a thread', () {
    late SettingsProvider settings;
    late WatchedPostsProvider watched;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      settings = SettingsProvider(prefs);
      watched = WatchedPostsProvider(prefs, settings);
      addTearDown(watched.dispose);
    });

    final Post root = _reply(2, quotes: const <int>[1]);
    final List<Post> posts = [
      _reply(1, quotes: const <int>[]),
      root,
      _reply(3, id: 'Same', countryName: 'France'),
      _reply(4, id: 'Other'),
      _reply(5, id: 'Same', name: 'Bob'),
      _reply(6, id: 'Same', quotes: const <int>[5]),
    ];
    final ThreadPosts thread = ThreadPosts(board: 'g', number: 1, posts: posts);

    Future<void> pumpThread(WidgetTester tester) async {
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
    }

    /// Holds the post by [poster].
    Future<void> hold(WidgetTester tester, String poster) async {
      await tester.longPress(find.textContaining(poster, findRichText: true));
      await tester.pumpAndSettle();
    }

    // The toast saying what happened goes away by itself, and what changed is
    // saved a moment later.
    Future<void> waitOutToast(WidgetTester tester) async {
      // It waits once it's faded in.
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    }

    testWidgets('holding a post lifts it off the list, with its menu', (
      tester,
    ) async {
      await pumpThread(tester);
      Opacity original() => tester.widget<Opacity>(
        find
            .ancestor(
              of: find.text('Words of 4').first,
              matching: find.byType(Opacity),
            )
            .first,
      );

      await hold(tester, 'Poster4');
      // The copy over the blurred page, and the post in the list, out of sight.
      expect(find.text('Words of 4'), findsNWidgets(2));
      expect(original().opacity, 0);
      expect(find.byType(BackdropFilter), findsWidgets);
      expect(find.text('Hide this post'), findsOneWidget);

      // Tapping beside it puts it back.
      await tester.tapAt(const Offset(390, 1590));
      await tester.pumpAndSettle();
      expect(find.text('Hide this post'), findsNothing);
      expect(find.text('Words of 4'), findsOneWidget);
      expect(original().opacity, 1);
      expect(watched.threadMemory(1)?.hiddenPosts ?? const <int>{}, isEmpty);
    });

    testWidgets('holding a post hides it, and tapping it shows it', (
      tester,
    ) async {
      await pumpThread(tester);
      expect(find.text('Words of 4'), findsOneWidget);

      await hold(tester, 'Poster4');
      await tester.tap(find.text('Hide this post'));
      await tester.pumpAndSettle();
      expect(find.text('Words of 4'), findsNothing);
      expect(find.text('Hidden by you'), findsOneWidget);
      expect(watched.threadMemory(1)!.hiddenPosts, {4});
      await waitOutToast(tester);

      await tester.tap(find.text('Hidden by you'));
      await tester.pump();
      expect(find.text('Words of 4'), findsOneWidget);
      // Only for now: it's still hidden, and says so above it.
      expect(watched.threadMemory(1)!.hiddenPosts, {4});
      expect(find.text('Hidden by you'), findsOneWidget);
      expect(find.text('Hide'), findsOneWidget);

      await hold(tester, 'Poster4');
      await tester.tap(find.text('Stop hiding this post'));
      await tester.pumpAndSettle();
      expect(watched.threadMemory(1)!.hiddenPosts, isEmpty);
      expect(find.text('Hidden by you'), findsNothing);
      await waitOutToast(tester);

      // Hidden again later, it's hidden right away, not still shown.
      await hold(tester, 'Poster4');
      await tester.tap(find.text('Hide this post'));
      await tester.pumpAndSettle();
      expect(find.text('Words of 4'), findsNothing);
      await waitOutToast(tester);
    });

    testWidgets('a post shown anyway can be hidden again', (tester) async {
      await pumpThread(tester);
      watched.setPostHidden(1, 4, hidden: true);
      await tester.pump();

      await tester.tap(find.text('Show'));
      await tester.pump();
      expect(find.text('Words of 4'), findsOneWidget);

      await tester.tap(find.text('Hide'));
      await tester.pump();
      expect(find.text('Words of 4'), findsNothing);
      expect(find.text('Show'), findsOneWidget);
      expect(watched.threadMemory(1)!.hiddenPosts, {4});
      await waitOutToast(tester);
    });

    testWidgets("hiding an ID hides that poster's posts in the thread", (
      tester,
    ) async {
      await pumpThread(tester);

      await hold(tester, 'Poster3');
      await tester.tap(find.text('Hide ID:Same'));
      await tester.pumpAndSettle();

      expect(find.text('Words of 3'), findsNothing);
      expect(find.text('Words of 5'), findsNothing);
      // Under 5 in the nested list, so folded away with it.
      expect(find.text('Words of 6'), findsNothing);
      expect(find.text('Hidden · ID:Same'), findsNWidgets(2));
      expect(find.text('Words of 4'), findsOneWidget);
      await waitOutToast(tester);
    });

    testWidgets('a name or country is hidden in every thread', (tester) async {
      await pumpThread(tester);

      await hold(tester, 'Bob');
      await tester.tap(find.text('Hide posts by Bob'));
      await tester.pumpAndSettle();
      expect(find.text('Hidden · Bob'), findsOneWidget);
      await waitOutToast(tester);

      await hold(tester, 'Poster3');
      await tester.tap(find.text('Hide posts from France'));
      await tester.pumpAndSettle();
      expect(find.text('Hidden · From France'), findsOneWidget);
      await waitOutToast(tester);

      expect(settings.postFilters, [
        PostFilter(PostFilterKind.name, 'Bob'),
        PostFilter(PostFilterKind.country, 'France'),
      ]);
    });

    testWidgets('a filter added elsewhere hides posts here at once', (
      tester,
    ) async {
      await pumpThread(tester);

      await settings.addPostFilter(PostFilter(PostFilterKind.text, 'of 4'));
      await tester.pump();
      expect(find.text('Words of 4'), findsNothing);
      expect(find.text('Hidden · “of 4”'), findsOneWidget);

      await settings.removePostFilter(PostFilter(PostFilterKind.text, 'of 4'));
      await tester.pump();
      expect(find.text('Words of 4'), findsOneWidget);
    });

    testWidgets('the menu opens them too, even when they are hidden', (
      tester,
    ) async {
      await pumpThread(tester);
      watched.setIdHidden(1, 'Same', hidden: true);
      await tester.pump();

      await tester.longPress(find.text('Hidden · ID:Same').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('3 posts by this ID'));
      await tester.pumpAndSettle();

      expect(find.byType(PostsByIdPage), findsOneWidget);
      expect(find.text('Words of 5'), findsOneWidget);
      await waitOutToast(tester);
    });
  });
}
