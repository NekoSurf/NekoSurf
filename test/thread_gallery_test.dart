import 'package:flutter/material.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/thread/thread_gallery_page.dart';
import 'package:flutter_chan/ui/pills.dart';
import 'package:flutter_test/flutter_test.dart';

Post _media(int no, String ext) =>
    Post(board: 'g', no: no, time: 1700000000, tim: no, ext: ext);

void main() {
  Future<void> pumpGallery(WidgetTester tester, List<Post> posts) async {
    await tester.pumpWidget(
      MaterialApp(home: ThreadGalleryPage(mediaPosts: posts)),
    );
  }

  int tiles(WidgetTester tester) => find
      .byWidgetPredicate((widget) => widget.key is ValueKey<int>)
      .evaluate()
      .length;

  testWidgets('filters to images or videos', (tester) async {
    await pumpGallery(tester, [
      _media(1, '.jpg'),
      _media(2, '.webm'),
      _media(3, '.png'),
    ]);
    expect(tiles(tester), 3);

    await tester.tap(find.text('Images'));
    await tester.pumpAndSettle();
    expect(tiles(tester), 2);

    await tester.tap(find.text('Videos'));
    await tester.pumpAndSettle();
    expect(tiles(tester), 1);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(tiles(tester), 3);
  });

  testWidgets('with only one kind there is nothing to filter', (tester) async {
    await pumpGallery(tester, [_media(1, '.jpg'), _media(2, '.png')]);
    expect(find.byType(MediaFilterPills), findsNothing);
  });
}
