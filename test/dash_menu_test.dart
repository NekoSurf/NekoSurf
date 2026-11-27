import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chan/ui/dash_menu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// A button at [top] that opens a menu, on a screen 800 high. Entries
  /// chosen go in [chosen].
  Future<void> openMenuAt(
    WidgetTester tester,
    double top, {
    List<String>? chosen,
  }) async {
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
                    DashMenuEntry(
                      title: title,
                      onPressed: () => chosen?.add(title),
                    ),
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

  testWidgets('a swipe outside it closes it and scrolls the page', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ScrollController scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: scroll,
            children: [
              DashMenuAnchor(
                menuChildren: [DashMenuEntry(title: 'One', onPressed: () {})],
                builder: (context, open) =>
                    TextButton(onPressed: open, child: const Text('Open')),
              ),
              for (int i = 0; i < 50; i++)
                SizedBox(height: 60, child: Text('$i')),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('One'), findsOneWidget);

    await tester.dragFrom(const Offset(200, 600), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(find.text('One'), findsNothing);
    expect(scroll.offset, greaterThan(100));
  });

  testWidgets('a tap outside it only closes it', (tester) async {
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    int pressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              DashMenuAnchor(
                menuChildren: [DashMenuEntry(title: 'One', onPressed: () {})],
                builder: (context, open) =>
                    TextButton(onPressed: open, child: const Text('Open')),
              ),
              const SizedBox(height: 400),
              TextButton(
                onPressed: () => pressed++,
                child: const Text('Under'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Under'));
    await tester.pumpAndSettle();
    expect(find.text('One'), findsNothing);
    expect(pressed, 0);

    // Closed, it's tapped as usual.
    await tester.tap(find.text('Under'));
    await tester.pumpAndSettle();
    expect(pressed, 1);
  });

  testWidgets('going back closes it first', (tester) async {
    await openMenuAt(tester, 100);

    final NavigatorState navigator = tester.state(find.byType(Navigator));
    expect(await navigator.maybePop(), isTrue);
    await tester.pumpAndSettle();

    expect(find.text('One'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('a tap on an entry chooses it', (tester) async {
    final List<String> chosen = <String>[];
    await openMenuAt(tester, 100, chosen: chosen);

    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();

    expect(chosen, ['Two']);
    expect(find.text('One'), findsNothing);
  });

  testWidgets('choosing an entry ticks', (tester) async {
    final List<String> haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await openMenuAt(tester, 100);

    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(haptics, ['HapticFeedbackType.selectionClick']);
  });

  testWidgets('sliding over the entries chooses the one let go on', (
    tester,
  ) async {
    final List<String> chosen = <String>[];
    await openMenuAt(tester, 100, chosen: chosen);

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.text('One')),
    );
    await gesture.moveTo(tester.getCenter(find.text('Two')));
    await gesture.moveTo(tester.getCenter(find.text('Three')));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(chosen, ['Three']);
  });

  testWidgets('sliding off the menu chooses nothing', (tester) async {
    final List<String> chosen = <String>[];
    await openMenuAt(tester, 100, chosen: chosen);

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.text('One')),
    );
    await gesture.moveTo(const Offset(390, 790));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(chosen, isEmpty);
    expect(find.text('One'), findsOneWidget);
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
