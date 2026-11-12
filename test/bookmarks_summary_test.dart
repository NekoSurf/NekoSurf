import 'package:flutter/material.dart';
import 'package:flutter_chan/bookmarks/bookmark.dart';
import 'package:flutter_chan/bookmarks/bookmarks_model.dart';
import 'package:flutter_chan/home/bookmarks.dart';
import 'package:flutter_chan/home/bookmarks_summary.dart';
import 'package:flutter_chan/media/post_thumbnail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Bookmark _bookmark(String board, int no, {bool image = true}) => Bookmark(
  board: board,
  no: no,
  sub: 'Thread $no',
  imageUrl: image ? '${1700000000000 + no}s.jpg' : null,
);

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  testWidgets('counts the threads and the boards, in the order shown', (
    tester,
  ) async {
    await _pump(
      tester,
      BookmarksSummary(
        bookmarks: [_bookmark('g', 3), _bookmark('wsg', 2), _bookmark('g', 1)],
        newestFirst: true,
      ),
    );
    expect(find.text('3'), findsOneWidget);
    expect(find.text('bookmarked threads'), findsOneWidget);
    expect(find.text('from 2 boards · newest first'), findsOneWidget);
  });

  testWidgets('names the board when there is only one', (tester) async {
    await _pump(
      tester,
      BookmarksSummary(bookmarks: [_bookmark('g', 1)], newestFirst: false),
    );
    expect(find.text('1'), findsOneWidget);
    expect(find.text('bookmarked thread'), findsOneWidget);
    expect(find.text('on /g/ · oldest first'), findsOneWidget);
  });

  testWidgets('shows the newest three with a thumbnail, whatever the order', (
    tester,
  ) async {
    // Oldest first: the newest are at the end.
    final List<Bookmark> oldestFirst = [
      _bookmark('g', 1),
      _bookmark('g', 2),
      _bookmark('g', 3),
      _bookmark('g', 4, image: false),
      _bookmark('g', 5),
    ];
    await _pump(
      tester,
      BookmarksSummary(bookmarks: oldestFirst, newestFirst: false),
    );
    final List<int> shown = [
      for (final PostThumbnail t in tester.widgetList<PostThumbnail>(
        find.byType(PostThumbnail),
      ))
        t.post.no,
    ];
    // Drawn from the back, so the newest comes last, on top.
    expect(shown, [2, 3, 5]);
  });

  testWidgets('leaves out the thumbnails when no bookmark has one', (
    tester,
  ) async {
    await _pump(
      tester,
      BookmarksSummary(
        bookmarks: [_bookmark('g', 1, image: false)],
        newestFirst: true,
      ),
    );
    expect(find.byType(PostThumbnail), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets("the tab shows no card while there's nothing bookmarked", (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ChangeNotifierProvider<BookmarksProvider>(
        create: (_) => BookmarksProvider(prefs),
        child: const MaterialApp(home: Bookmarks()),
      ),
    );
    expect(find.text('No bookmarks yet'), findsOneWidget);
    expect(find.byType(BookmarksSummary), findsNothing);
  });
}
