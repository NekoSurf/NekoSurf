import 'package:flutter/material.dart';
import 'package:flutter_chan/ui/dash_menu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// A button at [top] that opens a menu, on a screen 800 high.
  Future<void> openMenuAt(WidgetTester tester, double top) async {
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Positioned(
              top: top,
              left: 20,
              child: DashMenuAnchor(
                menuChildren: [
                  for (final String title in ['One', 'Two', 'Three', 'Four'])
                    DashMenuEntry(title: title, onPressed: () {}),
                ],
                builder: (context, open) =>
                    TextButton(onPressed: open, child: const Text('Open')),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a menu opens below what opened it', (tester) async {
    await openMenuAt(tester, 100);

    expect(
      tester.getTopLeft(find.text('One')).dy,
      greaterThan(tester.getBottomLeft(find.text('Open')).dy),
    );
  });

  testWidgets('near the bottom of the screen, it opens above instead', (
    tester,
  ) async {
    await openMenuAt(tester, 720);

    expect(
      tester.getBottomLeft(find.text('Four')).dy,
      lessThan(tester.getTopLeft(find.text('Open')).dy),
    );
    // All of it, not squeezed.
    expect(find.text('One').hitTestable(), findsOneWidget);
  });
}
