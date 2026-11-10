import 'package:flutter/cupertino.dart';
import 'package:flutter_chan/main.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

/// What a page sees of the theme.
class _Probe extends StatelessWidget {
  const _Probe();

  static bool? isDark;
  static Color? accent;
  static Color? primary;

  @override
  Widget build(BuildContext context) {
    isDark = context.isDark;
    accent = context.accent;
    primary = CupertinoTheme.of(context).primaryColor;
    return const SizedBox.expand();
  }
}

void main() {
  group('every theme', () {
    test('takes black text on its accent', () {
      for (final ThemeColor theme in ThemeColor.values) {
        expect(
          _contrast(theme.accent, const Color(0xFF000000)),
          greaterThan(4.5),
          reason: theme.name,
        );
      }
    });

    test('has an ink that reads on white', () {
      for (final ThemeColor theme in ThemeColor.values) {
        expect(
          _contrast(theme.ink, const Color(0xFFFFFFFF)),
          greaterThan(4.5),
          reason: theme.name,
        );
      }
    });

    test('has two colors, and an accent of its own', () {
      final Set<Color> accents = <Color>{};
      for (final ThemeColor theme in ThemeColor.values) {
        expect(theme.accent2, isNot(theme.accent), reason: theme.name);
        expect(accents.add(theme.accent), isTrue, reason: theme.name);
      }
    });
  });

  test('Auto follows the phone, the others stay put', () {
    for (final Brightness phone in Brightness.values) {
      expect(Appearance.system.brightness(phone), phone);
      expect(Appearance.light.brightness(phone), Brightness.light);
      expect(Appearance.dark.brightness(phone), Brightness.dark);
    }
  });

  testWidgets('what is built without a theme gets the first one', (
    tester,
  ) async {
    await tester.pumpWidget(const _Probe());
    expect(_Probe.accent, ThemeColor.cyan.accent);
  });

  testWidgets('the app takes the appearance and color as they change', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    SharedPreferences.setMockInitialValues({});
    final SettingsProvider settings = SettingsProvider(
      await SharedPreferences.getInstance(),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: const AppWithTheme(home: _Probe()),
      ),
    );
    expect(_Probe.isDark, isFalse);
    expect(_Probe.accent, ThemeColor.cyan.accent);
    // Light, buttons and text cursors take the darker shade.
    expect(_Probe.primary, ThemeColor.cyan.ink);

    await settings.appearance.set(Appearance.dark);
    await settings.themeColor.set(ThemeColor.red);
    await tester.pump();
    expect(_Probe.isDark, isTrue);
    expect(_Probe.accent, ThemeColor.red.accent);
    expect(_Probe.primary, ThemeColor.red.accent);

    // Back to the phone's.
    await settings.appearance.set(Appearance.system);
    await tester.pump();
    expect(_Probe.isDark, isFalse);
  });
}
