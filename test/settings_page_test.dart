import 'package:flutter/material.dart';
import 'package:flutter_chan/history/history_model.dart';
import 'package:flutter_chan/history/watched_posts_model.dart';
import 'package:flutter_chan/saved/saved_attachments_model.dart';
import 'package:flutter_chan/saved/saved_folders.dart';
import 'package:flutter_chan/settings/appearance_settings.dart';
import 'package:flutter_chan/settings/settings.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/settings/settings_widgets.dart';
import 'package:flutter_chan/thread/post_hiding.dart';
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
    watched = WatchedPostsProvider(prefs);
    addTearDown(watched.dispose);

    await tester.binding.setSurfaceSize(const Size(400, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<WatchedPostsProvider>.value(value: watched),
          ChangeNotifierProvider<HistoryProvider>(
            create: (_) => HistoryProvider(prefs, settings),
          ),
          ChangeNotifierProvider<SavedAttachmentsProvider>(
            create: (_) => SavedAttachmentsProvider(
              prefs,
              syncFolders: () async => const SavedFolders(
                media: '/nonexistent/media',
                thumbnails: '/nonexistent/thumbnails',
              ),
            ),
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
      'Auto-scroll to last seen',
      'Layout',
      'Start feed videos muted',
      'Data saver',
      "Use 4chan's file names",
      'Allow NSFW boards',
      'Turn on each time',
      'Cover NSFW images',
      'Show the Saved tab',
      'Keep saved files in the app',
      'Ask before saving to Photos',
      'Hide in the app switcher',
      'Track history',
      'Only while the app is open',
      'Clear cache',
      'Send feedback',
      'Privacy policy',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(find.text('NekoSurf'), findsOneWidget);
    // One for threads, one for posts.
    expect(find.text('Add filter'), findsNWidgets(2));
  });

  testWidgets('post filters are listed, and come off with a tap', (
    tester,
  ) async {
    await pumpSettings(tester);
    await settings.addPostFilter(PostFilter(PostFilterKind.name, 'Bob'));
    await settings.addPostFilter(PostFilter(PostFilterKind.country, 'France'));
    await tester.pump();
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('From France'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Remove Bob'));
    await tester.pump();
    expect(find.text('Bob'), findsNothing);
    expect(settings.postFilters, [
      PostFilter(PostFilterKind.country, 'France'),
    ]);
  });

  testWidgets('a post filter can be typed in', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Add filter').last);
    await tester.pumpAndSettle();
    expect(find.text('Hide posts matching'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'crypto');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(settings.postFilters, [PostFilter(PostFilterKind.text, 'crypto')]);
    expect(find.text('“crypto”'), findsOneWidget);
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

  testWidgets('OLED says it is always dark', (tester) async {
    await pumpSettings(tester);

    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is ThemeSwatch && widget.theme == ThemeColor.oled,
      ),
    );
    await tester.pump();
    expect(settings.themeColor.value, ThemeColor.oled);
    expect(find.text('OLED'), findsOneWidget);
    expect(find.text('OLED is always dark'), findsOneWidget);

    // Nothing to choose: it's dark either way.
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Light'), findsNothing);
  });

  testWidgets('the NSFW choices can be changed once NSFW boards are allowed', (
    tester,
  ) async {
    await pumpSettings(tester);
    final Finder eachTime = find.descendant(
      of: find.ancestor(
        of: find.text('Turn on each time'),
        matching: find.byType(SettingsRow),
      ),
      matching: find.byType(SettingsSwitch),
    );
    await tester.tap(eachTime, warnIfMissed: false);
    await tester.pump();
    expect(settings.nsfwEachSession.value, isFalse);

    await settings.allowNSFW.set(true);
    await tester.pumpAndSettle();
    await tester.tap(eachTime);
    await tester.pump();
    expect(settings.nsfwEachSession.value, isTrue);
  });

  testWidgets('caches clear without asking', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Clear cache'));
    await tester.pump();
    expect(find.text('Cancel'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
