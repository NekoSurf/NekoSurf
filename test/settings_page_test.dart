import 'package:flutter/material.dart';
import 'package:flutter_chan/history/history_model.dart';
import 'package:flutter_chan/history/watched_posts_model.dart';
import 'package:flutter_chan/settings/appearance_settings.dart';
import 'package:flutter_chan/settings/settings.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/dash_scaffold.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SettingsProvider settings;
  late WatchedPostsProvider watched;

  Future<void> pumpSettings(WidgetTester tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'NekoSurf',
      packageName: 'nekosurf',
      version: '1.2.3',
      buildNumber: '4',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    settings = SettingsProvider(prefs);
    watched = WatchedPostsProvider(prefs, settings);
    addTearDown(watched.dispose);

    await tester.binding.setSurfaceSize(const Size(400, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<WatchedPostsProvider>.value(value: watched),
          ChangeNotifierProvider<HistoryProvider>(
            create: (_) => HistoryProvider(prefs, settings),
          ),
        ],
        child: const MaterialApp(
          home: DashScaffold(title: 'Settings', slivers: [Settings()]),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('every setting is on the one page', (tester) async {
    await pumpSettings(tester);

    for (final String title in const [
      'Appearance',
      'Color',
      'Sort by',
      'Direction',
      'View',
      'Allow NSFW boards',
      'Auto-scroll to last seen',
      'Layout',
      'Start feed videos muted',
      'Data saver',
      "Use 4chan's file names",
      'Add filter',
      'Track history',
      'Keep watched posts',
      'Clear watched posts',
      'Clear recently visited',
      'Video cache limit',
      'Clear video cache',
      'Clear image cache',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(find.text('NekoSurf'), findsOneWidget);
  });

  testWidgets('choices change right there', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();
    expect(settings.boardViewMode.value, ViewMode.list);

    await tester.tap(find.text('Flat'));
    await tester.pumpAndSettle();
    expect(settings.threadLayout.value, ThreadLayout.flat);
  });

  testWidgets('the theme is chosen right there', (tester) async {
    await pumpSettings(tester);
    expect(find.text('Cyan'), findsOneWidget);
    expect(find.byType(ThemeSwatch), findsNWidgets(ThemeColor.values.length));

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(settings.appearance.value, Appearance.dark);
    expect(find.text('Dark'), findsOneWidget);

    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is ThemeSwatch && widget.theme == ThemeColor.red,
      ),
    );
    await tester.pump();
    expect(settings.themeColor.value, ThemeColor.red);
    expect(find.text('Red'), findsOneWidget);
    expect(find.text('Cyan'), findsNothing);
  });

  testWidgets('clearing watched posts asks first', (tester) async {
    await pumpSettings(tester);
    watched.noteThreadPosts(1, const <int>[1, 2]);
    await tester.pump(const Duration(seconds: 3));

    await tester.tap(find.text('Clear watched posts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(watched.threadMemory(1), isNotNull);

    await tester.tap(find.text('Clear watched posts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(watched.threadMemory(1), isNull);

    // The toast saying so goes away by itself.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('caches clear without asking', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Clear image cache'));
    await tester.pump();
    expect(find.text('Cancel'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
