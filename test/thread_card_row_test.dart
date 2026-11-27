import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/home/thread_cards.dart';
import 'package:flutter_test/flutter_test.dart';

Future<double> _rowHeight(WidgetTester tester, List<String> titles) async {
  await tester.pumpWidget(
    CupertinoApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: ThreadCardRow(
          cards: [
            for (int i = 0; i < titles.length; i++)
              ThreadCard(
                post: Post(board: 'g', no: i + 1, sub: titles[i]),
                onTap: () {},
              ),
          ],
        ),
      ),
    ),
  );
  return tester.getSize(find.byType(ThreadCardRow)).height;
}

void main() {
  testWidgets('short titles leave no room for a second line', (tester) async {
    final double short = await _rowHeight(tester, ['Short', 'Also short']);
    final double long = await _rowHeight(tester, [
      'Short',
      'A title long enough that it takes two lines on a card',
    ]);
    expect(long, greaterThan(short));
  });

  testWidgets('holding a card opens its menu', (tester) async {
    int held = 0;
    await tester.pumpWidget(
      CupertinoApp(
        home: ThreadCardRow(
          cards: [
            ThreadCard(
              post: Post(board: 'g', no: 1, sub: 'A thread'),
              onTap: () {},
              onMenu: (_) => held++,
            ),
          ],
        ),
      ),
    );
    await tester.longPress(find.text('A thread'));
    expect(held, 1);
  });
}
