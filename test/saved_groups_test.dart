import 'package:flutter/material.dart';
import 'package:flutter_chan/saved/saved_attachment.dart';
import 'package:flutter_chan/saved/saved_groups.dart';
import 'package:flutter_test/flutter_test.dart';

SavedAttachment _savedAt(String name, DateTime at) => SavedAttachment(
  type: SavedAttachmentType.image,
  fileName: '$name.jpg',
  thumbnail: '${name}s.jpg',
  addedAt: at.millisecondsSinceEpoch,
);

void main() {
  final DateTime now = DateTime(2026, 11, 27, 15);

  test('names a file by how long ago it was saved', () {
    expect(savedGroupTitle(DateTime(2026, 11, 27, 9), now), 'Today');
    expect(savedGroupTitle(DateTime(2026, 11, 26, 23), now), 'Yesterday');
    expect(savedGroupTitle(DateTime(2026, 11, 22), now), 'This week');
    expect(savedGroupTitle(DateTime(2026, 11, 3), now), 'This month');
    expect(savedGroupTitle(DateTime(2026, 10, 30), now), 'October');
    expect(savedGroupTitle(DateTime(2025, 12, 24), now), 'December 2025');
  });

  test('groups runs of files saved in the same stretch, in order', () {
    final List<SavedGroup> groups = groupByDay([
      _savedAt('a', DateTime(2026, 11, 27, 14)),
      _savedAt('b', DateTime(2026, 11, 27, 8)),
      _savedAt('c', DateTime(2026, 11, 26, 20)),
      _savedAt('d', DateTime(2026, 10, 2)),
    ], now);

    expect(
      [for (final g in groups) g.title],
      ['Today', 'Yesterday', 'October'],
    );
    expect(
      [for (final a in groups.first.items) a.fileName],
      ['a.jpg', 'b.jpg'],
    );
  });

  test('deals files into columns as a masonry grid does', () {
    final List<SavedAttachment> files = [
      for (final String name in ['tall', 'a', 'b', 'c']) _savedAt(name, now),
    ];
    // The tall one fills the left column as two square ones fill the right.
    final List<List<SavedAttachment>> columns = intoColumns(
      files,
      2,
      (a) => a.fileName == 'tall.jpg' ? 0.5 : 1,
    );
    expect([for (final a in columns[0]) a.fileName], ['tall.jpg', 'c.jpg']);
    expect([for (final a in columns[1]) a.fileName], ['a.jpg', 'b.jpg']);
  });

  testWidgets('many stretches of files scroll all the way to the end', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    const List<double> ratios = [0.6, 1, 1.1, 0.8];
    await tester.pumpWidget(
      MaterialApp(
        home: CustomScrollView(
          slivers: [
            SliverMainAxisGroup(
              slivers: [
                for (int g = 0; g < 12; g++)
                  SliverMainAxisGroup(
                    slivers: [
                      SliverToBoxAdapter(child: Text('Stretch $g')),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SavedColumns(
                          gap: 10,
                          columns: intoColumns(
                            [
                              for (int i = 0; i < 40; i++)
                                _savedAt('$g-$i', now),
                            ],
                            2,
                            (a) => ratios[a.fileName.length % 4],
                          ),
                          tile: (a) => AspectRatio(
                            aspectRatio: ratios[a.fileName.length % 4],
                            child: Text(a.fileName),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SliverToBoxAdapter(child: Text('The end')),
          ],
        ),
      ),
    );

    // It used to jump back once the first stretch was out of sight.
    double last = 0;
    for (int i = 0; i < 300; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pump();
      final ScrollPosition position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      expect(position.pixels, greaterThanOrEqualTo(last));
      last = position.pixels;
      if (position.pixels >= position.maxScrollExtent) {
        break;
      }
    }
    expect(find.text('The end'), findsOneWidget);
  });
}
