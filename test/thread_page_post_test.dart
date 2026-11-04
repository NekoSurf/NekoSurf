import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/pages/dashboard/dashboard_style.dart';
import 'package:flutter_chan/pages/thread/thread_page_post.dart';
import 'package:flutter_chan/pages/thread/thread_post_comment.dart';
import 'package:flutter_chan/pages/thread/thread_replied_to.dart';
import 'package:flutter_chan/pages/thread/thread_replies.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _comment =
    '<a href="#p1" class="quotelink">&gt;&gt;1</a><br>Some words of a reply';

String _quoteOf(int id) => '<a href="#p$id" class="quotelink">&gt;&gt;$id</a>';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// The row of a post with [replyCount] replies.
  Future<void> pumpRow(
    WidgetTester tester, {
    required VoidCallback? onToggle,
    int replyCount = 3,
    bool folded = false,
    bool isPreview = false,
  }) async {
    final Post post = Post(no: 2, time: 1700000000, com: _comment);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeChanger>(
        create: (_) => ThemeChanger(ThemeData.dark()),
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 400,
                child: ThreadPagePost(
                  board: 'g',
                  thread: 1,
                  post: post,
                  allPosts: [Post(no: 1, time: 1700000000), post],
                  onDismiss: (_) {},
                  number: 1,
                  replyCount: replyCount,
                  onToggleFold: onToggle,
                  folded: folded,
                  isPreview: isPreview,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('folded', () {
    testWidgets('shows only its header, and unfolds when tapped', (
      tester,
    ) async {
      int folds = 0;
      await pumpRow(tester, onToggle: () => folds++, folded: true);

      expect(find.byType(ThreadPostComment), findsNothing);
      expect(
        find.textContaining('Anonymous', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('3'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.chevron_right), findsOneWidget);

      await tester.tap(find.textContaining('Anonymous', findRichText: true));
      await tester.pump(const Duration(milliseconds: 500));

      expect(folds, 1);
    });

    testWidgets('open again, shows its text', (tester) async {
      await pumpRow(tester, onToggle: () {});

      expect(find.byType(ThreadPostComment), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.chevron_down), findsOneWidget);
    });

    testWidgets('without replies, shows just an arrow', (tester) async {
      await pumpRow(tester, onToggle: () {}, replyCount: 0, folded: true);

      expect(find.byType(ThreadPostComment), findsNothing);
      expect(find.byIcon(CupertinoIcons.chevron_right), findsOneWidget);
    });

    testWidgets("can't happen to what doesn't fold", (tester) async {
      await pumpRow(tester, onToggle: null, folded: true);

      expect(find.byType(ThreadPostComment), findsOneWidget);
    });
  });

  group('a preview', () {
    testWidgets('moves here from anywhere on the row', (tester) async {
      int taps = 0;
      await pumpRow(tester, onToggle: () => taps++, isPreview: true);

      await tester.tap(find.textContaining('Anonymous', findRichText: true));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('3'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Some words of a reply'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 500));

      expect(taps, 3);
    });

    testWidgets('shows some of the post, dimmed, and no quote opens', (
      tester,
    ) async {
      await pumpRow(tester, onToggle: () {}, isPreview: true);

      expect(find.text('Some words of a reply'), findsOneWidget);
      expect(find.byType(Opacity), findsOneWidget);

      await tester.tap(find.text('OP'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(ThreadRepliesTo), findsNothing);
    });

    testWidgets('has an arrow, even without replies', (tester) async {
      await pumpRow(tester, onToggle: () {}, replyCount: 0, isPreview: true);

      expect(find.byIcon(CupertinoIcons.chevron_right), findsOneWidget);
    });
  });

  testWidgets('shows its place in the thread and its post number', (
    tester,
  ) async {
    final Post post = Post(no: 110175321, time: 1700000000, com: 'Text');
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeChanger>(
        create: (_) => ThemeChanger(ThemeData.dark()),
        child: MaterialApp(
          home: Scaffold(
            body: ThreadPagePost(
              board: 'g',
              thread: 1,
              post: post,
              allPosts: [post],
              number: 38,
              onDismiss: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.textContaining('#38   110175321', findRichText: true),
      findsOneWidget,
    );
  });

  group('quotes', () {
    Future<void> pumpQuoting(WidgetTester tester, String com) async {
      final Post post = Post(no: 3, time: 1700000000, com: com);
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeChanger>(
          create: (_) => ThemeChanger(ThemeData.dark()),
          child: MaterialApp(
            home: Scaffold(
              body: ThreadPagePost(
                board: 'g',
                thread: 1,
                post: post,
                allPosts: [
                  Post(no: 1, time: 1700000000),
                  Post(no: 2, time: 1700000000),
                  post,
                ],
                onDismiss: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    String quoting(int id) =>
        '<a href="#p$id" class="quotelink">&gt;&gt;$id</a>';

    testWidgets('name posts by their place in the thread', (tester) async {
      await pumpQuoting(tester, '${quoting(1)}<br>${quoting(2)}<br>Both');

      expect(find.text('OP'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('Both'), findsOneWidget);
    });

    testWidgets('inside a sentence are named and open the post', (
      tester,
    ) async {
      await pumpQuoting(
        tester,
        'See ${quoting(1)} and ${quoting(2)}, they are right',
      );

      expect(
        find.text('See OP and #1, they are right', findRichText: true),
        findsOneWidget,
      );

      await tester.tapOnText(find.textRange.ofSubstring('#1'));
      await tester.pumpAndSettle();

      expect(find.byType(ThreadRepliesTo), findsOneWidget);
      expect(find.text('Replies to #1'), findsOneWidget);
    });

    testWidgets('leave no gap for blank lines after the text', (tester) async {
      await pumpQuoting(tester, '<pre>Code<br></pre><br><br>');

      expect(
        find.byWidgetPredicate((w) => w is SizedBox && w.height == 8),
        findsNothing,
      );
      expect(find.byType(SelectableText), findsOneWidget);
    });

    group('of the post it is listed under', () {
      Future<void> pumpUnder(WidgetTester tester, int? repliedTo) async {
        final Post post = Post(
          no: 4,
          time: 1700000000,
          com: '${quoting(1)}<br>${quoting(2)}<br>Words',
        );
        await tester.pumpWidget(
          ChangeNotifierProvider<ThemeChanger>(
            create: (_) => ThemeChanger(ThemeData.dark()),
            child: MaterialApp(
              home: Scaffold(
                body: ThreadPagePost(
                  board: 'g',
                  thread: 1,
                  post: post,
                  allPosts: [
                    Post(no: 1, time: 1700000000),
                    Post(no: 2, time: 1700000000),
                    Post(no: 3, time: 1700000000),
                    post,
                  ],
                  repliedTo: repliedTo,
                  onDismiss: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      final Color quiet = DashColors.muted(false);

      Color colorOf(WidgetTester tester, String label) =>
          tester.widget<Text>(find.text(label)).style!.color!;

      testWidgets('stands out from the others', (tester) async {
        await pumpUnder(tester, 2);

        expect(colorOf(tester, '#1'), isNot(quiet));
        expect(colorOf(tester, 'OP'), quiet);
        expect(find.byIcon(CupertinoIcons.arrow_turn_left_up), findsOneWidget);
      });

      testWidgets('follows the place it is listed in', (tester) async {
        await pumpUnder(tester, 1);

        expect(colorOf(tester, 'OP'), isNot(quiet));
        expect(colorOf(tester, '#1'), quiet);
      });

      testWidgets('leaves them all alike if it is not one of them', (
        tester,
      ) async {
        await pumpUnder(tester, 3);

        expect(colorOf(tester, 'OP'), isNot(quiet));
        expect(colorOf(tester, '#1'), isNot(quiet));
        expect(
          find.byIcon(CupertinoIcons.arrow_turn_left_up),
          findsNWidgets(2),
        );
      });
    });

    testWidgets('keep the number of a post not in the thread', (tester) async {
      await pumpQuoting(tester, '${quoting(99)}<br>Gone');

      expect(find.text('99'), findsOneWidget);
    });

    testWidgets('of another board show as written, and do nothing', (
      tester,
    ) async {
      await pumpQuoting(
        tester,
        '<a href="/g/" class="quotelink">&gt;&gt;&gt;/g/</a>',
      );

      await tester.tapOnText(find.textRange.ofSubstring('>>>/g/'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(ThreadRepliesTo), findsNothing);
    });
  });

  group('in a list of replies, a quote', () {
    // The replies page of 2: 3 answers it, and 4 quotes both.
    final Post root = Post(no: 2, time: 1700000000);
    final List<Post> posts = [
      Post(no: 1, time: 1700000000),
      root,
      Post(no: 3, time: 1700000000, com: _quoteOf(2)),
      Post(no: 4, time: 1700000000, com: '${_quoteOf(3)}<br>Words of 4'),
    ];

    Future<void> pumpReplies(WidgetTester tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeChanger>(
          create: (_) => ThemeChanger(ThemeData.dark()),
          child: MaterialApp(
            home: ThreadReplies(
              post: root,
              thread: 1,
              board: 'g',
              allPosts: posts,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('jumps to a post in the list, without a new page', (
      tester,
    ) async {
      await pumpReplies(tester);

      await tester.tap(find.text('#2'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byType(ThreadRepliesTo), findsNothing);
      expect(find.text('Words of 4'), findsOneWidget);
    });

    testWidgets('unfolds the post it names', (tester) async {
      // 3 and 4 answer 2, and 5 quotes both, so it's listed under each.
      final Post top = Post(no: 2, time: 1700000000);
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeChanger>(
          create: (_) => ThemeChanger(ThemeData.dark()),
          child: MaterialApp(
            home: ThreadReplies(
              post: top,
              thread: 1,
              board: 'g',
              allPosts: [
                Post(no: 1, time: 1700000000),
                top,
                Post(no: 3, time: 1700000000, com: _quoteOf(2)),
                Post(
                  no: 4,
                  time: 1700000000,
                  com: '${_quoteOf(2)}<br>Words of 4',
                ),
                Post(
                  no: 5,
                  time: 1700000000,
                  com: '${_quoteOf(3)}<br>${_quoteOf(4)}',
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Words of 4'), findsOneWidget);

      // Fold 4, whose place in the thread is #3, from its header.
      await tester.tap(find.textContaining('#3   4', findRichText: true));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.text('Words of 4'), findsNothing);

      // 5 is still listed under 3: its quote of 4 brings 4 back.
      await tester.tap(find.text('#3').first);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('Words of 4'), findsOneWidget);
      expect(find.byType(ThreadRepliesTo), findsNothing);
    });

    testWidgets('opens a post that is not in the list on its own page', (
      tester,
    ) async {
      await pumpReplies(tester);

      await tester.tap(find.text('#1'));
      await tester.pumpAndSettle();

      expect(find.byType(ThreadRepliesTo), findsOneWidget);
    });
  });

  group('folding in a long list', () {
    // Replies to 2, tall enough that only a few fit on the screen.
    final Post root = Post(no: 2, time: 1700000000);
    final String tall = List<String>.filled(30, 'A line of text').join('<br>');
    final List<Post> posts = [
      Post(no: 1, time: 1700000000),
      root,
      for (int no = 3; no < 30; no++)
        Post(no: no, time: 1700000000, com: '${_quoteOf(2)}<br>$tall'),
    ];

    Future<void> pumpList(WidgetTester tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeChanger>(
          create: (_) => ThemeChanger(ThemeData.dark()),
          child: MaterialApp(
            home: ThreadReplies(
              post: root,
              thread: 1,
              board: 'g',
              allPosts: posts,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Finder header(int number) =>
        find.textContaining('#$number   ', findRichText: true);

    /// Scrolls until the header of the post at [number] is at about [y].
    Future<void> scrollHeaderTo(
      WidgetTester tester,
      int number,
      double y,
    ) async {
      for (int attempt = 0; attempt < 40; attempt++) {
        if (header(number).evaluate().isEmpty) {
          await tester.drag(find.byType(ThreadReplies), const Offset(0, -400));
        } else {
          final double at = tester.getTopLeft(header(number)).dy;
          if ((at - y).abs() < 2) {
            return;
          }
          await tester.timedDrag(
            find.byType(ThreadReplies),
            Offset(0, y - at),
            const Duration(seconds: 1),
          );
        }
        await tester.pumpAndSettle();
      }
    }

    testWidgets('a quote goes to its post, far down', (tester) async {
      final Post first = Post(
        no: 3,
        time: 1700000000,
        com: '${_quoteOf(2)}<br>${_quoteOf(28)}<br>$tall',
      );
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeChanger>(
          create: (_) => ThemeChanger(ThemeData.dark()),
          child: MaterialApp(
            home: ThreadReplies(
              post: root,
              thread: 1,
              board: 'g',
              allPosts: [posts[0], root, first, ...posts.skip(3)],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(header(2), findsOneWidget);

      await tester.tap(find.text('#27'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(header(27), findsOneWidget);
      expect(header(2), findsNothing);
    });

    testWidgets('keeps its header where it was', (tester) async {
      await pumpList(tester);
      await scrollHeaderTo(tester, 6, 300);
      final double before = tester.getTopLeft(header(6)).dy;

      await tester.tap(header(6));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(tester.getTopLeft(header(6)).dy, closeTo(before, 1));
    });

    testWidgets('keeps it there on unfolding too', (tester) async {
      await pumpList(tester);
      await scrollHeaderTo(tester, 6, 300);
      await tester.tap(header(6));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      final double before = tester.getTopLeft(header(6)).dy;

      await tester.tap(header(6));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(tester.getTopLeft(header(6)).dy, closeTo(before, 1));
    });

    testWidgets('brings a header above the screen back into view', (
      tester,
    ) async {
      await pumpList(tester);
      await scrollHeaderTo(tester, 6, 100);
      await tester.timedDrag(
        find.byType(ThreadReplies),
        const Offset(0, -220),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(header(6)).dy, lessThan(0));

      await tester.tapAt(const Offset(300, 200));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final double at = tester.getTopLeft(header(6)).dy;
      expect(at, greaterThanOrEqualTo(0));
      expect(at, lessThan(200));
    });
  });

  group('tapping a post', () {
    late int folds;

    setUp(() => folds = 0);

    testWidgets('folds from the header', (tester) async {
      await pumpRow(tester, onToggle: () => folds++);

      await tester.tap(find.textContaining('Anonymous'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(folds, 1);
    });

    testWidgets('folds from the empty space', (tester) async {
      await pumpRow(tester, onToggle: () => folds++);

      // Beside the reply count's row of text, past the end of the words.
      await tester.tapAt(
        tester.getBottomRight(find.byType(ThreadPagePost)) - const Offset(4, 4),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(folds, 1);
    });

    testWidgets(
      'folds from the text, which keeps long-press to select',
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      (tester) async {
        await pumpRow(tester, onToggle: () => folds++);

        await tester.tap(find.text('Some words of a reply'));
        await tester.pump(const Duration(milliseconds: 500));
        expect(folds, 1);

        await tester.longPress(find.text('Some words of a reply'));
        await tester.pump(const Duration(milliseconds: 500));
        expect(folds, 1);
      },
    );

    testWidgets('folds once from the reply count', (tester) async {
      await pumpRow(tester, onToggle: () => folds++);

      await tester.tap(find.text('3'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(folds, 1);
    });

    testWidgets('a quote link opens its post instead', (tester) async {
      await pumpRow(tester, onToggle: () => folds++);

      await tester.tap(find.text('OP'));
      await tester.pumpAndSettle();

      expect(folds, 0);
      expect(find.byType(ThreadRepliesTo), findsOneWidget);
    });

    testWidgets('folds without replies too', (tester) async {
      await pumpRow(tester, onToggle: () => folds++, replyCount: 0);

      await tester.tap(find.textContaining('Anonymous'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(folds, 1);
    });
  });
}
