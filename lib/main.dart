import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chan/blocs/bookmarks_model.dart';
import 'package:flutter_chan/blocs/favorite_model.dart';
import 'package:flutter_chan/blocs/gallery_model.dart';
import 'package:flutter_chan/blocs/saved_attachments_model.dart';
import 'package:flutter_chan/blocs/settings_model.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/blocs/watched_media_model.dart';
import 'package:flutter_chan/pages/boards/board_list.dart';
import 'package:provider/provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (FlutterErrorDetails details) {
    print('Error From INSIDE FRAME_WORK');
    print('----------------------');
    print('Error :  ${details.exception}');
    print('StackTrace :  ${details.stack}');
  };
  runApp(const MyApp()); // starting point of app
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeChanger>(
          create: (_) => ThemeChanger(ThemeData.dark()),
        ),
        ChangeNotifierProvider<BookmarksProvider>(
          create: (_) => BookmarksProvider([]),
        ),
        ChangeNotifierProvider<FavoriteProvider>(
          create: (_) => FavoriteProvider([]),
        ),
        ChangeNotifierProvider<SettingsProvider>(
          create: (_) => SettingsProvider(),
        ),
        ChangeNotifierProvider<GalleryProvider>(
          create: (_) => GalleryProvider(),
        ),
        ChangeNotifierProvider<SavedAttachmentsProvider>(
          create: (_) => SavedAttachmentsProvider([]),
        ),
        ChangeNotifierProvider<WatchedMediaProvider>(
          create: (_) => WatchedMediaProvider(),
          lazy: false,
        ),
      ],
      child: const AppWithTheme(),
    );
  }
}

class AppWithTheme extends StatefulWidget {
  const AppWithTheme({Key? key}) : super(key: key);

  @override
  State<AppWithTheme> createState() => _AppWithThemeState();
}

class _AppWithThemeState extends State<AppWithTheme>
    with WidgetsBindingObserver {
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
    final Brightness brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;

    final theme = Provider.of<ThemeChanger>(context, listen: false);

    theme.setTheme(
      brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light(),
    );

    super.didChangePlatformBrightness();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeChanger>(context);

    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      home: const BoardList(),
      theme: CupertinoThemeData(
        brightness: theme.getTheme() == ThemeData.dark()
            ? Brightness.dark
            : Brightness.light,
      ),
      localizationsDelegates: const [
        DefaultCupertinoLocalizations.delegate,
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
    );
  }
}
