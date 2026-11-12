import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chan/ui/dash_header.dart';
import 'package:flutter_chan/ui/frosted.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const List<DashTab> tabs = [
    DashTab(CupertinoIcons.square_grid_2x2_fill, 'Boards'),
    DashTab(CupertinoIcons.paperclip, 'Saved'),
    DashTab(CupertinoIcons.bookmark_fill, 'Bookmarks', count: 3),
    DashTab(CupertinoIcons.settings, 'Settings'),
  ];

  Future<List<int>> pumpBar(WidgetTester tester) async {
    final List<int> tapped = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: DashTabBar(
              tabs: tabs,
              selectedIndex: 0,
              onSelected: tapped.add,
            ),
          ),
        ),
      ),
    );
    return tapped;
  }

  testWidgets('is as wide as its tabs, not the page', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpBar(tester);

    final Rect bar = tester.getRect(find.byType(Frosted));
    expect(bar.width, lessThan(430 - 32));
    // In the middle.
    expect(bar.center.dx, 215);
    expect(
      tester.getCenter(find.text('Saved')).dx,
      lessThan(tester.getCenter(find.text('Bookmarks')).dx),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a tab, even the one shown, says so with a click', (
    tester,
  ) async {
    final List<MethodCall> haptics = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call);
        }
        return null;
      },
    );
    final List<int> tapped = await pumpBar(tester);

    await tester.tap(find.text('Boards'));
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(tapped, [0, 3]);
    expect(haptics, hasLength(2));
  });

  testWidgets('shows how many are new on a tab', (tester) async {
    await pumpBar(tester);
    expect(find.text('3'), findsOneWidget);
    expect(find.bySemanticsLabel('Bookmarks, 3 unread'), findsOneWidget);
  });
}
