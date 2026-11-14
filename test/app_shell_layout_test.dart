import 'package:flutter/widgets.dart';
import 'package:flutter_chan/main.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/ui/dash_header.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester, Size window) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      AppRoot(prefs: prefs, settings: SettingsProvider(prefs)),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('on a phone, the tabs are along the bottom', (tester) async {
    await pumpApp(tester, const Size(390, 844));

    expect(find.byType(DashTabBar), findsOneWidget);
    expect(find.byType(DashSideBar), findsNothing);
  });

  testWidgets('in a wide window, the tabs are down the side, and pages '
      'beside them', (tester) async {
    await pumpApp(tester, const Size(1194, 834));

    expect(find.byType(DashSideBar), findsOneWidget);
    expect(find.byType(DashTabBar), findsNothing);
    expect(
      tester.getTopLeft(find.text('NekoSurf').first).dx,
      greaterThan(kDashSideBarWidth),
    );

    await tester.tap(find.text('Settings').first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Appearance'), findsWidgets);
  });

  testWidgets('a tab keeps its place when the window gets narrow', (
    tester,
  ) async {
    await pumpApp(tester, const Size(1194, 834));
    await tester.tap(find.text('Settings').first);
    await tester.pump(const Duration(milliseconds: 500));

    tester.view.physicalSize = const Size(390, 844);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(DashTabBar), findsOneWidget);
    expect(find.text('Appearance'), findsWidgets);
  });
}
