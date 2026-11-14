import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/chan/post.dart';
import 'package:flutter_chan/ui/master_detail.dart';
import 'package:flutter_chan/ui/open.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _pageFor(Destination destination) => switch (destination) {
  ThreadDestination(:final post) => CupertinoPageScaffold(
    child: Builder(
      builder: (context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Thread ${post.no}'),
          CupertinoButton(
            onPressed: () => Navigator.of(context).push(
              CupertinoPageRoute<void>(
                builder: (_) => const CupertinoPageScaffold(
                  child: Center(child: Text('Replies')),
                ),
              ),
            ),
            child: const Text('Open replies'),
          ),
        ],
      ),
    ),
  ),
  BoardDestination(:final board) => Text('Board $board'),
};

/// A list of two threads, with the app's way of opening them.
Widget _app() {
  return DestinationPages(
    pageFor: _pageFor,
    child: CupertinoApp(
      onGenerateRoute: (RouteSettings settings) {
        final Object? destination = settings.arguments;
        if (destination is Destination) {
          return CupertinoPageRoute<void>(
            builder: (_) => _pageFor(destination),
          );
        }
        return CupertinoPageRoute<void>(builder: (_) => _list());
      },
    ),
  );
}

/// The list of two threads.
Widget _list() {
  return MasterDetail(
    master: CupertinoPageScaffold(
      child: Builder(
        builder: (context) => Column(
          children: [
            for (final int no in [1, 2])
              CupertinoButton(
                onPressed: () => openThread(context, Post(board: 'g', no: no)),
                child: Text('Open $no'),
              ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  void windowOf(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('in a narrow window, a thread opens over the list', (
    tester,
  ) async {
    windowOf(tester, const Size(820, 1180));
    await tester.pumpWidget(_app());

    await tester.tap(find.text('Open 1'));
    await tester.pumpAndSettle();

    expect(find.text('Thread 1'), findsOneWidget);
    expect(find.text('Open 1'), findsNothing);
  });

  testWidgets('in a wide window, a thread opens beside the list, in place '
      'of the one there', (tester) async {
    windowOf(tester, const Size(1376, 1032));
    await tester.pumpWidget(_app());
    // Until a thread is chosen, the list has the page.
    expect(tester.getSize(find.byType(CupertinoPageScaffold)).width, 1376);

    await tester.tap(find.text('Open 1'));
    await tester.pumpAndSettle();
    expect(find.text('Thread 1'), findsOneWidget);
    expect(find.text('Open 1'), findsOneWidget);

    await tester.tap(find.text('Open 2'));
    await tester.pumpAndSettle();
    expect(find.text('Thread 2'), findsOneWidget);
    expect(find.text('Thread 1'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Thread 2')).dx,
      greaterThan(MasterDetail.masterWidth),
    );
  });

  testWidgets('when the window gets narrow, the thread beside the list '
      'opens over it', (tester) async {
    windowOf(tester, const Size(1376, 1032));
    await tester.pumpWidget(_app());
    await tester.tap(find.text('Open 2'));
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(820, 1180);
    await tester.pumpAndSettle();

    expect(find.text('Thread 2'), findsOneWidget);
    expect(find.text('Open 2'), findsNothing);
  });

  testWidgets('back goes back in the pane, closes it, then leaves the list', (
    tester,
  ) async {
    windowOf(tester, const Size(1376, 1032));
    await tester.pumpWidget(
      DestinationPages(
        pageFor: _pageFor,
        child: CupertinoApp(
          home: Builder(
            builder: (context) => CupertinoButton(
              onPressed: () => Navigator.of(
                context,
              ).push(CupertinoPageRoute<void>(builder: (_) => _list())),
              child: const Text('Open the list'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open the list'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open replies'));
    await tester.pumpAndSettle();
    expect(find.text('Replies'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Replies'), findsNothing);
    expect(find.text('Thread 1'), findsOneWidget);

    // Back from the thread gives the list the page again.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Thread 1'), findsNothing);
    expect(find.text('Open 1'), findsOneWidget);
    expect(tester.getSize(find.byType(CupertinoPageScaffold)).width, 1376);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Open the list'), findsOneWidget);
  });
}
