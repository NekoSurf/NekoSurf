import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chan/blocs/theme.dart';
import 'package:flutter_chan/pages/boards/board_list.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/constants/glass_defaults.dart';
import 'package:liquid_glass_widgets/liquid_glass_setup.dart';
import 'package:liquid_glass_widgets/theme/glass_theme_data.dart';
import 'package:liquid_glass_widgets/theme/glass_theme_settings.dart';
import 'package:liquid_glass_widgets/types/glass_quality.dart';
import 'package:liquid_glass_widgets/types/glass_specular_sharpness.dart';
import 'package:media_kit/media_kit.dart';
import 'package:visibility_detector/visibility_detector.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await FFmpegKitExtended.initialize();
  await LiquidGlassWidgets.initialize();
  VisibilityDetectorController.instance.updateInterval = const Duration(
    milliseconds: 16,
  );
  FlutterError.onError = (FlutterErrorDetails details) {
    print('Error From INSIDE FRAME_WORK');
    print('----------------------');
    print('Error :  ${details.exception}');
    print('StackTrace :  ${details.stack}');
  };
  runApp(
    ProviderScope(
      child: LiquidGlassWidgets.wrap(
        theme: const GlassThemeData(
          light: GlassThemeVariant(
            settings: GlassThemeSettings(
              blur: 2,
              chromaticAberration: 0.15,
              lightAngle: GlassDefaults.lightAngle,
              lightIntensity: .3,
              ambientStrength: 0,
              refractiveIndex: 1.2,
              saturation: 1.2,
              specularSharpness: GlassSpecularSharpness.medium,
            ),
            quality: GlassQuality.standard,
          ),
          dark: GlassThemeVariant(
            settings: GlassThemeSettings(
              blur: 2,
              chromaticAberration: 0.15,
              lightAngle: GlassDefaults.lightAngle,
              lightIntensity: .3,
              ambientStrength: 0,
              refractiveIndex: 1.2,
              saturation: 1.2,
              specularSharpness: GlassSpecularSharpness.medium,
            ),
            quality: GlassQuality.standard,
          ),
        ),
        child: const MyApp(),
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const AppWithTheme();
  }
}

class AppWithTheme extends ConsumerStatefulWidget {
  const AppWithTheme({Key? key}) : super(key: key);

  @override
  ConsumerState<AppWithTheme> createState() => _AppWithThemeState();
}

class _AppWithThemeState extends ConsumerState<AppWithTheme>
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

    ref.read(themeProvider.notifier).setTheme(
      brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light(),
    );

    super.didChangePlatformBrightness();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);

    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      home: const BoardList(),
      theme: CupertinoThemeData(
        brightness: theme == ThemeData.dark() ? Brightness.dark : Brightness.light,
      ),
      localizationsDelegates: const [
        DefaultCupertinoLocalizations.delegate,
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
    );
  }
}
