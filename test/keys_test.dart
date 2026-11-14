import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chan/ui/dash_scaffold.dart';
import 'package:flutter_chan/ui/keys.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(Widget home) => CupertinoApp(
    builder: (context, child) => AppKeys(child: child!),
    home: home,
  );

  Future<void> openPage(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => CupertinoButton(
            onPressed: () => Navigator.of(
              context,
            ).push(CupertinoPageRoute<void>(builder: (_) => page)),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  for (final (String name, List<LogicalKeyboardKey> keys) in [
    ('Esc', [LogicalKeyboardKey.escape]),
    ('⌘W', [LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyW]),
    (
      'Ctrl+[',
      [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.bracketLeft],
    ),
  ]) {
    testWidgets('$name goes back', (tester) async {
      await openPage(tester, const PageKeys(bindings: {}, child: Text('Page')));
      expect(find.text('Page'), findsOneWidget);

      for (final LogicalKeyboardKey key in keys) {
        await tester.sendKeyDownEvent(key);
      }
      for (final LogicalKeyboardKey key in keys.reversed) {
        await tester.sendKeyUpEvent(key);
      }
      await tester.pumpAndSettle();

      expect(find.text('Page'), findsNothing);
    });
  }

  testWidgets('Esc in a text field leaves the field, not the page', (
    tester,
  ) async {
    await openPage(
      tester,
      const CupertinoPageScaffold(
        child: Center(child: CupertinoTextField(autofocus: true)),
      ),
    );
    await tester.pump();
    bool typing() =>
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<EditableText>() !=
        null;
    expect(typing(), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoTextField), findsOneWidget);
    expect(typing(), isFalse);
  });

  testWidgets('⌘R refreshes a page that can be refreshed', (tester) async {
    int refreshed = 0;
    await openPage(
      tester,
      DashScaffold(
        title: 'Board',
        onRefresh: () async => refreshed++,
        slivers: const [SliverToBoxAdapter(child: Text('Threads'))],
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(refreshed, 1);
  });
}
