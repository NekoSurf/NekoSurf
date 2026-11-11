import 'dart:async';

import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chan/board/favorite_model.dart';
import 'package:flutter_chan/bookmarks/bookmarks_model.dart';
import 'package:flutter_chan/history/history_model.dart';
import 'package:flutter_chan/history/watched_posts_model.dart';
import 'package:flutter_chan/home/app_shell.dart';
import 'package:flutter_chan/home/routes.dart';
import 'package:flutter_chan/media/image_cache.dart';
import 'package:flutter_chan/media/video_server.dart';
import 'package:flutter_chan/saved/downloads.dart';
import 'package:flutter_chan/saved/saved_attachments_model.dart';
import 'package:flutter_chan/settings/backup.dart';
import 'package:flutter_chan/settings/settings_model.dart';
import 'package:flutter_chan/settings/synced_items.dart';
import 'package:flutter_chan/sync/cloud_sync.dart';
import 'package:flutter_chan/ui/app_restart.dart';
import 'package:flutter_chan/ui/colors.dart';
import 'package:flutter_chan/ui/fast_page_transitions.dart';
import 'package:flutter_chan/ui/unfocus_on_push.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await FFmpegKitExtended.initialize();
  VisibilityDetectorController.instance.updateInterval = const Duration(
    milliseconds: 16,
  );
  // Errors from async code outside the framework go the same way as the
  // framework's own (FlutterError.onError, which prints them), so there's
  // one place to hook in logging.
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stack, library: 'NekoSurf'),
    );
    return true;
  };
  // Loaded before the first frame, so it shows the saved settings,
  // favorites and bookmarks rather than defaults.
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  CloudSync.instance.storedItems = storedSyncItems;
  unawaited(CloudSync.instance.load(prefs));
  final SettingsProvider settings = SettingsProvider(prefs);
  unawaited(
    VideoServer.instance.setMaxCacheBytes(
      settings.videoCacheMegabytes.value * megabyte,
    ),
  );
  unawaited(deleteSaveLeftovers());
  unawaited(deleteOldImageCache());
  runApp(AppRoot(prefs: prefs, settings: settings));
}

/// The app, taken down and built again for a restored backup
/// ([AppRestart]). What iCloud sync has to send goes when it's left, and
/// what changed elsewhere is fetched when it's back.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key, required this.prefs, required this.settings});

  final SharedPreferences prefs;
  final SettingsProvider settings;

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  late SettingsProvider _settings = widget.settings;
  Key _app = UniqueKey();
  bool _down = false;
  Object? _failure;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () => unawaited(CloudSync.instance.flush()),
      onResume: () => unawaited(CloudSync.instance.fetchQuietly()),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _restart(Future<void> Function() work) async {
    setState(() => _down = true);
    // The app is gone after this frame, and what it had loaded has written
    // what it still had to: none of that can land on top of [work]'s.
    await WidgetsBinding.instance.endOfFrame;
    Object? failure;
    try {
      await work();
    } catch (e) {
      debugPrint('Restoring failed: $e');
      failure = e;
    }
    final SettingsProvider old = _settings;
    _settings = SettingsProvider(widget.prefs);
    old.dispose();
    unawaited(
      VideoServer.instance.setMaxCacheBytes(
        _settings.videoCacheMegabytes.value * megabyte,
      ),
    );
    if (!mounted) {
      return;
    }
    if (failure == null) {
      _comeBack();
    } else {
      setState(() => _failure = failure);
    }
  }

  void _comeBack() {
    setState(() {
      _down = false;
      _failure = null;
      _app = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppRestart(
      prefs: widget.prefs,
      restart: _restart,
      child: _down
          ? _Restoring(failure: _failure, onDone: _comeBack)
          : MyApp(key: _app, prefs: widget.prefs, settings: _settings),
    );
  }
}

/// While a backup is restored, and what went wrong if it didn't work.
///
/// Plain widgets, not an app: an app's navigator would take the focus, and
/// the app's own navigator, coming back in the same frame, would find it in
/// a page that's half gone (UnfocusOnPushObserver).
class _Restoring extends StatelessWidget {
  const _Restoring({required this.failure, required this.onDone});

  final Object? failure;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final bool isDark =
        View.of(context).platformDispatcher.platformBrightness ==
        Brightness.dark;
    final Color text = isDark ? Colors.white : Colors.black;
    final Object? failure = this.failure;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: isDark ? Colors.black : Colors.white,
        child: DefaultTextStyle(
          style: TextStyle(
            color: text,
            fontSize: 15,
            decoration: TextDecoration.none,
          ),
          textAlign: TextAlign.center,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: failure == null
                    ? [
                        CupertinoActivityIndicator(radius: 14, color: text),
                        const SizedBox(height: 16),
                        const Text('Restoring your backup…'),
                      ]
                    : [
                        const Text(
                          "Couldn't restore the backup",
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          failure is NotABackup
                              ? '$failure'
                              : 'Nothing was changed. ($failure)',
                        ),
                        const SizedBox(height: 20),
                        GestureDetector(
                          onTap: onDone,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: text.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'OK',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.prefs, required this.settings});

  final SharedPreferences prefs;
  final SettingsProvider settings;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Not lazy: iCloud sync applies changes made elsewhere to all of
        // them, once they're all there.
        ChangeNotifierProvider<BookmarksProvider>(
          create: (_) => BookmarksProvider(prefs),
          lazy: false,
        ),
        ChangeNotifierProvider<FavoriteProvider>(
          create: (_) => FavoriteProvider(prefs),
          lazy: false,
        ),
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<HistoryProvider>(
          create: (_) => HistoryProvider(prefs, settings),
          lazy: false,
        ),
        ChangeNotifierProvider<SavedAttachmentsProvider>(
          create: (_) => SavedAttachmentsProvider(prefs),
          lazy: false,
        ),
        ChangeNotifierProvider<WatchedPostsProvider>(
          create: (_) => WatchedPostsProvider(prefs, settings),
          lazy: false,
        ),
      ],
      child: const AppWithTheme(),
    );
  }
}

