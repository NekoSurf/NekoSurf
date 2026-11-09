import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/home/routes.dart';
import 'package:flutter_chan/ui/back_swipe_route.dart';
import 'package:flutter_test/flutter_test.dart';

const Key _homeKey = Key('home');
const Key _boardKey = Key('board');

/// How often the home page has been built.
int _homeBuilds = 0;

class _HomePage extends StatelessWidget {
  const _HomePage();

  @override
  Widget build(BuildContext context) {
    // Like nearly everything on a page, it depends on something inherited.
    MediaQuery.sizeOf(context);
    _homeBuilds++;
    return const SizedBox.expand(key: _homeKey, child: Text('home'));
  }
}

/// The app, as main.dart builds it, with a board open over the home page.
Future<NavigatorState> _openBoard(WidgetTester tester) async {
  final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    CupertinoApp(
      navigatorKey: navigator,
      onGenerateInitialRoutes: (_) => [homeRoute(const _HomePage())],
      onGenerateRoute: generateRoute,
    ),
  );
  // The route generateRoute builds a board in.
  navigator.currentState!.push(
    BackSwipePageRoute<void>(
      builder: (_) => const SizedBox.expand(key: _boardKey, child: Text('b')),
    ),
  );
  await tester.pumpAndSettle();
  return navigator.currentState!;
}

double _left(WidgetTester tester, Key key) =>
    tester.getTopLeft(find.byKey(key)).dx;

/// Where the home page is when the board is at [boardLeft]: it slides a third
/// as far as the board, as a board does under a thread.
double _homeLeftFor(WidgetTester tester, double boardLeft) =>
    (boardLeft - tester.getSize(find.byKey(_boardKey)).width) / 3;

void main() {
  testWidgets(
    'the home page follows a back swipe, and carries on when let go',
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    (tester) async {
      await _openBoard(tester);

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_boardKey)),
      );
      for (int i = 0; i < 25; i++) {
        await gesture.moveBy(const Offset(20, 0));
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          _left(tester, _homeKey),
          closeTo(_homeLeftFor(tester, _left(tester, _boardKey)), 0.5),
        );
      }

      // Past halfway, so the board goes; each frame, the home page is still
      // where the board puts it, without a jump.
      await gesture.up();
      while (find.byKey(_boardKey).evaluate().isNotEmpty) {
        expect(
          _left(tester, _homeKey),
          closeTo(_homeLeftFor(tester, _left(tester, _boardKey)), 0.5),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(_left(tester, _homeKey), 0);
    },
  );

  testWidgets(
    'the home page is not rebuilt as a board opens and goes back',
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    (tester) async {
      final NavigatorState navigator = await _openBoard(tester);
      final int builds = _homeBuilds;

      navigator.pop();
      await tester.pumpAndSettle();
      navigator.push(
        BackSwipePageRoute<void>(builder: (_) => const SizedBox.expand()),
      );
      await tester.pumpAndSettle();

      expect(_homeBuilds, builds);
    },
  );
}
