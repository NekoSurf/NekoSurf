import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/services/unfocus_on_push.dart';
import 'package:flutter_test/flutter_test.dart';

/// A board page: a search field, and a thread that opens over it.
Widget _app({required bool observed, WidgetBuilder? thread}) {
  return CupertinoApp(
    navigatorObservers: [if (observed) UnfocusOnPushObserver()],
    home: Builder(
      builder: (BuildContext context) => CupertinoPageScaffold(
        child: SafeArea(
          child: Column(
            children: [
              const CupertinoSearchTextField(),
              CupertinoButton(
                child: const Text('thread'),
                onPressed: () => Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder:
                        thread ??
                        (_) =>
                            const CupertinoPageScaffold(child: Text('posts')),
                  ),
                ),
              ),
              CupertinoButton(
                child: const Text('dialog'),
                onPressed: () => showCupertinoDialog<void>(
                  context: context,
                  builder: (_) => const CupertinoAlertDialog(),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _typeThenOpen(WidgetTester tester, String what) async {
  await tester.showKeyboard(find.byType(CupertinoSearchTextField));
  expect(tester.testTextInput.isVisible, isTrue);
  await tester.tap(find.text(what));
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator)).pop();
  await tester.pumpAndSettle();
}

bool _fieldFocused(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus;

void main() {
  testWidgets('without it, coming back from a thread brings the keyboard up', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(observed: false));
    await _typeThenOpen(tester, 'thread');
    await _back(tester);

    expect(_fieldFocused(tester), isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('coming back from a thread leaves the keyboard down', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(observed: true));
    await _typeThenOpen(tester, 'thread');
    await _back(tester);

    expect(_fieldFocused(tester), isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('a dialog gives the keyboard back when it closes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(observed: true));
    await _typeThenOpen(tester, 'dialog');
    await _back(tester);

    expect(_fieldFocused(tester), isTrue);
  });

  testWidgets('a page that focuses its own field still gets it', (
    WidgetTester tester,
  ) async {
    final FocusNode search = FocusNode();
    addTearDown(search.dispose);
    await tester.pumpWidget(
      _app(
        observed: true,
        thread: (_) => CupertinoPageScaffold(
          child: SafeArea(
            child: CupertinoTextField(focusNode: search, autofocus: true),
          ),
        ),
      ),
    );
    await _typeThenOpen(tester, 'thread');

    expect(search.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  });
}
