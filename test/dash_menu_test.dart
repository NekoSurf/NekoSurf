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

  group('lifted', () {
    const Key original = Key('original');
    const Key copy = Key('copy');

    /// A box [height] high at [top], which opens a lifted menu when tapped.
    Future<List<String>> lift(
      WidgetTester tester, {
      double top = 300,
      double height = 120,
    }) async {
      tester.view
        ..physicalSize = const Size(400, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final List<String> chosen = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              Positioned(
                top: top,
                left: 0,
                right: 0,
                height: height,
                child: Builder(
                  builder: (context) => GestureDetector(
                    onTap: () => showLiftedMenu(
                      context,
                      preview: (_) => SizedBox(key: copy, height: height),
                      entries: [
                        DashMenuEntry(
                          title: 'Choose me',
                          onPressed: () => chosen.add('Choose me'),
                        ),
                      ],
                    ),
                    child: const ColoredBox(key: original, color: Colors.red),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      // Near its top: a tall one's middle is off the screen.
      await tester.tapAt(Offset(200, top + 10));
      await tester.pumpAndSettle();
      return chosen;
    }

    testWidgets('copies what was held as a card, with the menu under it', (
      tester,
    ) async {
      await lift(tester);

      final Rect lifted = tester.getRect(find.byKey(copy));
      // Room on both sides, where it was.
      expect(lifted.left, closeTo(8, 0.5));
      expect(lifted.width, closeTo(384, 0.5));
      expect(lifted.top, closeTo(300, 0.5));
      expect(
        tester.getTopLeft(find.text('Choose me')).dy,
        greaterThan(lifted.bottom),
      );
    });

    testWidgets('goes back into place when nothing is chosen', (tester) async {
      final List<String> chosen = await lift(tester, top: 700);
      // Moved up to make room for the menu.
      final Rect lifted = tester.getRect(find.byKey(copy));
      expect(lifted.top, lessThan(700));

      await tester.tapAt(const Offset(200, 20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final Rect halfway = tester.getRect(find.byKey(copy));
      expect(halfway.top, greaterThan(lifted.top));
      expect(halfway.top, lessThan(700));
      await tester.pumpAndSettle();

      expect(find.byKey(copy), findsNothing);
      expect(chosen, isEmpty);
    });

    testWidgets('fades where it is once an entry is chosen', (tester) async {
      final List<String> chosen = await lift(tester, top: 700);
      final Rect lifted = tester.getRect(find.byKey(copy));

      await tester.tap(find.text('Choose me'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.getRect(find.byKey(copy)).top, closeTo(lifted.top, 0.5));
      await tester.pumpAndSettle();

      expect(find.byKey(copy), findsNothing);
      expect(chosen, ['Choose me']);
    });

    testWidgets('a copy taller than the screen leaves room for the menu', (
      tester,
    ) async {
      await lift(tester, top: 0, height: 2000);

      expect(find.text('Choose me').hitTestable(), findsOneWidget);
      expect(tester.getBottomLeft(find.text('Choose me')).dy, lessThan(800));
    });
  });
}
