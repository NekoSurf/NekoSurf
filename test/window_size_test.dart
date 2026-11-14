import 'package:flutter/widgets.dart';
import 'package:flutter_chan/ui/window_size.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('windows fall in the size classes by their width', () {
    expect(WindowSize.fromWidth(390), WindowSize.compact);
    expect(WindowSize.fromWidth(744), WindowSize.medium);
    expect(WindowSize.fromWidth(1032), WindowSize.expanded);
    expect(WindowSize.fromWidth(1376), WindowSize.large);
    expect(WindowSize.large.isAtLeast(WindowSize.expanded), isTrue);
    expect(WindowSize.medium.isAtLeast(WindowSize.expanded), isFalse);
  });

  Future<Rect> rowIn(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: CustomScrollView(
          slivers: [
            ReadableSliver(
              sliver: SliverToBoxAdapter(
                child: SizedBox(key: Key('row'), height: 40),
              ),
            ),
          ],
        ),
      ),
    );
    return tester.getRect(find.byKey(const Key('row')));
  }

  testWidgets('a readable list keeps to a column in the middle of a wide '
      'window', (tester) async {
    final Rect row = await rowIn(tester, 1376);

    expect(row.width, kReadableWidth);
    expect(row.left, (1376 - kReadableWidth) / 2);
  });

  testWidgets('a readable list takes all of a phone', (tester) async {
    final Rect row = await rowIn(tester, 390);

    expect(row.left, 0);
    expect(row.width, 390);
  });
}
