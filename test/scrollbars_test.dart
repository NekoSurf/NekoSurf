import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/ui/scrollbars.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

ItemPosition _at(int index, double leading, double trailing) => ItemPosition(
  index: index,
  itemLeadingEdge: leading,
  itemTrailingEdge: trailing,
);

void main() {
  group('measureRows', () {
    test('counts the rows above the screen and on it, in parts', () {
      final RowSpan? span = measureRows([
        _at(4, -0.25, 0.25), // half above
        _at(5, 0.25, 0.75),
        _at(6, 0.75, 1.25), // half below
      ]);
      expect(span!.top, closeTo(4.5, 1e-9));
      expect(span.shown, closeTo(2, 1e-9));
    });

    test('is at the first row when it starts below the top', () {
      final RowSpan? span = measureRows([_at(0, 0.1, 0.6), _at(1, 0.6, 0.9)]);
      expect(span!.top, 0);
      expect(span.shown, closeTo(2, 1e-9));
    });

    test('leaves out rows laid out off the screen', () {
      final RowSpan? span = measureRows([
        _at(2, -0.6, -0.1),
        _at(3, -0.1, 0.9),
        _at(4, 1.0, 1.4),
      ]);
      expect(span!.top, closeTo(3.1, 1e-9));
      expect(span.shown, closeTo(0.9, 1e-9));
    });

    test('is nothing while no row is shown', () {
      expect(measureRows(const []), isNull);
    });
  });

  group('RowScrollbar', () {
    const int count = 300;
    late ItemScrollController controller;
    late ItemPositionsListener positions;

    // Rows of different heights, as posts are.
    double heightOf(int index) => 40.0 + (index % 7) * 30;

    Future<void> pumpList(WidgetTester tester) async {
      controller = ItemScrollController();
      positions = ItemPositionsListener.create();
      await tester.pumpWidget(
        CupertinoApp(
          home: RowScrollbar(
            rowCount: count,
            positions: positions,
            controller: controller,
            endPadding: 8,
            child: ScrollablePositionedList.builder(
              itemCount: count,
              itemScrollController: controller,
              itemPositionsListener: positions,
              padding: const EdgeInsets.only(bottom: 8),
              itemBuilder: (_, int index) =>
                  SizedBox(height: heightOf(index), child: Text('Row $index')),
            ),
          ),
        ),
      );
    }

    Iterable<ItemPosition> shown() => positions.itemPositions.value.where(
      (ItemPosition p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1,
    );

    int firstShown() => shown()
        .map((ItemPosition p) => p.index)
        .reduce((int a, int b) => a < b ? a : b);

    /// Scrolls a little, so the thumb shows, near the top of the track.
    Future<void> showThumb(WidgetTester tester) async {
      await tester.drag(find.byType(RowScrollbar), const Offset(0, -20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    Offset thumbAtTop(WidgetTester tester) {
      final Rect box = tester.getRect(find.byType(RowScrollbar));
      return Offset(box.right - 4, box.top + 3 + 10);
    }

    Future<TestGesture> takeThumb(WidgetTester tester) async {
      final TestGesture gesture = await tester.startGesture(thumbAtTop(tester));
      await tester.pump(const Duration(milliseconds: 150));
      return gesture;
    }

    testWidgets('dragging the thumb to the end shows the last row there', (
      WidgetTester tester,
    ) async {
      await pumpList(tester);
      await showThumb(tester);

      final TestGesture gesture = await takeThumb(tester);
      for (int i = 0; i < 20; i++) {
        await gesture.moveBy(const Offset(0, 40));
        await tester.pump();
      }
      await gesture.up();
      for (int i = 0; i < 4; i++) {
        await tester.pump();
      }

      final ItemPosition last = shown().firstWhere(
        (ItemPosition p) => p.index == count - 1,
      );
      final double height = tester.getSize(find.byType(RowScrollbar)).height;
      expect(last.itemTrailingEdge, closeTo(1 - 8 / height, 0.005));
    });

    testWidgets('dragging the thumb halfway goes to the middle rows', (
      WidgetTester tester,
    ) async {
      await pumpList(tester);
      await showThumb(tester);
      final double height = tester.getSize(find.byType(RowScrollbar)).height;

      final TestGesture gesture = await takeThumb(tester);
      // The thumb travels the screen less its own length and margins.
      await gesture.moveBy(Offset(0, (height - 36 - 6) / 2));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await tester.pump();

      expect(firstShown(), inInclusiveRange(count * 0.4, count * 0.6));
    });

    testWidgets('a drag takes the thumb at once, once it shows', (
      WidgetTester tester,
    ) async {
      await pumpList(tester);
      // Hidden until the list scrolls: the drag goes to the list, which is at
      // its top.
      await tester.dragFrom(thumbAtTop(tester), const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(firstShown(), 0);

      await showThumb(tester);
      // No holding first, as on the pages with CupertinoScrollbar.
      final TestGesture gesture = await tester.startGesture(
        thumbAtTop(tester),
      );
      await gesture.moveBy(const Offset(0, 300));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await tester.pump();
      expect(firstShown(), greaterThan(count * 0.3));
    });
  });

  testWidgets('PageScrollbar scrolls its page from the thumb', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: PageScrollbar(
          child: CustomScrollView(
            primary: true,
            slivers: [
              SliverList.builder(
                itemCount: 200,
                itemBuilder: (_, int index) =>
                    SizedBox(height: 50, child: Text('Row $index')),
              ),
            ],
          ),
        ),
      ),
    );
    final ScrollPosition position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final Rect box = tester.getRect(find.byType(PageScrollbar));
    final TestGesture gesture = await tester.startGesture(
      Offset(box.right - 4, box.top + 3 + 10),
    );
    await tester.pump(const Duration(milliseconds: 150));
    await gesture.moveBy(Offset(0, box.height));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(position.pixels, position.maxScrollExtent);
  });
}
