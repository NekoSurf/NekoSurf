import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chan/ui/dash_scaffold.dart';
import 'package:flutter_test/flutter_test.dart';

/// What iOS sends when the status bar is tapped.
Future<void> tapStatusBar(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.statusBar.name,
    SystemChannels.statusBar.codec.encodeMethodCall(
      const MethodCall('handleScrollToTop'),
    ),
    (_) {},
  );
  await tester.pumpAndSettle();
}

Widget rowsPage(String title) => DashScaffold(
  title: title,
  slivers: [
    SliverList.builder(
      itemCount: 100,
      itemBuilder: (_, int i) =>
          SizedBox(height: 60, child: Text('$title row $i')),
    ),
  ],
);

/// The page's list, scrolled [by].
Future<void> scrollDown(WidgetTester tester, String title, double by) async {
  await tester.drag(
    find.byType(CustomScrollView).hitTestable().first,
    Offset(0, -by),
  );
  await tester.pumpAndSettle();
  expect(find.text('$title row 0'), findsNothing);
}

void main() {
  testWidgets('tapping the status bar takes the page to its top', (
    tester,
  ) async {
    await tester.pumpWidget(CupertinoApp(home: rowsPage('Board')));
    await scrollDown(tester, 'Board', 1500);

    await tapStatusBar(tester);

    expect(find.text('Board row 0'), findsOneWidget);
  });

  testWidgets('only the page on top goes up', (tester) async {
    final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      CupertinoApp(navigatorKey: navigator, home: rowsPage('Board')),
    );
    await scrollDown(tester, 'Board', 1500);
    navigator.currentState!.push(
      CupertinoPageRoute<void>(builder: (_) => rowsPage('Thread')),
    );
    await tester.pumpAndSettle();
    await scrollDown(tester, 'Thread', 1500);

    await tapStatusBar(tester);
    expect(find.text('Thread row 0'), findsOneWidget);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Board row 0'), findsNothing);
  });

  testWidgets('a dialog over the page keeps it where it is', (tester) async {
    await tester.pumpWidget(CupertinoApp(home: rowsPage('Board')));
    await scrollDown(tester, 'Board', 1500);
    showCupertinoDialog<void>(
      context: tester.element(find.byType(DashScaffold)),
      builder: (_) => const CupertinoAlertDialog(title: Text('Hello')),
    );
    await tester.pumpAndSettle();

    await tapStatusBar(tester);

    expect(find.text('Board row 0', skipOffstage: false), findsNothing);
  });

  testWidgets('a page with its own list takes it to the top its own way', (
    tester,
  ) async {
    int toTop = 0;
    await tester.pumpWidget(
      CupertinoApp(
        home: DashBarScaffold(
          title: 'Thread',
          onScrollToTop: () => toTop++,
          body: const SizedBox.expand(),
        ),
      ),
    );

    await tapStatusBar(tester);

    expect(toTop, 1);
  });
}
