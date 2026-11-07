import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_chan/ui/pull_to_refresh.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<int> pumpList(
    WidgetTester tester, {
    required List<int> refreshes,
    bool fromBottom = false,
    int items = 3,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PullToRefresh(
          fromBottom: fromBottom,
          onRefresh: () async {
            refreshes.add(1);
            await Future<void>.delayed(const Duration(milliseconds: 100));
          },
          child: ListView(
            physics: PullToRefresh.pullPhysics,
            children: [
              for (int i = 0; i < items; i++)
                SizedBox(height: 100, child: Text('row $i')),
            ],
          ),
        ),
      ),
    );
    return 0;
  }

  testWidgets('pulling far enough down refreshes once on release', (
    tester,
  ) async {
    final List<int> refreshes = <int>[];
    await pumpList(tester, refreshes: refreshes);

    final TestGesture gesture = await tester.startGesture(
      const Offset(200, 200),
    );
    await gesture.moveBy(const Offset(0, 300));
    await tester.pump();
    expect(refreshes, isEmpty, reason: 'nothing starts before letting go');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(refreshes.length, 1);

    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('a short pull does not refresh', (tester) async {
    final List<int> refreshes = <int>[];
    await pumpList(tester, refreshes: refreshes);

    final TestGesture gesture = await tester.startGesture(
      const Offset(200, 200),
    );
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(refreshes, isEmpty);
  });

  double ringOpacity(WidgetTester tester) => tester
      .widget<Opacity>(
        find
            .ancestor(
              of: find.byType(CircularProgressIndicator),
              matching: find.byType(Opacity),
            )
            .first,
      )
      .opacity;

  testWidgets('a short pull let go with speed clears the ring, no refresh', (
    tester,
  ) async {
    final List<int> refreshes = <int>[];
    await pumpList(tester, refreshes: refreshes);

    await tester.fling(find.text('row 0'), const Offset(0, 80), 3000);
    await tester.pumpAndSettle();

    expect(refreshes, isEmpty);
    expect(ringOpacity(tester), 0, reason: 'it would stay on screen');
  });

  testWidgets('flinging into the top never shows the ring', (tester) async {
    final List<int> refreshes = <int>[];
    await pumpList(tester, refreshes: refreshes, items: 30);

    await tester.drag(find.text('row 0'), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.fling(find.text('row 6'), const Offset(0, 200), 6000);

    double brightest = 0;
    for (int i = 0; i < 200 && tester.binding.hasScheduledFrame; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      brightest = max(brightest, ringOpacity(tester));
    }

    await tester.pumpAndSettle();
    expect(refreshes, isEmpty);
    expect(brightest, 0);
  });

  testWidgets('pulling past the bottom refreshes only when asked to', (
    tester,
  ) async {
    for (final bool fromBottom in <bool>[false, true]) {
      final List<int> refreshes = <int>[];
      await pumpList(tester, refreshes: refreshes, fromBottom: fromBottom);

      final TestGesture gesture = await tester.startGesture(
        const Offset(200, 300),
      );
      await gesture.moveBy(const Offset(0, -300));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(refreshes.length, fromBottom ? 1 : 0);
      await tester.pumpAndSettle();
    }
  });
}
