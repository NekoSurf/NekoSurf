import 'package:flutter/material.dart';
import 'package:flutter_chan/board/favorite_model.dart';
import 'package:flutter_chan/bookmarks/bookmarks_model.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/history/history_model.dart';
import 'package:flutter_chan/history/watched_posts_model.dart';
import 'package:flutter_chan/home/dashboard.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/ui/dash_header.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Boards tab, with [visited] in History.
Future<SettingsProvider> _pumpBoards(
  WidgetTester tester, {
  List<Post> visited = const [],
  bool showContinueReading = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final SettingsProvider settings = SettingsProvider(prefs);
  await settings.showContinueReading.set(showContinueReading);
  final HistoryProvider history = HistoryProvider(prefs, settings);
  for (final Post post in visited) {
    await history.recordThread(post);
  }
  final WatchedPostsProvider watched = WatchedPostsProvider(prefs);
  addTearDown(watched.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<HistoryProvider>.value(value: history),
        ChangeNotifierProvider<WatchedPostsProvider>.value(value: watched),
        ChangeNotifierProvider<FavoriteProvider>(
          create: (_) => FavoriteProvider(prefs),
        ),
        ChangeNotifierProvider<BookmarksProvider>(
          create: (_) => BookmarksProvider(prefs),
        ),
      ],
      child: const MaterialApp(home: Dashboard()),
    ),
  );
  await tester.pump();
  return settings;
}

/// The clock in the header.
final Finder _historyButton = find.byWidgetPredicate(
  (w) => w is DashIconButton && w.label == 'History',
);

void main() {
  final Post thread = Post(board: 'g', no: 1, sub: 'A thread');

  testWidgets('Continue reading links to History in place of the header', (
    tester,
  ) async {
    await _pumpBoards(tester, visited: [thread]);
    expect(find.text('Continue reading'), findsOneWidget);
    // Its link, and no clock in the header.
    expect(find.text('History'), findsOneWidget);
    expect(_historyButton, findsNothing);
  });

  testWidgets('turned off, the header has History again', (tester) async {
    final SettingsProvider settings = await _pumpBoards(
      tester,
      visited: [thread],
      showContinueReading: false,
    );
    expect(find.text('Continue reading'), findsNothing);
    expect(_historyButton, findsOneWidget);

    await settings.showContinueReading.set(true);
    await tester.pump();
    expect(find.text('Continue reading'), findsOneWidget);
    expect(_historyButton, findsNothing);
  });

  testWidgets('with nothing read yet, the header has History', (tester) async {
    await _pumpBoards(tester);
    expect(find.text('Continue reading'), findsNothing);
    expect(_historyButton, findsOneWidget);
  });
}
