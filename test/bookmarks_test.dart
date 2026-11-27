import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_chan/bookmarks/bookmark.dart';
import 'package:flutter_chan/bookmarks/bookmarks_model.dart';
import 'package:flutter_chan/history/watched_posts_model.dart';
import 'package:flutter_chan/home/bookmarks.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Bookmark _bookmark(String board, int no) =>
    Bookmark(board: board, no: no, sub: 'Thread $no');

void main() {
  late SettingsProvider settings;
  late WatchedPostsProvider watched;
  late BookmarksProvider bookmarks;

  /// The Bookmarks tab with [saved] bookmarked.
  Future<void> pumpBookmarks(
    WidgetTester tester, [
    List<Bookmark> saved = const <Bookmark>[],
  ]) async {
    SharedPreferences.setMockInitialValues({
      'favoriteThreads': [for (final b in saved) jsonEncode(b.toJson())],
    });
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    settings = SettingsProvider(prefs);
    watched = WatchedPostsProvider(prefs);
    addTearDown(watched.dispose);
    bookmarks = BookmarksProvider(prefs);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<WatchedPostsProvider>.value(value: watched),
          ChangeNotifierProvider<BookmarksProvider>.value(value: bookmarks),
        ],
        child: const MaterialApp(home: Bookmarks()),
      ),
    );
    await tester.pump();
  }

  testWidgets('with nothing bookmarked, it says how to bookmark', (
    tester,
  ) async {
    await pumpBookmarks(tester);

    expect(find.text('No bookmarks yet'), findsOneWidget);
    // Outside the tabs, there's no Boards tab to go to.
    expect(find.text('Browse boards'), findsNothing);
  });

  testWidgets('threads without new replies are only listed', (tester) async {
    await pumpBookmarks(tester, [_bookmark('g', 1), _bookmark('g', 2)]);

    expect(find.text('New replies'), findsNothing);
    expect(find.text('All bookmarks'), findsNothing);
    expect(find.text('Thread 1'), findsOneWidget);
  });

  testWidgets('a thread with new replies is a card above the list', (
    tester,
  ) async {
    await pumpBookmarks(tester, [_bookmark('g', 1), _bookmark('g', 2)]);

    // Read when it had no replies; two have come since.
    watched.noteThreadPosts(2, [2]);
    watched.noteThreadPosts(2, [2, 3, 4]);
    await tester.pump();

    expect(find.text('New replies'), findsOneWidget);
    expect(find.text('All bookmarks'), findsOneWidget);
    expect(find.text('+2'), findsOneWidget);
    // On its card, and in the list.
    expect(find.text('Thread 2'), findsNWidgets(2));
    expect(find.text('Thread 1'), findsOneWidget);
    // Read positions are stored a moment later.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('clearing asks first, and Cancel keeps them', (tester) async {
    await pumpBookmarks(tester, [_bookmark('g', 1)]);

    await tester.tap(find.bySemanticsLabel('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear bookmarks'));
    await tester.pumpAndSettle();
    expect(find.text('Clear all 1 bookmark?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(bookmarks.bookmarks, hasLength(1));
  });
}
