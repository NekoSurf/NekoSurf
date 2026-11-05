import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/Models/post.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/blocs/watched_posts_model.dart';
import 'package:flutter_chan/enums/enums.dart';
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
  late SettingsProvider settings;
  late WatchedPostsProvider watched;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    settings = SettingsProvider(prefs);
    watched = WatchedPostsProvider(prefs);
    addTearDown(watched.dispose);
  });

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

    testWidgets('of another board show as written', (tester) async {
      await pumpQuoting(
        tester,
        '<a href="/g/" class="quotelink">&gt;&gt;&gt;/g/</a>',
      );

      expect(find.textContaining('>>>/g/', findRichText: true), findsOneWidget);
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
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeChanger>(
              create: (_) => ThemeChanger(ThemeData.dark()),
            ),
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ChangeNotifierProvider<WatchedPostsProvider>.value(value: watched),
          ],
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
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeChanger>(
              create: (_) => ThemeChanger(ThemeData.dark()),
            ),
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ChangeNotifierProvider<WatchedPostsProvider>.value(value: watched),
          ],
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
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeChanger>(
              create: (_) => ThemeChanger(ThemeData.dark()),
            ),
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ChangeNotifierProvider<WatchedPostsProvider>.value(value: watched),
          ],
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
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeChanger>(
              create: (_) => ThemeChanger(ThemeData.dark()),
            ),
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ChangeNotifierProvider<WatchedPostsProvider>.value(value: watched),
          ],
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

    testWidgets(
      'a quote of the last post stops at the end, without going past it',
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      (tester) async {
        // Short posts, so that the last one can't reach the top of the screen.
        final Post first = Post(
          no: 3,
          time: 1700000000,
          com: '${_quoteOf(2)}<br>${_quoteOf(40)}<br>Words of 3',
        );
        final List<Post> short = [
          Post(no: 1, time: 1700000000),
          root,
          first,
          for (int no = 4; no <= 40; no++)
            Post(
              no: no,
              time: 1700000000,
              com: '${_quoteOf(2)}<br>Words of $no',
            ),
        ];
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeChanger>(
                create: (_) => ThemeChanger(ThemeData.dark()),
              ),
              ChangeNotifierProvider<SettingsProvider>.value(value: settings),
              ChangeNotifierProvider<WatchedPostsProvider>.value(
                value: watched,
              ),
            ],
            child: MaterialApp(
              home: ThreadReplies(
                post: root,
                thread: 1,
                board: 'g',
                allPosts: short,
              ),
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.text('#39'));
        final Finder last = find.text('Words of 40');
        final Finder approaching = find.text('Words of 36');
        final double screen = tester.getSize(find.byType(ThreadReplies)).height;
        double highest = screen;
        double? previous;
        double lastStep = 0;
        for (int frame = 0; frame < 120; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          // While the list it fades to is being set up, it can't be seen.
          if (frame > 3 && last.evaluate().isNotEmpty) {
            final double bottom = tester.getBottomLeft(last).dy;
            highest = bottom < highest ? bottom : highest;
          }
          // Higher up, this one is on screen for the way in.
          if (frame > 3 && approaching.evaluate().isNotEmpty) {
            final double top = tester.getTopLeft(approaching).dy;
            if (previous != null && (top - previous).abs() > 0.01) {
              lastStep = (top - previous).abs();
            }
            previous = top;
          }
        }
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // It never leaves empty space below the last post.
        expect(last, findsOneWidget);
        expect(highest, greaterThan(screen - 80));
        // And it slows down into place, rather than being cut off at speed.
        expect(lastStep, lessThan(4));
      },
    );

    testWidgets(
      'a quote of a post already on screen slows down at the end too',
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      (tester) async {
        // About a screen and a half of short posts, with the quoted one in view.
        final Post first = Post(
          no: 3,
          time: 1700000000,
          com: '${_quoteOf(2)}<br>${_quoteOf(7)}<br>Words of 3',
        );
        final List<Post> short = [
          Post(no: 1, time: 1700000000),
          root,
          first,
          for (int no = 4; no <= 10; no++)
            Post(
              no: no,
              time: 1700000000,
              com: '${_quoteOf(2)}<br>Words of $no',
            ),
        ];
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeChanger>(
                create: (_) => ThemeChanger(ThemeData.dark()),
              ),
              ChangeNotifierProvider<SettingsProvider>.value(value: settings),
              ChangeNotifierProvider<WatchedPostsProvider>.value(
                value: watched,
              ),
            ],
            child: MaterialApp(
              home: ThreadReplies(
                post: root,
                thread: 1,
                board: 'g',
                allPosts: short,
              ),
            ),
          ),
        );
        await tester.pump();
        final Finder quoted = find.text('Words of 7');
        expect(quoted, findsOneWidget);

        await tester.tap(find.text('#6'));
        double? previous;
        double lastStep = 0;
        double travelled = 0;
        for (int frame = 0; frame < 60; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          final double top = tester.getTopLeft(quoted).dy;
          if (previous != null && (top - previous).abs() > 0.01) {
            lastStep = (top - previous).abs();
            travelled += lastStep;
          }
          previous = top;
        }
        await tester.pumpAndSettle(const Duration(seconds: 2));

        expect(travelled, greaterThan(0));
        expect(lastStep, lessThan(4));
      },
    );

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

  group('in the flat layout', () {
    // The replies page of 2: 3 answers it, 4 answers 3, and 5 answers 2 and 3.
    final Post root = Post(no: 2, time: 1700000000);
    final List<Post> posts = [
      Post(no: 1, time: 1700000000),
      root,
      Post(no: 3, time: 1700000000, com: '${_quoteOf(2)}<br>Words of 3'),
      Post(no: 4, time: 1700000000, com: '${_quoteOf(3)}<br>Words of 4'),
      Post(
        no: 5,
        time: 1700000000,
        com: '${_quoteOf(2)}<br>${_quoteOf(3)}<br>Words of 5',
      ),
    ];

    Future<void> pumpFlat(WidgetTester tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeChanger>(
              create: (_) => ThemeChanger(ThemeData.dark()),
            ),
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ChangeNotifierProvider<WatchedPostsProvider>.value(value: watched),
          ],
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

    setUp(() => settings.setThreadLayout(ThreadLayout.flat));

    double topOf(WidgetTester tester, String words) =>
        tester.getTopLeft(find.text(words)).dy;

    double leftOf(WidgetTester tester, String words) =>
        tester.getTopLeft(find.text(words)).dx;

    testWidgets('lists each post once, in order, without indents', (
      tester,
    ) async {
      await pumpFlat(tester);

      expect(find.text('Words of 5'), findsOneWidget);
      expect(
        topOf(tester, 'Words of 3'),
        lessThan(topOf(tester, 'Words of 4')),
      );
      expect(
        topOf(tester, 'Words of 4'),
        lessThan(topOf(tester, 'Words of 5')),
      );
      expect(leftOf(tester, 'Words of 4'), leftOf(tester, 'Words of 3'));
    });

    testWidgets('tapping a post folds just that post', (tester) async {
      await pumpFlat(tester);

      await tester.tap(find.text('Words of 4'));
      await tester.pumpAndSettle();

      expect(find.text('Words of 4'), findsNothing);
      expect(find.text('Words of 5'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.chevron_right), findsOneWidget);
    });

    testWidgets('tapping it again brings it back', (tester) async {
      await pumpFlat(tester);

      await tester.tap(find.text('Words of 4'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(CupertinoIcons.chevron_right));
      await tester.pumpAndSettle();

      expect(find.text('Words of 4'), findsOneWidget);
    });

    testWidgets('a folded post with replies still opens them from its count', (
      tester,
    ) async {
      await pumpFlat(tester);

      await tester.tap(find.text('Words of 3'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(CupertinoIcons.reply));
      await tester.pumpAndSettle();

      expect(find.text('Replies to #2'), findsOneWidget);
    });

    testWidgets('its count opens its replies', (tester) async {
      await pumpFlat(tester);

      await tester.tap(find.byIcon(CupertinoIcons.reply));
      await tester.pumpAndSettle();

      expect(find.text('Replies to #2'), findsOneWidget);
    });

    testWidgets('no quote stands out, as no post is under another', (
      tester,
    ) async {
      await pumpFlat(tester);

      // 5 quotes 2 and 3; under 3 in the nested layout, only that one would.
      expect(find.byIcon(CupertinoIcons.arrow_turn_left_up), findsNWidgets(4));
    });

    testWidgets('a quote still jumps, without a new page', (tester) async {
      await pumpFlat(tester);

      await tester.tap(find.text('#2').last);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byType(ThreadRepliesTo), findsNothing);
    });

    testWidgets('switching in Settings relays the open list', (tester) async {
      await pumpFlat(tester);
      final double flat = leftOf(tester, 'Words of 4');

      await settings.setThreadLayout(ThreadLayout.nested);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(leftOf(tester, 'Words of 4'), greaterThan(flat));

      await settings.setThreadLayout(ThreadLayout.flat);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(leftOf(tester, 'Words of 4'), flat);
    });
  });

  group('new posts', () {
    // The replies page of 2: 3 answers it, and 4 and 5 answer 3.
    final Post root = Post(no: 2, time: 1700000000);
    final String tall = List<String>.filled(60, 'A line of text').join('<br>');
    final List<Post> posts = [
      Post(no: 1, time: 1700000000),
      root,
      Post(no: 3, time: 1700000000, com: '${_quoteOf(2)}<br>Words of 3'),
      Post(no: 4, time: 1700000000, com: '${_quoteOf(3)}<br>Words of 4'),
      Post(no: 5, time: 1700000000, com: '${_quoteOf(3)}<br>Words of 5'),
      Post(no: 6, time: 1700000000, com: '${_quoteOf(2)}<br>$tall'),
      Post(no: 7, time: 1700000000, com: '${_quoteOf(6)}<br>Words of 7'),
      Post(no: 8, time: 1700000000, com: '${_quoteOf(2)}<br>Words of 8'),
      Post(no: 9, time: 1700000000, com: '${_quoteOf(2)}<br>$tall'),
    ];

    Future<void> pumpNew(WidgetTester tester, Set<int> unseen) async {
      watched.noteThreadPosts(1, const <int>[1, 2]);
      watched.noteThreadPosts(1, <int>[1, 2, 3, 4, 5, 6, 7, 8, 9]);
      watched.markPostsSeen(1, <int>{3, 4, 5, 6, 7, 8, 9}.difference(unseen));
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeChanger>(
              create: (_) => ThemeChanger(ThemeData.dark()),
            ),
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ChangeNotifierProvider<WatchedPostsProvider>.value(value: watched),
          ],
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

    // They're saved a moment after they change.
    Future<void> saveNewPosts(WidgetTester tester) =>
        tester.pump(const Duration(seconds: 3));

    bool isTinted(WidgetTester tester, String words) {
      final AnimatedContainer box = tester.widget<AnimatedContainer>(
        find
            .ancestor(
              of: find.text(words),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      return (box.decoration! as BoxDecoration).color !=
          DashColors.accent.withValues(alpha: 0);
    }

    testWidgets('are tinted, and the others are not', (tester) async {
      await pumpNew(tester, {4});

      expect(isTinted(tester, 'Words of 4'), isTrue);
      expect(isTinted(tester, 'Words of 3'), isFalse);
      await saveNewPosts(tester);
    });

    testWidgets('stop being unseen once on screen, but stay tinted', (
      tester,
    ) async {
      await pumpNew(tester, {4});
      await tester.pumpAndSettle();

      expect(watched.unseenPosts(1), isEmpty);
      expect(isTinted(tester, 'Words of 4'), isTrue);
      await saveNewPosts(tester);
    });

    testWidgets('stay unseen while below the screen', (tester) async {
      await pumpNew(tester, {4, 8});
      await tester.pumpAndSettle();

      expect(watched.unseenPosts(1), {8});
      await saveNewPosts(tester);
    });

    testWidgets('folded away stay unseen, counted by the post on screen', (
      tester,
    ) async {
      await pumpNew(tester, {7});
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('#5   ', findRichText: true));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('1 new'), findsOneWidget);
      expect(watched.unseenPosts(1), {7});
      await saveNewPosts(tester);
    });

    testWidgets("posts passed on the way to a quote aren't seen", (
      tester,
    ) async {
      final Post first = Post(
        no: 3,
        time: 1700000000,
        com: '${_quoteOf(2)}<br>${_quoteOf(15)}<br>Words of 3',
      );
      final List<Post> many = [
        Post(no: 1, time: 1700000000),
        root,
        first,
        for (int no = 4; no <= 30; no++)
          Post(no: no, time: 1700000000, com: '${_quoteOf(2)}<br>Words of $no'),
      ];
      watched.noteThreadPosts(1, const <int>[1, 2]);
      watched.noteThreadPosts(1, <int>[for (final Post p in many) p.no!]);
      watched.markPostsSeen(1, <int>[
        for (final Post p in many)
          if (p.no != 10) p.no!,
      ]);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeChanger>(
              create: (_) => ThemeChanger(ThemeData.dark()),
            ),
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ChangeNotifierProvider<WatchedPostsProvider>.value(value: watched),
          ],
          child: MaterialApp(
            home: ThreadReplies(
              post: root,
              thread: 1,
              board: 'g',
              allPosts: many,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('#14'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('Words of 15'), findsOneWidget);
      expect(find.text('Words of 10'), findsNothing);
      expect(watched.unseenPosts(1), {10});
      await saveNewPosts(tester);
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
