import 'package:flutter/material.dart';
import 'package:flutter_chan/services/back_swipe_route.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_test/flutter_test.dart';

const Key _pageKey = Key('page');

/// A home screen with [page] open over it, in a [BackSwipePageRoute].
Future<NavigatorState> _openPage(WidgetTester tester, Widget page) async {
  final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      home: const Scaffold(body: Text('home')),
    ),
  );
  navigator.currentState!.push(
    BackSwipePageRoute<void>(
      builder: (_) => Scaffold(
        body: SizedBox.expand(key: _pageKey, child: page),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return navigator.currentState!;
}

/// From the middle of the page, so never near the edge swipe's strip.
Future<void> _drag(WidgetTester tester, Offset by, {Duration? over}) async {
  await tester.timedDragFrom(
    tester.getCenter(find.byKey(_pageKey)),
    by,
    over ?? const Duration(seconds: 1),
  );
  await tester.pumpAndSettle();
}

bool _onPage(WidgetTester tester) => find.byKey(_pageKey).evaluate().isNotEmpty;

void main() {
  testWidgets('goes back when swiped right from the middle of the page', (
    tester,
  ) async {
    await _openPage(tester, const Text('page'));

    await _drag(tester, const Offset(450, 0));

    expect(_onPage(tester), isFalse);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('follows the finger, with the page behind showing', (
    tester,
  ) async {
    final NavigatorState navigator = await _openPage(
      tester,
      const Text('page'),
    );
    final Animation<double> animation = ModalRoute.of(
      tester.element(find.byKey(_pageKey)),
    )!.animation!;

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_pageKey)),
    );
    // Past the slop, so the rest is followed one to one.
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    final double before = animation.value;
    await gesture.moveBy(const Offset(200, 0));
    await tester.pump();

    expect(before - animation.value, closeTo(200 / 800, 0.001));
    expect(navigator.userGestureInProgress, isTrue);
    expect(find.text('home'), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(navigator.userGestureInProgress, isFalse);
  });

  testWidgets('stays when let go slowly before halfway', (tester) async {
    final NavigatorState navigator = await _openPage(
      tester,
      const Text('page'),
    );

    await _drag(tester, const Offset(150, 0), over: const Duration(seconds: 2));

    expect(_onPage(tester), isTrue);
    expect(navigator.userGestureInProgress, isFalse);
    expect(
      ModalRoute.of(tester.element(find.byKey(_pageKey)))!.animation!.value,
      1,
    );
  });

  testWidgets('a quick flick is enough, however short', (tester) async {
    await _openPage(tester, const Text('page'));

    await tester.flingFrom(
      tester.getCenter(find.byKey(_pageKey)),
      const Offset(120, 0),
      1600,
    );
    await tester.pumpAndSettle();

    expect(_onPage(tester), isFalse);
  });

  testWidgets('a flick back left cancels a swipe that went far', (
    tester,
  ) async {
    await _openPage(tester, const Text('page'));

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_pageKey)),
    );
    for (int i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(50, 0));
      await tester.pump(const Duration(milliseconds: 100));
    }
    for (int i = 0; i < 4; i++) {
      await gesture.moveBy(const Offset(-40, 0));
      await tester.pump(const Duration(milliseconds: 8));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_onPage(tester), isTrue);
  });

  testWidgets('ignores a swipe to the left', (tester) async {
    final NavigatorState navigator = await _openPage(
      tester,
      const Text('page'),
    );

    await _drag(tester, const Offset(-350, 0));

    expect(_onPage(tester), isTrue);
    expect(navigator.userGestureInProgress, isFalse);
  });

  testWidgets('leaves scrolling alone', (tester) async {
    final ScrollController scroll = ScrollController();
    addTearDown(scroll.dispose);
    await _openPage(
      tester,
      ListView.builder(
        controller: scroll,
        itemCount: 100,
        itemBuilder: (_, index) => SizedBox(height: 80, child: Text('$index')),
      ),
    );

    // Slightly to the right, as thumbs do.
    await _drag(tester, const Offset(30, -300));

    expect(_onPage(tester), isTrue);
    expect(scroll.offset, greaterThan(0));
  });

  testWidgets('a sideways drag used on the page goes to it, like scrubbing', (
    tester,
  ) async {
    double scrubbed = 0;
    await _openPage(
      tester,
      Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) => scrubbed += details.delta.dx,
          child: const SizedBox(width: 400, height: 400),
        ),
      ),
    );

    await _drag(tester, const Offset(450, 0));

    expect(_onPage(tester), isTrue);
    expect(scrubbed, greaterThan(0));
  });

  testWidgets(
    'swipes that start on selectable text still go back',
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    (tester) async {
      await _openPage(
        tester,
        const Center(
          child: SelectableText('Some text to start the swipe on, in a post.'),
        ),
      );

      await _drag(tester, const Offset(450, 0));

      expect(_onPage(tester), isFalse);
    },
  );

  testWidgets('does nothing on the first page, with nothing to go back to', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: (_) => BackSwipePageRoute<void>(
          builder: (_) => const Scaffold(
            body: SizedBox.expand(key: _pageKey, child: Text('page')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _drag(tester, const Offset(450, 0));

    expect(_onPage(tester), isTrue);
    expect(
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .userGestureInProgress,
      isFalse,
    );
  });

  group('a row with actions that open to the left', () {
    Widget row() => ListView(
      children: [
        Slidable(
          endActionPane: ActionPane(
            motion: const BehindMotion(),
            children: [SlidableAction(onPressed: (_) {}, icon: Icons.delete)],
          ),
          child: const SlidableBackSwipe(
            child: SizedBox(height: 300, child: Text('row')),
          ),
        ),
      ],
    );

    double ratio(WidgetTester tester) =>
        Slidable.of(tester.element(find.text('row')))!.ratio;

    Future<void> dragRow(WidgetTester tester, Offset by) async {
      await tester.timedDrag(find.text('row'), by, const Duration(seconds: 1));
      await tester.pumpAndSettle();
    }

    testWidgets('goes back when swiped right', (tester) async {
      await _openPage(tester, row());

      await dragRow(tester, const Offset(450, 0));

      expect(_onPage(tester), isFalse);
    });

    testWidgets('a quick flick goes back too', (tester) async {
      await _openPage(tester, row());

      await tester.fling(find.text('row'), const Offset(300, 0), 2000);
      await tester.pumpAndSettle();

      expect(_onPage(tester), isFalse);
    });

    testWidgets('still opens to the left, and closes back to the right', (
      tester,
    ) async {
      await _openPage(tester, row());

      await dragRow(tester, const Offset(-300, 0));
      expect(_onPage(tester), isTrue);
      expect(ratio(tester), lessThan(0));

      await dragRow(tester, const Offset(300, 0));
      expect(_onPage(tester), isTrue);
      expect(ratio(tester), 0);
    });
  });

  testWidgets('a plain route still only goes back from the edge', (
    tester,
  ) async {
    final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: const Scaffold(body: Text('home')),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(
          body: SizedBox.expand(key: _pageKey, child: Text('page')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _drag(tester, const Offset(450, 0));

    expect(_onPage(tester), isTrue);
  });
}
