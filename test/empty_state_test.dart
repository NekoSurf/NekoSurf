import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/chan/load_errors.dart';
import 'package:flutter_chan/ui/empty_state.dart';
import 'package:flutter_chan/ui/reload.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(CupertinoApp(home: CupertinoPageScaffold(child: child)));

void main() {
  testWidgets('an empty page says why, and offers what to do', (tester) async {
    int done = 0;
    await _pump(
      tester,
      DashEmptyState(
        icon: CupertinoIcons.clock,
        title: 'No history yet',
        message: 'The threads you open show up here.',
        actionLabel: 'Browse boards',
        onAction: () => done++,
      ),
    );
    expect(find.text('No history yet'), findsOneWidget);
    expect(find.text('The threads you open show up here.'), findsOneWidget);
    await tester.tap(find.text('Browse boards'));
    expect(done, 1);
  });

  testWidgets('without something to do, there is no button', (tester) async {
    await _pump(
      tester,
      const DashEmptyState(
        icon: CupertinoIcons.search,
        title: 'No threads match',
        message: 'Try other words, or clear the search.',
      ),
    );
    expect(find.byType(CupertinoButton), findsNothing);
  });

  testWidgets('a page that failed to load looks the same, with Try again', (
    tester,
  ) async {
    int reloaded = 0;
    await _pump(
      tester,
      ReloadWidget.forError(
        const ApiException(404, 'thread'),
        onReload: () => reloaded++,
      ),
    );
    expect(find.byType(DashEmptyState), findsOneWidget);
    expect(find.text('Not found'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(reloaded, 1);
  });
}