class AppWithTheme extends StatefulWidget {
  const AppWithTheme({super.key, this.home = const AppShell()});

  /// The page the app opens on.
  final Widget home;

  @override
  State<AppWithTheme> createState() => _AppWithThemeState();
}

class _AppWithThemeState extends State<AppWithTheme>
    with WidgetsBindingObserver {
  // Stays with the app's one navigator; an observer can't watch two.
  final UnfocusOnPushObserver _unfocusOnPush = UnfocusOnPushObserver();

  Brightness _phoneBrightness =
      WidgetsBinding.instance.platformDispatcher.platformBrightness;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    setState(() {
      _phoneBrightness =
          WidgetsBinding.instance.platformDispatcher.platformBrightness;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeColor themeColor = context.select<SettingsProvider, ThemeColor>(
      (s) => s.themeColor.value,
    );
    final Brightness brightness = themeColor.isAlwaysDark
        ? Brightness.dark
        : context
              .select<SettingsProvider, Appearance>((s) => s.appearance.value)
              .brightness(_phoneBrightness);
    final bool isDark = brightness == Brightness.dark;

    return DashTheme(
      color: themeColor,
      // The app can be dark on a light phone: the status bar goes by the app.
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarBrightness: brightness,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        ),
        child: _buildApp(brightness, themeColor),
      ),
    );
  }

  Widget _buildApp(Brightness brightness, ThemeColor themeColor) {
    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      onGenerateInitialRoutes: (_) => [homeRoute(widget.home)],
      onGenerateRoute: generateRoute,
      navigatorObservers: [_unfocusOnPush],
      // Beyond this, fixed-size cards and rows cut their text off.
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Theme(
          data: Theme.of(context).copyWith(
            pageTransitionsTheme: PageTransitionsTheme(
              builders: {
                for (final platform in TargetPlatform.values)
                  platform:
                      platform == TargetPlatform.iOS ||
                          platform == TargetPlatform.macOS
                      ? const CupertinoPageTransitionsBuilder()
                      : const FastCupertinoTransitionsBuilder(),
              },
            ),
          ),
          child: child!,
        ),
      ),
      // Text cursors and selection, and buttons without a color of their own.
      theme: CupertinoThemeData(
        brightness: brightness,
        primaryColor: brightness == Brightness.dark
            ? themeColor.accent
            : themeColor.ink,
        scaffoldBackgroundColor: themeColor.palette(brightness).page,
        barBackgroundColor: themeColor.palette(brightness).card,
      ),
      localizationsDelegates: const [
        DefaultCupertinoLocalizations.delegate,
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
    );
  }
}
