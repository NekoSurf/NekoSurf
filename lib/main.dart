import 'dart:async';

import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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
import 'package:flutter_chan/settings/settings_model.dart';
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
  final SettingsProvider settings = SettingsProvider(prefs);
  unawaited(
    VideoServer.instance.setMaxCacheBytes(
      settings.videoCacheMegabytes.value * megabyte,
    ),
  );
  unawaited(deleteSaveLeftovers());
  unawaited(deleteOldImageCache());
  runApp(MyApp(prefs: prefs, settings: settings));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.prefs, required this.settings});

  final SharedPreferences prefs;
  final SettingsProvider settings;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<BookmarksProvider>(
          create: (_) => BookmarksProvider(prefs),
        ),
        ChangeNotifierProvider<FavoriteProvider>(
          create: (_) => FavoriteProvider(prefs),
        ),
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<HistoryProvider>(
          create: (_) => HistoryProvider(prefs, settings),
        ),
        ChangeNotifierProvider<SavedAttachmentsProvider>(
          create: (_) => SavedAttachmentsProvider(prefs),
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
  const AppWithTheme({super.key});

  @override
  State<AppWithTheme> createState() => _AppWithThemeState();
}

class _AppWithThemeState extends State<AppWithTheme>
    with WidgetsBindingObserver {
  // Stays with the app's one navigator; an observer can't watch two.
  final UnfocusOnPushObserver _unfocusOnPush = UnfocusOnPushObserver();

  Brightness _brightness =
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
      _brightness =
          WidgetsBinding.instance.platformDispatcher.platformBrightness;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      onGenerateInitialRoutes: (_) => [homeRoute(const AppShell())],
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
      theme: CupertinoThemeData(brightness: _brightness),
      localizationsDelegates: const [
        DefaultCupertinoLocalizations.delegate,
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
    );
  }
}
