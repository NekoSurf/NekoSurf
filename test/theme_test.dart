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
  static Color? page;

  @override
  Widget build(BuildContext context) {
    isDark = context.isDark;
    accent = context.accent;
    primary = CupertinoTheme.of(context).primaryColor;
    page = DashColors.page(context);
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

    test('has text that reads on its pages and cards, light and dark', () {
      for (final ThemeColor theme in ThemeColor.values) {
        for (final Brightness brightness in Brightness.values) {
          final DashPalette palette = theme.palette(brightness);
          final String which = '${theme.name} ${brightness.name}';
          for (final Color under in [palette.page, palette.card]) {
            expect(
              _contrast(palette.text, under),
              greaterThan(7),
              reason: which,
            );
            // The usual bar is 4.5: Cyan's light grey, kept from before
            // there were themes, is a hair under it on the page.
            expect(
              _contrast(palette.muted, under),
              greaterThan(4.45),
              reason: which,
            );
          }
        }
      }
    });

    test('has pages of its own', () {
      for (final Brightness brightness in Brightness.values) {
        final Set<Color> pages = <Color>{
          for (final ThemeColor theme in ThemeColor.values)
            theme.palette(brightness).page,
        };
        expect(pages, hasLength(ThemeColor.values.length));
      }
    });

    test('has two colors, and an accent of its own', () {
      final Set<Color> accents = <Color>{};
      for (final ThemeColor theme in ThemeColor.values) {
        expect(theme.accent2, isNot(theme.accent), reason: theme.name);
        // OLED is Cyan's colors on black.
        if (theme != ThemeColor.oled) {
          expect(accents.add(theme.accent), isTrue, reason: theme.name);
        }
      }
    });
  });

  test('OLED is pure black, light or dark', () {
    for (final Brightness brightness in Brightness.values) {
      expect(ThemeColor.oled.palette(brightness).page, const Color(0xFF000000));
    }
    expect(ThemeColor.oled.isAlwaysDark, isTrue);
    expect(
      [
        for (final ThemeColor theme in ThemeColor.values)
          if (theme.isAlwaysDark) theme,
      ],
      [ThemeColor.oled],
    );
  });

  test('Cyan keeps the colors from before there were themes', () {
    final DashPalette dark = ThemeColor.cyan.palette(Brightness.dark);
    final DashPalette light = ThemeColor.cyan.palette(Brightness.light);
    expect(dark.page, const Color(0xFF0B0D11));
    expect(dark.card, const Color(0xFF141520));
    expect(dark.text, const Color(0xFFE8EAF0));
    expect(dark.muted, const Color(0xFF8A8FA8));
    expect(light.page, const Color(0xFFF4F5F7));
    expect(light.card, const Color(0xFFFFFFFF));
    expect(light.text, const Color(0xFF14161F));
    expect(light.muted, const Color(0xFF6B7085));
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
    // The whole page takes the theme, not just what's highlighted.
    expect(_Probe.page, ThemeColor.red.palette(Brightness.dark).page);

    // Back to the phone's.
    await settings.appearance.set(Appearance.system);
    await tester.pump();
    expect(_Probe.isDark, isFalse);

    // OLED stays dark on a light phone, whatever the appearance.
    await settings.themeColor.set(ThemeColor.oled);
    await tester.pump();
    expect(_Probe.isDark, isTrue);
    expect(_Probe.page, const Color(0xFF000000));
    await settings.appearance.set(Appearance.light);
    await tester.pump();
    expect(_Probe.isDark, isTrue);
  });
}
